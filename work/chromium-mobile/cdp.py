#!/usr/bin/env python3
"""Minimal raw-WebSocket CDP client for driving the deployed Chromium.

No external deps (websocket-client is not installed on the phone). Implements just enough
RFC6455 (text frames, client masking, ping/pong) to talk to Chrome DevTools Protocol.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import time
import urllib.request

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def _ws_connect(url):
    # ws://host:port/path
    assert url.startswith("ws://")
    rest = url[5:]
    hostport, _, path = rest.partition("/")
    path = "/" + path
    host, _, port = hostport.partition(":")
    port = int(port or 80)
    s = socket.create_connection((host, port), timeout=10)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = s.recv(4096)
        if not chunk:
            raise ConnectionError("ws handshake closed")
        resp += chunk
    if b"101" not in resp.split(b"\r\n", 1)[0]:
        raise ConnectionError("ws handshake failed: " + resp.split(b"\r\n", 1)[0].decode(errors="replace"))
    return s


def _ws_send(s, text):
    data = text.encode()
    header = bytearray([0x81])  # FIN + text
    n = len(data)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", n)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", n)
    mask = os.urandom(4)
    header += mask
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    s.sendall(bytes(header) + masked)


def _ws_recv(s):
    def rd(n):
        buf = b""
        while len(buf) < n:
            c = s.recv(n - len(buf))
            if not c:
                raise ConnectionError("ws closed")
            buf += c
        return buf

    b1, b2 = rd(2)
    opcode = b1 & 0x0F
    masked = b2 & 0x80
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack(">H", rd(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", rd(8))[0]
    mask = rd(4) if masked else None
    payload = rd(length)
    if mask:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    if opcode == 0x8:  # close
        raise ConnectionError("ws close frame")
    if opcode == 0x9:  # ping -> pong
        return _ws_recv(s)
    return payload.decode(errors="replace")


class CDP:
    def __init__(self, port=9222, timeout=10):
        self.port = port
        self._id = 0
        target = self._find_page(port, timeout)
        self.ws = _ws_connect(target["webSocketDebuggerUrl"])

    @staticmethod
    def _find_page(port, timeout):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                data = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=3))
                pages = [t for t in data if t.get("type") == "page"]
                if pages:
                    return pages[0]
            except Exception as e:  # noqa: BLE001
                last = e
            time.sleep(0.5)
        raise RuntimeError(f"no CDP page target on :{port}: {last}")

    def call(self, method, params=None):
        self._id += 1
        mid = self._id
        _ws_send(self.ws, json.dumps({"id": mid, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(_ws_recv(self.ws))
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    def send_nowait(self, method, params=None):
        self._id += 1
        _ws_send(self.ws, json.dumps({"id": self._id, "method": method, "params": params or {}}))

    def close(self):
        try:
            self.ws.close()
        except Exception:  # noqa: BLE001
            pass


if __name__ == "__main__":
    c = CDP()
    print(c.call("Browser.getVersion"))
    c.close()
