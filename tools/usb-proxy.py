#!/usr/bin/env python3
"""极简 HTTP/HTTPS 代理，用于 adb reverse 反向网络。

场景：手机没有可用的 Wi-Fi/IPv4 出口，但 USB 连着电脑。
  adb reverse tcp:8888 tcp:8888   → 手机 127.0.0.1:8888 落到电脑 127.0.0.1:8888
  chroot 里配 Acquire::http::Proxy "http://127.0.0.1:8888"
手机上的 apt/curl 就能借用电脑的网络。

支持：CONNECT 隧道（HTTPS）与绝对 URI 的普通 HTTP。
仅监听回环地址，不对外暴露。

用法: ./tools/usb-proxy.py [--port 8888] [--bind 127.0.0.1] [--quiet]
"""
import argparse
import socket
import sys
import threading

BUF = 65536


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def relay(a: socket.socket, b: socket.socket) -> None:
    """在两条 socket 之间双向搬运字节，任一端结束就拆掉双方。"""
    socks = [a, b]
    try:
        while True:
            readable, _, _ = _select(socks)
            if not readable:
                break
            for s in readable:
                data = s.recv(BUF)
                if not data:
                    return
                (b if s is a else a).sendall(data)
    except OSError:
        pass
    finally:
        for s in socks:
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def _select(socks):
    import select

    return select.select(socks, [], [], 300)


def read_headers(conn: socket.socket) -> bytes | None:
    """读到 \\r\\n\\r\\n 为止（含），上限 64KB。"""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = conn.recv(BUF)
        if not chunk:
            return None
        buf += chunk
        if len(buf) > 65536:
            return None
    return buf


def parse_authority(url: str) -> tuple[str, int, str]:
    """从绝对 URI 中取 (host, port, path)。"""
    rest = url.split("://", 1)[1]
    slash = rest.find("/")
    authority = rest if slash < 0 else rest[:slash]
    path = "/" if slash < 0 else rest[slash:]
    if authority.startswith("["):  # IPv6 字面量
        end = authority.index("]")
        host, port = authority[1:end], int(authority[end + 2 :] or 80)
    elif ":" in authority:
        host, port_s = authority.rsplit(":", 1)
        port = int(port_s)
    else:
        host, port = authority, 80
    return host, port, path


def handle(conn: socket.socket, peer, quiet: bool) -> None:
    try:
        head = read_headers(conn)
        if not head:
            conn.close()
            return
        first, _, rest = head.partition(b"\r\n")
        parts = first.decode("latin-1").split()
        if len(parts) < 3:
            conn.close()
            return
        method, target, version = parts[0], parts[1], parts[2]

        if method.upper() == "CONNECT":
            host, _, port_s = target.rpartition(":")
            port = int(port_s or 443)
            upstream = socket.create_connection((host, port), timeout=30)
            if not quiet:
                log(f"[proxy] CONNECT {host}:{port}")
            conn.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
            relay(conn, upstream)
            return

        if not target.startswith("http://"):
            conn.sendall(b"HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\n\r\n")
            conn.close()
            return

        host, port, path = parse_authority(target)
        # 头部原样转发，只把 request-line 改回 origin-form 并强制短连接
        headers = [
            line
            for line in rest.split(b"\r\n")
            if line and not line.lower().startswith((b"proxy-connection", b"connection", b"proxy-authorization"))
        ]
        out = [f"{method} {path} {version}".encode("latin-1")]
        out += headers
        out.append(b"Connection: close")
        out.append(b"")
        out.append(b"")
        if not quiet:
            log(f"[proxy] {method} {host}:{port}{path}")
        upstream = socket.create_connection((host, port), timeout=30)
        upstream.sendall(b"\r\n".join(out))
        relay(conn, upstream)
    except Exception as exc:  # noqa: BLE001 - 单个连接失败不应拖垮代理
        if not quiet:
            log(f"[proxy] 错误: {exc}")
        try:
            conn.close()
        except OSError:
            pass


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8888)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.bind, args.port))
    srv.listen(128)
    log(f"[proxy] 监听 {args.bind}:{args.port}  (USB 反向网络已就绪)")
    while True:
        conn, peer = srv.accept()
        threading.Thread(target=handle, args=(conn, peer, args.quiet), daemon=True).start()


if __name__ == "__main__":
    sys.exit(main())
