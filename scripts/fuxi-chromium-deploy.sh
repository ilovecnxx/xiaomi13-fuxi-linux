#!/bin/bash
# Deploy Chromium (Debian arm64 .deb, v150) onto Xiaomi 13 fuxi mainline Linux as an
# isolated prefix under /opt/chromium. Nothing is installed via system dpkg; the handful of
# sonames Ubuntu 26.10 lacks (dav1d6/jpeg62/flac12/minizip1/openh264-7/double-conversion3/
# xnvctrl0) are extracted into /opt/chromium/privatelib and injected with LD_LIBRARY_PATH.
#
# Google Chrome itself has no official arm64 Linux build; this is Chromium (same engine).
#
# Usage:
#   [FUXI_HOST=<wifi-ip>] scripts/fuxi-chromium-deploy.sh            # deploy / update
#   [FUXI_HOST=<wifi-ip>] scripts/fuxi-chromium-deploy.sh --rollback # remove /opt/chromium + desktop entries
#   scripts/fuxi-chromium-deploy.sh --cache-only                     # only (re)download+verify debs to host cache
#
# Notes: only touches the linux rootfs (/opt, fuxi's ~/.local, /tmp). Never flashes, never
# reboots the phone, never modifies dpkg system packages.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$B/work/chromium-debs"
LOCK="$CACHE/.verified"
mode=deploy
case "${1:-}" in
  --rollback) mode=rollback; shift ;;
  --cache-only) mode=cache-only; shift ;;
  "") ;;
  *) echo "Usage: $0 [--rollback|--cache-only]" >&2; exit 2 ;;
esac
[ "$#" -eq 0 ] || { echo "Usage: $0 [--rollback|--cache-only]" >&2; exit 2; }

# ---- package set (Debian bookworm main/arm64) ----
DEBSUITE=bookworm
DEBARCH=arm64
OWN_DEBS=(chromium chromium-common)
PRIV_DEBS=(libdav1d6 libdouble-conversion3 libflac12 libjpeg62-turbo libminizip1 libopenh264-7 libxnvctrl0)

fetch_verify() {
  mkdir -p "$CACHE"
  python3 - "$CACHE" "$DEBSUITE" "$DEBARCH" "${OWN_DEBS[@]}" "${PRIV_DEBS[@]}" <<'PY'
import urllib.request, gzip, re, hashlib, os, sys
cache, suite, arch = sys.argv[1], sys.argv[2], sys.argv[3]
want = set(sys.argv[4:])
base = "http://deb.debian.org/debian/"
idx = urllib.request.urlopen(base + f"dists/{suite}/main/binary-{arch}/Packages.gz", timeout=120).read()
text = gzip.decompress(idx).decode('utf-8', 'replace')
meta = {}
for s in text.split("\n\n"):
    m = re.search(r'^Package: (\S+)$', s, re.M)
    if m and m.group(1) in want:
        meta[m.group(1)] = dict(
            fn=re.search(r'^Filename: (\S+)$', s, re.M).group(1),
            sha=re.search(r'^SHA256: (\S+)$', s, re.M).group(1),
            ver=re.search(r'^Version: (\S+)$', s, re.M).group(1))
missing = want - meta.keys()
if missing:
    raise SystemExit(f"missing metadata for: {missing}")
for name in sorted(want):
    p = meta[name]; out = os.path.join(cache, os.path.basename(p['fn']))
    if os.path.exists(out) and hashlib.sha256(open(out, 'rb').read()).hexdigest() == p['sha']:
        print(f"cached {os.path.basename(out)} ({p['ver']})"); continue
    print(f"fetch  {os.path.basename(out)} ({p['ver']})", flush=True)
    data = urllib.request.urlopen(base + p['fn'], timeout=300).read()
    if hashlib.sha256(data).hexdigest() != p['sha']:
        raise SystemExit(f"SHA256 mismatch for {out}")
    open(out, 'wb').write(data)
print("all debs verified")
PY
  date -Iseconds > "$LOCK"
}

remote() { "$B/scripts/fuxi-ssh.sh" "$@"; }

# resilient scp: retries until the phone USB/WiFi link is stable
scp_retry() {
  local src="$1" dst="$2" i
  local SSHK=(-i "$B/work/ssh/fuxi_root" -o UserKnownHostsFile="$B/work/ssh/known_hosts"
              -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o ServerAliveInterval=5)
  for i in $(seq 1 20); do
    scp "${SSHK[@]}" "$src" "root@${FUXI_HOST:-10.42.0.2}:$dst" && return 0
    echo "scp retry $i ($src)" >&2; sleep 6
  done
  return 1
}

if [ "$mode" = cache-only ]; then
  fetch_verify
  exit 0
fi

if [ "$mode" = rollback ]; then
  remote 'bash -s' <<'REMOTE'
set -eu
echo "Removing Chromium isolated prefix and desktop entries (no dpkg touched)"
pkill -u fuxi -f '/opt/chromium/root/usr/lib/chromium/chromium ' 2>/dev/null || true
runuser -u fuxi -- env XDG_RUNTIME_DIR=/run/user/1000 sh -c 'rm -f ~/.local/share/applications/org.chromium.Chromium.desktop' 2>/dev/null || true
rm -rf /opt/chromium
rm -f /tmp/chromium*.deb /tmp/chromium*.log 2>/dev/null || true
echo "rollback done: /opt/chromium removed"
REMOTE
  exit 0
fi

# ---- deploy ----
fetch_verify

LOG="$B/work/claude-logs/chromium-deploy-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$B/work/claude-logs"

