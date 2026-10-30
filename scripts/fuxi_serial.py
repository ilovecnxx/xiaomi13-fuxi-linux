#!/usr/bin/env python3
"""通过 g_serial（/dev/fuxi-acm）在主线内核的 initramfs shell 里执行命令。

用法: fuxi_serial.py <tty> <outdir> [cmd ...]
  - 先 `touch /tmp/keep /tmp/stay`：取消 init 的 180 秒安全重启，并留在 initramfs
    （不 touch /tmp/stay 的话，init 在 USB 就绪 8 秒后自动 switch_root 进 UFS 上的 Ubuntu）
  - 依次执行 cmd，每条输出写到 <outdir>/cmd-NN.txt
  - 最后保存完整 dmesg 到 <outdir>/dmesg.txt
  - 全部原始串口流追加到 <outdir>/acm-raw.log
退出码: 0 = 全部命令执行完; 2 = 串口打不开/无 shell 响应
"""
import os
import sys
import time

import serial

# 回显里出现的是 __FUXI_""END__，只有真正的输出才是 __FUXI_END__
END = b"__FUXI_END__"


class Shell:
    def __init__(self, dev, raw_path):
        self.port = serial.Serial(dev, 115200, timeout=0.2)
        self.raw = open(raw_path, "ab")

    def _read_until(self, marker, timeout):
        buf = b""
        t0 = time.time()
        while time.time() - t0 < timeout:
            chunk = self.port.read(4096)
            if chunk:
                self.raw.write(chunk)
                self.raw.flush()
                buf += chunk
                if marker in buf:
                    return buf
        return None

    def run(self, cmd, timeout=60):
        line = f'{cmd}; echo "__FUXI_""END__ rc=$?"\n'
        self.port.write(line.encode())
        out = self._read_until(END, timeout)
        if out is None:
            return None
        text = out.decode(errors="replace").replace("\r", "")
        body, _, tail = text.partition("__FUXI_END__")
        # 去掉命令回显行（回显里带 __FUXI_""END__）
        lines = [l for l in body.split("\n") if '__FUXI_""END__' not in l]
        return "\n".join(lines).strip("\n") + "\n" + tail.split("\n")[0].strip()

    def alive(self, tries=10):
        for _ in range(tries):
            self.port.write(b"\n")
            if self.run("echo ping", timeout=3) is not None:
                return True
        return False


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    dev, outdir, cmds = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(outdir, exist_ok=True)
    try:
        sh = Shell(dev, os.path.join(outdir, "acm-raw.log"))
    except serial.SerialException as e:
        print(f"open {dev} failed: {e}")
        return 2
    if not sh.alive():
        print("shell 无响应")
        return 2
    sh.run("touch /tmp/keep /tmp/stay")
    for i, cmd in enumerate(cmds):
        out = sh.run(cmd, timeout=120)
        with open(os.path.join(outdir, f"cmd-{i:02d}.txt"), "w") as f:
            f.write(f"$ {cmd}\n{out if out is not None else '<<TIMEOUT>>'}\n")
        print(f"[{i:02d}] {cmd} -> {'timeout' if out is None else 'ok'}")
    dm = sh.run("dmesg", timeout=60)
    with open(os.path.join(outdir, "dmesg.txt"), "w") as f:
        f.write(dm if dm is not None else "<<TIMEOUT>>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
