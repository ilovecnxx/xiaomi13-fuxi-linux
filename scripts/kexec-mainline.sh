#!/bin/sh
# 在 fuxi 的 Ubuntu 上执行：kexec 跳转主线内核并抓日志
set -e
IMG=${IMG:-/tmp/mainline-Image}
DTB=${DTB:-/tmp/fuxi-stock.dtb}
CMD=${CMD:-"console=ttyGS0,115200n8 loglevel=7 rdinit=/init pstore_blk.blkdev=/dev/sda30"}
echo "loading $IMG with dtb $DTB"
kexec -l "$IMG" --dtb="$DTB" --command-line="$CMD"
echo "booting mainline via kexec..."
kexec -e
