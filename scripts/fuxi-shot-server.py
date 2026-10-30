#!/usr/bin/env python3
"""手机截图小工具 —— 本地网页界面，点按钮就抓一张 fuxi 手机屏并存到电脑。

用法:
    python3 scripts/fuxi-shot-server.py          # 默认 127.0.0.1:8099
    PORT=8123 python3 scripts/fuxi-shot-server.py

接口:
    GET  /                网页界面
    GET  /api/list        最近截图列表 + 保存目录
    GET  /shot/<文件名>   取图
    POST /api/shot        {"note": "可选备注"} → 抓一张
    POST /api/open        {"name": "文件名"}    → 用系统看图软件打开
    POST /api/folder      打开截图文件夹
"""
from __future__ import annotations

import json
import mimetypes
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

B = Path(__file__).resolve().parent.parent
SHOT_SCRIPT = B / "scripts" / "fuxi-shot.sh"
UI_FILE = B / "scripts" / "fuxi-shot-ui.html"
PORT = int(os.environ.get("PORT", "8099"))
HOST = os.environ.get("HOST", "127.0.0.1")


def _pictures_dir() -> Path:
    try:
        out = subprocess.run(
            ["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except Exception:
        out = ""
    return Path(out or (Path.home() / "Pictures"))


OUT_DIR = Path(os.environ.get("OUTDIR", _pictures_dir() / "手机截图"))
_LOCK = threading.Lock()  # 一次只抓一张，避免并发冲突


def _safe_note(note: str) -> str:
    note = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff._-]+", "-", note).strip("-")
    return note[:40]


def capture(note: str = "") -> dict:
    ts = time.strftime("%Y%m%d-%H%M%S")
    suffix = f"-{s}" if (s := _safe_note(note)) else ""
    name = f"shot-{ts}{suffix}"
    with _LOCK:
        try:
            proc = subprocess.run(
                [str(SHOT_SCRIPT), name],
                capture_output=True,
                text=True,
                timeout=40,
                cwd=str(B),
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError("截图超时（手机无响应？）") from None
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip().splitlines()
        raise RuntimeError(detail[-1] if detail else f"截图脚本退出码 {proc.returncode}")
    lines = [ln for ln in proc.stdout.strip().splitlines() if ln.strip()]
    path = Path(lines[-1]) if lines else OUT_DIR / f"{name}.png"
    if not path.is_file():
        raise RuntimeError(f"截图文件不存在：{path}")
    return _entry(path)


def _entry(path: Path) -> dict:
    st = path.stat()
    return {
        "name": path.name,
        "path": str(path),
        "url": "/shot/" + urllib.parse.quote(path.name),
        "size": st.st_size,
        "mtime": time.strftime("%H:%M:%S", time.localtime(st.st_mtime)),
        "ts": st.st_mtime,
    }


def list_shots(limit: int = 60) -> list[dict]:
    if not OUT_DIR.is_dir():
        return []
    files = sorted(OUT_DIR.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
    return [_entry(p) for p in files[:limit]]


def open_with_system(path: Path) -> None:
    subprocess.Popen(
        ["xdg-open", str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "FuxiShot/1.0"

    def log_message(self, fmt: str, *args) -> None:  # 安静一点
        sys.stderr.write("[%s] %s\n" % (time.strftime("%H:%M:%S"), fmt % args))

    # ---- helpers -------------------------------------------------------
    def _send(self, code: int, body: bytes, ctype: str = "text/plain; charset=utf-8") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code: int, payload: dict) -> None:
        self._send(code, json.dumps(payload, ensure_ascii=False).encode(), "application/json; charset=utf-8")

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except Exception:
            return {}

    # ---- routes --------------------------------------------------------
    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path in ("/", "/index.html"):
            return self._send(200, UI_FILE.read_bytes(), "text/html; charset=utf-8")
        if path == "/api/list":
            return self._json(200, {"ok": True, "dir": str(OUT_DIR), "shots": list_shots()})
        if path.startswith("/shot/"):
            name = os.path.basename(urllib.parse.unquote(path[len("/shot/"):]))
            target = (OUT_DIR / name).resolve()
            if target.parent != OUT_DIR.resolve() or not target.is_file():
                return self._send(404, b"not found")
            ctype = mimetypes.guess_type(str(target))[0] or "application/octet-stream"
            return self._send(200, target.read_bytes(), ctype)
        self._send(404, b"not found")

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        data = self._read_json()
        try:
            if path == "/api/shot":
                shot = capture(str(data.get("note") or ""))
                return self._json(200, {"ok": True, "shot": shot, "dir": str(OUT_DIR)})
            if path == "/api/open":
                name = os.path.basename(str(data.get("name") or ""))
                target = (OUT_DIR / name).resolve()
                if target.parent != OUT_DIR.resolve() or not target.is_file():
                    return self._json(404, {"ok": False, "error": "文件不存在"})
                open_with_system(target)
                return self._json(200, {"ok": True})
            if path == "/api/folder":
                OUT_DIR.mkdir(parents=True, exist_ok=True)
                open_with_system(OUT_DIR)
                return self._json(200, {"ok": True, "dir": str(OUT_DIR)})
        except RuntimeError as exc:
            return self._json(200, {"ok": False, "error": str(exc)})
        except Exception as exc:  # noqa: BLE001
            return self._json(500, {"ok": False, "error": f"{type(exc).__name__}: {exc}"})
        self._json(404, {"ok": False, "error": "not found"})


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.daemon_threads = True
    print(f"手机截图: http://{HOST}:{PORT}  →  {OUT_DIR}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
