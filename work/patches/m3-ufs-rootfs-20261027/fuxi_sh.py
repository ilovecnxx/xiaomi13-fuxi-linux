#!/usr/bin/env python3
"""在手机的串口 shell（initramfs 或 systemd 自动登录的 bash）里执行命令，打印输出。

用法: fuxi_sh.py [-t 秒] [--send] cmd [cmd ...]
  -t      每条命令的超时（默认 60）
  --send  只发送最后一条命令、不等结束标记（用于 exit / switch_root 这类不会返回的命令）
退出码: 最后一条命令的 rc；2 = 串口打不开/无响应；3 = 超时
原始串口流追加到 work/claude-logs/fuxi-sh-raw.log
"""
import os
import re
import sys
import time

import serial

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fuxi_serial import Shell  # noqa: E402

ACM = os.environ.get("FUXI_ACM", "/dev/fuxi-acm")
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "work", "claude-logs", "fuxi-sh-raw.log")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07")


def main():
    args = sys.argv[1:]
    timeout, send_last = 60, False
    while args and args[0].startswith("-"):
        if args[0] == "-t":
            timeout = float(args[1])
            args = args[2:]
        elif args[0] == "--send":
            send_last = True
            args = args[1:]
        else:
            break
    if not args:
        print(__doc__)
        return 1
    try:
        sh = Shell(ACM, LOG)
    except serial.SerialException as e:
        print(f"open {ACM} failed: {e}")
        return 2
    if not sh.alive(tries=5):
        print("shell 无响应")
        return 2
    rc = 0
    for i, cmd in enumerate(args):
        if send_last and i == len(args) - 1:
            sh.port.write((cmd + "\n").encode())
            time.sleep(1)
            print(f"$ {cmd}\n(已发送，不等待返回)")
            return 0
        out = sh.run(cmd, timeout=timeout)
        if out is None:
            print(f"$ {cmd}\n<<TIMEOUT {timeout}s>>")
            return 3
        out = ANSI.sub("", out)
        print(f"$ {cmd}\n{out}")
        m = re.search(r"rc=(\d+)\s*$", out)
        rc = int(m.group(1)) if m else 0
    return rc


if __name__ == "__main__":
    sys.exit(main())
