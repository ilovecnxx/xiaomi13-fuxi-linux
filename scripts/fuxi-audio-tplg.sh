#!/bin/bash
# 生成 fuxi 的 AudioReach 拓扑 qcom/sm8550/Xiaomi-13-tplg.bin（声卡 model "Xiaomi-13"，driver_name "sm8550"）。
# 做法：拿本机 linux-firmware 里的 SM8550-QRD 拓扑（/lib/firmware，不联网），用 alsatplg 反编译，
# 把其中 Primary MI2S 播放通路（device16：logger → i2s_rx）改成 Secondary MI2S：
#   - DAI 号 token1（AR_TKN_DAI_INDEX）16 PRIMARY_MI2S_RX → 18 SECONDARY_MI2S_RX
#   - i2s 模块 token250（HW_IF_IDX）0 → 1（I2S_INTF_TYPE_SECONDARY）
#   - i2s 模块 token256（SD_LINE_IDX）1（SD0）→ ${SD:-2}（SD1 = GPIO124 i2s1_data1，厂商 tdm1_dout）
#   - 流名/混音器改名 Primary MI2S Playback → Secondary MI2S Playback、PRIMARY_MI2S_RX → SECONDARY_MI2S_RX
# 其余通路（WSA/WCD/VA/DP）原样保留，之后接听筒、耳机、麦克风时再改。
# 用法: scripts/fuxi-audio-tplg.sh   产物: work/firmware-audio/qcom/sm8550/Xiaomi-13-tplg.bin
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
SRC=/lib/firmware/qcom/sm8550/SM8550-QRD-tplg.bin.zst
OUT="$B/work/firmware-audio/qcom/sm8550"
SD="${SD:-2}"
case "$SD" in 1|2) ;; *) echo 'SD 必须为 1（SD0）或 2（SD1）' >&2; exit 2;; esac
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.build.XXXXXX"); trap 'rm -rf "$W"' EXIT
zstd -dqf "$SRC" -o "$W/qrd.bin"
alsatplg -d "$W/qrd.bin" -o "$W/qrd.conf"
# alsatplg 1.2.15 反编译的瑕疵：清单（无私有数据）被写成引用 'manifest:data0'，还粘到了第一条 SectionData 上；
# 去掉后重新编译与原文件语义一致（只是同类块合并、少了 14 个块头，内核不关心块的 index）
sed -i -e "1s/.*/SectionManifest.manifest {}/" -e "s/^\t'manifest:data0'\.'stream0/\t'stream0/" "$W/qrd.conf"
python3 -I - "$W/qrd.conf" "$W/fuxi.conf" "${SD:-2}" <<'EOF'
import re, sys
src, dst, sd = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()

def edit_block(s, name, subs):
    """在名为 name 的顶层条目（'name' { ... }）内部做 token 替换，要求每个都命中一次"""
    i = s.index(f"\t'{name}' {{")
    depth, j = 0, s.index("{", i)
    while True:
        c = s[j]
        depth += c == "{"
        depth -= c == "}"
        j += 1
        if depth == 0:
            break
    blk = s[i:j]
    for tok, old, new in subs:
        blk, n = re.subn(rf"(\t{tok}) {old}\n", rf"\g<1> {new}\n", blk)
        assert n == 1, (name, tok, n)
    return s[:i] + blk + s[j:]

s = edit_block(s, "device16.logger1:tuple0", [("token1", 16, 18)])
s = edit_block(s, "device16.i2s_rx1:tuple0", [("token1", 16, 18), ("token250", 0, 1), ("token256", 1, sd)])
s = edit_block(s, "PRIMARY_MI2S_RX Audio Mixer:tuple0", [("token1", 16, 18)])
s = s.replace("PRIMARY_MI2S_RX Audio Mixer", "SECONDARY_MI2S_RX Audio Mixer")
s = s.replace("Primary MI2S Playback", "Secondary MI2S Playback")
open(dst, "w").write(s)
EOF
# 路由里引用的 BE 流名（'TX_CODEC_DMA_TX_3 Capture' 等）由内核的 q6apm-lpass-dais 提供，alsatplg 会报
# "undefined ... widget/stream"，不影响产物（原样保留在路由表里）
if ! alsatplg -c "$W/fuxi.conf" -o "$W/fuxi.bin" > "$W/compiler.log" 2>&1; then
  cat "$W/compiler.log" >&2
  exit 1
fi
grep -v 'undefined s[a-z]* widget/stream' "$W/compiler.log" || true
[ -s "$W/fuxi.bin" ]
# 回读核对
alsatplg -d "$W/fuxi.bin" -o "$W/check.conf"
grep -q "'Secondary MI2S Playback, , device16.i2s_rx1'" "$W/check.conf"
grep -A30 "'device16.i2s_rx1:tuple0' {" "$W/check.conf" | grep -E 'token(1|250|256) ' | tr -s '\t\n' ' '; echo
# 只有编译和回读成功才替换既有产物，避免失败时把旧文件误报为新构建。
mv "$W/fuxi.bin" "$OUT/Xiaomi-13-tplg.bin"
cp "$W/compiler.log" "$OUT/Xiaomi-13-tplg.build.log"
sha256sum "$OUT/Xiaomi-13-tplg.bin" > "$OUT/Xiaomi-13-tplg.sha256"
echo "[ok] $OUT/Xiaomi-13-tplg.bin $(stat -c %s "$OUT/Xiaomi-13-tplg.bin") bytes（SD_LINE_IDX=${SD:-2}）"
