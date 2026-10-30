#!/usr/bin/env python3
"""打包 ath12k board-2.bin（格式见 drivers/net/wireless/ath/ath12k/hw.h、core.c）。

  magic "QCA-ATH12K-BOARD\\0"（补齐到 4 字节）
  IE: <le32 id><le32 len><data，补齐到 4 字节>
    ATH12K_BD_IE_BOARD(0) 里嵌套 BOARD_NAME(0, 字符串) + BOARD_DATA(1, 数据)

用法: fuxi-ath12k-board.py <输出 board-2.bin> <板名=数据文件> [<板名=数据文件> ...]
"""
import struct
import sys

MAGIC = b"QCA-ATH12K-BOARD\0"
BD_IE_BOARD, BD_IE_BOARD_NAME, BD_IE_BOARD_DATA = 0, 0, 1


def pad4(b):
    return b + b"\0" * (-len(b) % 4)


def ie(ie_id, data):
    return struct.pack("<II", ie_id, len(data)) + pad4(data)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out = pad4(MAGIC)
    for arg in sys.argv[2:]:
        name, path = arg.split("=", 1) if "=" in arg and not arg.startswith("bus=") else arg.rsplit("=", 1)
        data = open(path, "rb").read()
        out += ie(BD_IE_BOARD, ie(BD_IE_BOARD_NAME, name.encode()) + ie(BD_IE_BOARD_DATA, data))
        print(f"{name} <- {path} ({len(data)} bytes)")
    open(sys.argv[1], "wb").write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
