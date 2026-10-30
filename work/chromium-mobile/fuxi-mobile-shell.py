#!/usr/bin/env python3
"""fuxi mobile Chromium shell — self-healing supervisor.

Keeps one Chromium (--app, Blink) window alive with the Android-Chrome-style overlay injected.
A background supervisor loop reconnects CDP and re-injects the overlay whenever needed, so the
UI survives the chromium singleton races and timing that happen at startup / after restarts.

Navigation in the page is handled by the injected JS (history/location) — the bridge is only a
convenience/inspection channel. All CDP calls are serialised on one lock.
"""
import json
import os
import signal
import subprocess
import sys
import threading
import time
import socketserver
import http.server
import urllib.parse
import base64

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cdp import CDP  # noqa: E402

CHROME = "/opt/chromium/root/usr/lib/chromium/chromium"
PRIVLIB = "/opt/chromium/privatelib"
HERE = os.path.dirname(os.path.abspath(__file__))
INJECT_JS = os.path.join(HERE, "mobile-chrome.js")
DEBUG_PORT = 9222
BRIDGE_PORT = 9223
HOME_URL = os.environ.get("FUXI_HOME", "https://www.example.com")

_lock = threading.Lock()
_cdp = None
_proc = None


def log(*a):
    print("[fuxi-mobile]", *a, file=sys.stderr, flush=True)


def overlay_js():
    js = open(INJECT_JS, encoding="utf-8").read()
    return js.replace("window.__FUXI_HOME__ || 'https://www.example.com'",
                      "window.__FUXI_HOME__ || %s" % json.dumps(HOME_URL))


def cdp_call(method, params=None):
    global _cdp
    with _lock:
        if _cdp is None:
            _cdp = CDP(port=DEBUG_PORT, timeout=10)
            _cdp.call("Page.enable")
        try:
            return _cdp.call(method, params)
        except Exception:
            try:
                _cdp.close()
            except Exception:
                pass
            _cdp = CDP(port=DEBUG_PORT, timeout=10)
            _cdp.call("Page.enable")
            return _cdp.call(method, params)


def launch():
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = PRIVLIB + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    args = [
        CHROME,
        "--user-data-dir=" + os.path.expanduser("~/.config/chromium-fuxi-mobile"),
        "--no-sandbox", "--test-type", "--disable-dev-shm-usage",
        "--ozone-platform=wayland", "--enable-features=UseOzonePlatform",
        "--disable-features=Vulkan", "--use-angle=gl", "--use-gl=angle",
        "--enable-gpu-rasterization", "--ignore-gpu-blocklist",
        "--password-store=basic", "--no-first-run", "--no-default-browser-check",
        "--remote-debugging-port=%d" % DEBUG_PORT,
        "--app=" + HOME_URL,
    ]
    if os.environ.get("CHROMIUM_SOFTWARE") == "1":
        args += ["--disable-gpu", "--disable-gpu-compositing"]
    return subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ensure_overlay():
    """Inject overlay into current page + register persistent script. Best-effort."""
    global _cdp
    js = overlay_js()
    with _lock:
        if _cdp is None:
            return False
        try:
            _cdp.call("Page.addScriptToEvaluateOnNewDocument", {"source": js})
            _cdp.call("Runtime.evaluate", {"expression": js, "awaitPromise": False})
            if os.environ.get("FUXI_FORCE_LIGHT") == "1":
                try:
                    _cdp.call("Emulation.setEmulatedMedia", {"features": [
                        {"name": "prefers-color-scheme", "value": "light"}]})
                except Exception:
                    pass
            try:
                _cdp.call("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
            except Exception:
                pass
            return True
        except Exception as e:
            log("ensure_overlay err:", e)
            try:
                _cdp.close()
            except Exception:
                pass
            _cdp = None
            return False


def supervisor():
    """Owns CDP: connect when possible, keep overlay present, reconnect on loss."""
    global _cdp
    last_ok = 0
    while True:
        time.sleep(2)
        if _proc is not None and _proc.poll() is not None:
            log("chromium gone; relaunching")
            try:
                globals()["_proc"] = launch()
            except Exception as e:
                log("relaunch err", e)
            _cdp = None
            time.sleep(3)
            continue
        try:
            if _cdp is None:
                c = CDP(port=DEBUG_PORT, timeout=6)
                with _lock:
                    _cdp = c
                try:
                    _cdp.call("Page.enable")
                    _cdp.call("Runtime.enable")
                except Exception as e:
                    log("enable err", e)
                    with _lock:
                        _cdp = None
                    continue
                ok = ensure_overlay()
                log("reconnected, overlay", "ok" if ok else "fail")
                last_ok = time.time()
            else:
                # verify overlay still present; re-inject if the page reloaded without it
                try:
                    r = cdp_call("Runtime.evaluate", {
                        "expression": "!!document.getElementById('fx-bottom')", "returnByValue": True})
                    present = r.get("result", {}).get("value")
                    if not present:
                        ensure_overlay()
                except Exception:
                    with _lock:
                        try:
                            _cdp.close()
                        except Exception:
                            pass
                        _cdp = None
        except Exception as e:
            log("supervisor loop err:", e)
            with _lock:
                if _cdp is not None:
                    try:
                        _cdp.close()
                    except Exception:
                        pass
                    _cdp = None
            time.sleep(2)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        try:
            if p.path == "/state":
                r = cdp_call("Runtime.evaluate", {
                    "expression": "JSON.stringify({u:location.href,t:document.title,b:!!document.getElementById('fx-bottom')})",
                    "returnByValue": True})
                self._send(200, "application/json", (r.get("result", {}).get("value") or "{}").encode())
            elif p.path == "/shot":
                r = cdp_call("Page.captureScreenshot", {"format": "png"})
                self._send(200, "image/png", base64.b64decode(r["data"]))
            elif p.path == "/eval":
                q = urllib.parse.parse_qs(p.query)
                r = cdp_call("Runtime.evaluate", {"expression": q.get("e", [""])[0], "returnByValue": True})
                self._send(200, "application/json", json.dumps(r.get("result", {})).encode())
            else:
                self._send(404, "text/plain", b"no")
        except Exception as e:
            self._send(500, "text/plain", str(e).encode())

    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(n) if n else b"{}"
            if urllib.parse.urlparse(self.path).path == "/navigate":
                url = json.loads(body).get("url", HOME_URL)
                cdp_call("Runtime.evaluate", {"expression": "location.href=" + json.dumps(url), "awaitPromise": False})
            self._send(200, "application/json", b'{"ok":true}')
        except Exception as e:
            self._send(500, "text/plain", str(e).encode())


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def bridge():
    with Server(("127.0.0.1", BRIDGE_PORT), Handler) as httpd:
        log("bridge on", BRIDGE_PORT)
        httpd.serve_forever()


def main():
    global _proc
    _proc = launch()
    log("chromium launched pid", _proc.pid)
    threading.Thread(target=bridge, daemon=True).start()
    threading.Thread(target=supervisor, daemon=True).start()

    def bye(*_):
        try:
            _proc.terminate()
        except Exception:
            pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGINT, bye)
    _proc.wait()
    log("chromium exited", _proc.returncode)
    return 0


if __name__ == "__main__":
    sys.exit(main())