echo "copying debs to phone (retry-tolerant)..."
for f in "$CACHE"/*.deb; do
  scp_retry "$f" "/tmp/$(basename "$f")"
done

remote 'bash -s' <<'REMOTE' | tee "$LOG"
set -euo pipefail
grep -q 'fuxi.fb=' /proc/cmdline
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ]
[ "$(id -u fuxi)" = 1000 ]

echo "extracting chromium + chromium-common into /opt/chromium/root"
mkdir -p /opt/chromium/root /opt/chromium/privatelib /opt/chromium/bin /opt/chromium/share/applications /opt/chromium/share/icons
for d in /tmp/chromium_*.deb /tmp/chromium-common_*.deb; do dpkg-deb -x "$d" /opt/chromium/root; done

echo "extracting private libs (sonames Ubuntu 26.10 lacks)"
rm -rf /tmp/chrlibx; mkdir -p /tmp/chrlibx
for d in /tmp/libdav1d6_*.deb /tmp/libdouble-conversion3_*.deb /tmp/libflac12_*.deb \
         /tmp/libjpeg62-turbo_*.deb /tmp/libminizip1_*.deb /tmp/libopenh264-7_*.deb /tmp/libxnvctrl0_*.deb; do
  dpkg-deb -x "$d" /tmp/chrlibx
done
cp -a /tmp/chrlibx/usr/lib/aarch64-linux-gnu/*.so* /opt/chromium/privatelib/ 2>/dev/null || true
rm -rf /tmp/chrlibx
ldconfig -n /opt/chromium/privatelib 2>/dev/null || true

CHR=/opt/chromium/root/usr/lib/chromium/chromium
if LD_LIBRARY_PATH=/opt/chromium/privatelib ldd "$CHR" 2>&1 | grep -q "not found"; then
  echo "FATAL: unresolved libraries:"; LD_LIBRARY_PATH=/opt/chromium/privatelib ldd "$CHR" | grep "not found"; exit 1
fi
echo "all shared libraries resolve"

cat > /opt/chromium/bin/chromium-launch <<'LAUNCH'
#!/bin/bash
# Chromium 150 (Debian arm64) launcher for Xiaomi 13 fuxi mainline Linux / Phosh.
# Isolated prefix; private libs under /opt/chromium/privatelib. GPU: ANGLE-gl over freedreno.
set -u
ROOT=/opt/chromium
CHR="$ROOT/root/usr/lib/chromium/chromium"
export LD_LIBRARY_PATH="$ROOT/privatelib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
: "${HOME:=/home/fuxi}"; export HOME
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"; export XDG_RUNTIME_DIR
: "${DBUS_SESSION_BUS_ADDRESS:=unix:path=/run/user/$(id -u)/bus}"; export DBUS_SESSION_BUS_ADDRESS
ARGS=(
  --user-data-dir="$HOME/.config/chromium-fuxi"
  --no-sandbox
  --disable-dev-shm-usage
  --ozone-platform=wayland
  --enable-features=UseOzonePlatform
  --disable-features=Vulkan
  --use-angle=gl
  --use-gl=angle
  --enable-gpu-rasterization
  --ignore-gpu-blocklist
  --password-store=basic
  --no-first-run
  --no-default-browser-check
)
if [ "${CHROMIUM_SOFTWARE:-0}" = "1" ]; then ARGS+=( --disable-gpu --disable-gpu-compositing ); fi
exec "$CHR" "${ARGS[@]}" "$@"
LAUNCH
chmod +x /opt/chromium/bin/chromium-launch

for sz in 48 64 128 256; do
  install -d -m 0755 /opt/chromium/share/icons/hicolor/${sz}x${sz}/apps
  cp "/opt/chromium/root/usr/share/icons/hicolor/${sz}x${sz}/apps/chromium.png" \
     "/opt/chromium/share/icons/hicolor/${sz}x${sz}/apps/org.chromium.Chromium.png" 2>/dev/null || true
done

cat > /opt/chromium/share/applications/org.chromium.Chromium.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Chromium
Name[zh_CN]=Chromium 浏览器
GenericName=Web Browser
GenericName[zh_CN]=网络浏览器
Comment=Access the Internet
Comment[zh_CN]=访问互联网
Exec=/opt/chromium/bin/chromium-launch %U
Icon=org.chromium.Chromium
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=chromium
DESK
chmod 0644 /opt/chromium/share/applications/org.chromium.Chromium.desktop

runuser -u fuxi -- bash -c '
  install -d ~/.local/share/applications ~/.local/share/icons/hicolor
  cp /opt/chromium/share/applications/org.chromium.Chromium.desktop ~/.local/share/applications/
  for sz in 48 64 128 256; do
    install -d ~/.local/share/icons/hicolor/${sz}x${sz}/apps
    cp /opt/chromium/share/icons/hicolor/${sz}x${sz}/apps/org.chromium.Chromium.png \
       ~/.local/share/icons/hicolor/${sz}x${sz}/apps/ 2>/dev/null || true
  done
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
'
echo "closing leftover /tmp debs"
rm -f /tmp/chromium_*.deb /tmp/chromium-common_*.deb /tmp/libdav1d6_*.deb /tmp/libdouble-conversion3_*.deb \
      /tmp/libflac12_*.deb /tmp/libjpeg62-turbo_*.deb /tmp/libminizip1_*.deb /tmp/libopenh264-7_*.deb /tmp/libxnvctrl0_*.deb 2>/dev/null || true
echo "verify:"
LD_LIBRARY_PATH=/opt/chromium/privatelib /opt/chromium/root/usr/lib/chromium/chromium --version
grep '^Exec=' /opt/chromium/share/applications/org.chromium.Chromium.desktop
echo "DONE: Chromium deployed to /opt/chromium (isolated prefix; nothing added to system dpkg)."
REMOTE

echo "log=$LOG"
