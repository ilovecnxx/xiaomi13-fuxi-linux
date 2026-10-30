#!/usr/bin/env python3
"""打印 LUN4（sde）GPT 里 A/B 分区的槽位属性。用法: fuxi-gpt-slots.py <gpt.bin> [<gpt2.bin>]（两个文件时只列出不同的项）"""
import struct, sys

B = 4096


def slots(path):
    d = open(path, 'rb').read()
    hdr = d[B:B + 92]
    assert hdr[:8] == b'EFI PART', path
    ent_lba, n, esz = struct.unpack_from('<QII', hdr, 72)
    out = {}
    for i in range(n):
        e = d[ent_lba * B + i * esz: ent_lba * B + (i + 1) * esz]
        if len(e) < esz or e[:16] == b'\0' * 16:
            continue
        name = e[56:128].decode('utf-16le').rstrip('\0')
        attr = struct.unpack_from('<Q', e, 48)[0]
        if name[-2:] in ('_a', '_b'):
            out[name] = (i + 1, attr)
    return out


def fmt(attr):
    a = attr >> 48
    return (f'0x{attr:016x} prio={a & 3} active={(a >> 2) & 1} retry={(a >> 3) & 7} '
            f'success={(a >> 6) & 1} unbootable={(a >> 7) & 1}')


s1 = slots(sys.argv[1])
if len(sys.argv) == 2:
    for k, (idx, at) in sorted(s1.items()):
        print(f'{k:20s} #{idx:<3d} {fmt(at)}')
else:
    s2 = slots(sys.argv[2])
    for k in sorted(set(s1) | set(s2)):
        a1, a2 = s1.get(k, (0, None))[1], s2.get(k, (0, None))[1]
        if a1 != a2:
            print(f'{k:20s} {fmt(a1)}\n{"":20s} {fmt(a2)}')
