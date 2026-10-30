#!/bin/bash
# 把 scripts/ 下的 keeper 源同步到部署暂存目录，避免两处副本漂移
# 用法:
#   scripts/fuxi-modem-keeper-package.sh          # 同步
#   scripts/fuxi-modem-keeper-package.sh --check  # 只校验是否一致（不一致退出 1）
set -u
B="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$B/work/deploy/modem-keeper-20261031"
FILES=(fuxi-modem-keeper.py fuxi-qmi-usage.py)

mkdir -p "$DST"
rc=0
for f in "${FILES[@]}"; do
  if [ "${1:-}" = "--check" ]; then
    if diff -q "$B/scripts/$f" "$DST/$f" >/dev/null 2>&1; then
      echo "OK   $f"
    else
      echo "DRIFT $f"
      rc=1
    fi
  else
    cp -f "$B/scripts/$f" "$DST/$f"
    echo "sync $f"
  fi
done

if [ "${1:-}" != "--check" ]; then
  echo "--- sha256 ---"
  ( cd "$B" && sha256sum "scripts/fuxi-modem-keeper.py" "scripts/fuxi-qmi-usage.py" \
      "work/deploy/modem-keeper-20261031/fuxi-modem-keeper.py" "work/deploy/modem-keeper-20261031/fuxi-qmi-usage.py" )
fi
exit $rc
