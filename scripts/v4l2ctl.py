#!/usr/bin/env python3
# 极简 v4l2 控件工具（手机没装 v4l-utils 时用）
# 用法: v4l2ctl.py <dev>            列出控件
#       v4l2ctl.py <dev> <id> <val> 设置控件（id 可写十进制或 0x 十六进制）
import fcntl, struct, sys

QUERYCTRL, G_CTRL, S_CTRL = 0xC0445624, 0xC008561B, 0xC008561C
QUERYMENU = 0xC02C5625  # struct v4l2_querymenu: id, index, name[32], reserved
NEXT = 0x80000000
fd = open(sys.argv[1], "rb+", buffering=0)

def get(cid):
    return struct.unpack("Ii", fcntl.ioctl(fd, G_CTRL, struct.pack("Ii", cid, 0)))[1]

if len(sys.argv) == 4:
    cid, val = int(sys.argv[2], 0), int(sys.argv[3], 0)
    fcntl.ioctl(fd, S_CTRL, struct.pack("Ii", cid, val))
    print(f"0x{cid:08x} = {get(cid)}")
    sys.exit()

cid = NEXT
while True:
    try:
        r = fcntl.ioctl(fd, QUERYCTRL, struct.pack("II32siiiiI8x", cid, 0, b"", 0, 0, 0, 0, 0))
    except OSError:
        break
    i, typ, name, mn, mx, st, df, fl = struct.unpack("II32siiiiI8x", r)
    cid = i | NEXT
    name = name.split(b"\0")[0].decode()
    if typ == 6:  # CTRL_CLASS
        print(f"-- {name}"); continue
    try: v = get(i)
    except OSError: v = "?"
    print(f"0x{i:08x} {name:<28} type={typ} [{mn},{mx}] def={df} val={v} flags=0x{fl:x}")
    if typ == 3:  # MENU
        for k in range(mn, mx + 1):
            try:
                m = fcntl.ioctl(fd, QUERYMENU, struct.pack("II32s4x", i, k, b""))
                print(f"      {k}: {struct.unpack('II32s4x', m)[2].split(b'\0')[0].decode()}")
            except OSError: pass
