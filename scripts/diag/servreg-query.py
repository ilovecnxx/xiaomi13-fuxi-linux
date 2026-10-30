#!/usr/bin/env python3
# 只读诊断：向每个 servreg locator（QMI 服务 64）端口发送 GET_DOMAIN_LIST(0x21)，打印返回的域列表。
# 用法: servreg-query.py <服务名，如 tms/servreg> [node:port ...]；不给端口则查询 qrtr-ns 列出的全部 locator。
import socket, struct, sys, subprocess, re
AF_QIPCRTR = 42
name = sys.argv[1].encode()
targets = [tuple(map(int, t.split(':'))) for t in sys.argv[2:]]
if not targets:
    out = subprocess.run(['qrtr-lookup', '64'], capture_output=True, text=True).stdout
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 5 and f[0] == '64':
            targets.append((int(f[3]), int(f[4])))
def tlv(t, v): return struct.pack('<BH', t, len(v)) + v
for node, port in targets:
    s = socket.socket(AF_QIPCRTR, socket.SOCK_DGRAM)
    s.settimeout(3)
    offset, got, total = 0, 0, None
    print(f'== locator node={node} port={port} service={name.decode()}')
    while True:
        body = tlv(0x01, name) + tlv(0x10, struct.pack('<I', offset))
        s.sendto(struct.pack('<BHHH', 0, 1 + offset, 0x21, len(body)) + body, (node, port))
        try:
            d, _ = s.recvfrom(4096)
        except socket.timeout:
            print('  timeout'); break
        typ, txn, mid, ln = struct.unpack_from('<BHHH', d)
        p, entries = 7, []
        while p < 7 + ln:
            t, l = struct.unpack_from('<BH', d, p); v = d[p+3:p+3+l]; p += 3 + l
            if t == 0x02: print('  result=%d error=%d' % struct.unpack('<HH', v))
            elif t == 0x10: total, = struct.unpack('<H', v); print('  total_domains', total)
            elif t == 0x11: print('  db_rev', struct.unpack('<H', v)[0])
            elif t == 0x12:
                n, q = v[0], 1
                for _ in range(n):
                    sl = v[q]; nm = v[q+1:q+1+sl].decode(errors='replace'); q += 1 + sl
                    inst, = struct.unpack_from('<I', v, q); dv = v[q+4]; sd, = struct.unpack_from('<I', v, q+5); q += 9
                    entries.append(nm); print(f'  domain name={nm} instance={inst} data_valid={dv} data=0x{sd:x}')
            else: print('  tlv', hex(t), v.hex())
        got += len(entries)
        if not entries or total is None or got >= total: break
        offset = got
    s.close()
