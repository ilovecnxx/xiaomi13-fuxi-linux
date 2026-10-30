#!/bin/bash
# Layer the Android-Chrome-style MOBILE UI on top of the already-installed Chromium
# (/opt/chromium). Installs the self-contained overlay + single-threaded shell supervisor,
# a systemd --user autostart service and a desktop icon, then (re)starts it in the Phosh session.
#
# Prereq: scripts/fuxi-chromium-deploy.sh has run (Chromium present under /opt/chromium).
# Usage: [FUXI_HOST=..] scripts/fuxi-chromium-mobile-ui.sh [--rollback]
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$B/work/chromium-mobile"
mode=deploy
[ "${1:-}" = "--rollback" ] && mode=rollback
SSHK=(-i "$B/work/ssh/fuxi_root" -o UserKnownHostsFile="$B/work/ssh/known_hosts"
      -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o ServerAliveInterval=5)
HOST="${FUXI_HOST:-10.42.0.2}"
ssh_retry() { local i; for i in $(seq 1 20); do ssh "${SSHK[@]}" root@"$HOST" "$@" && return 0; sleep 5; done; return 1; }
scp_retry() { local i; for i in $(seq 1 20); do scp "${SSHK[@]}" "$1" root@"$HOST:$2" && return 0; sleep 5; done; return 1; }

if [ "$mode" = rollback ]; then
  ssh_retry 'bash -s' <<'R'
set -eu
su fuxi -s /bin/bash -c 'export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus;
  systemctl --user disable --now fuxi-mobile-chromium.service 2>/dev/null || true'
rm -f /home/fuxi/.config/systemd/user/fuxi-mobile-chromium.service
rm -f /home/fuxi/.config/autostart/fuxi-mobile-chromium.desktop
rm -rf /opt/chromium/mobile
pkill -u fuxi -f fuxi-mobile-shell 2>/dev/null || true
echo "mobile UI layer removed"
R
  exit 0
fi

ssh_retry 'mkdir -p /opt/chromium/mobile'
for f in cdp.py fuxi-mobile-shell.py mobile-chrome.js probe.py launch-mobile.sh; do
  scp_retry "$SRC/$f" "/opt/chromium/mobile/$f"
done

ssh_retry 'bash -s' <<'R'
set -eu
grep -q fuxi.fb= /proc/cmdline
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ]
[ -x /opt/chromium/root/usr/lib/chromium/chromium ]
chmod 755 /opt/chromium/mobile /opt/chromium/mobile/*.py /opt/chromium/mobile/launch-mobile.sh
chmod 644 /opt/chromium/mobile/mobile-chrome.js

install -d -o fuxi -g fuxi /home/fuxi/.config/systemd/user
cat > /home/fuxi/.config/systemd/user/fuxi-mobile-chromium.service <<UNIT
[Unit]
Description=Fuxi mobile Chromium shell (Blink + Android-Chrome-style UI)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-0
Environment=DISPLAY=:0
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
Environment=FUXI_FORCE_LIGHT=1
Environment=FUXI_HOME=https://www.example.com
ExecStart=/usr/bin/python3 -u /opt/chromium/mobile/fuxi-mobile-shell.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
UNIT
chown fuxi:fuxi /home/fuxi/.config/systemd/user/fuxi-mobile-chromium.service

install -d -o fuxi -g fuxi /home/fuxi/.config/autostart
cat > /home/fuxi/.config/autostart/fuxi-mobile-chromium.desktop <<AUTO
[Desktop Entry]
Type=Application
Name=Fuxi Mobile Chromium
Exec=/opt/chromium/mobile/launch-mobile.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
AUTO
chown fuxi:fuxi /home/fuxi/.config/autostart/fuxi-mobile-chromium.desktop

cat > /opt/chromium/share/applications/org.chromium.ChromiumMobile.desktop <<D
[Desktop Entry]
Type=Application
Name=Chromium
Name[zh_CN]=Chromium 浏览器
GenericName=Web Browser
GenericName[zh_CN]=网络浏览器
Comment=Mobile Chromium browser
Exec=/opt/chromium/mobile/launch-mobile.sh
Icon=org.chromium.Chromium
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
D
chmod 644 /opt/chromium/share/applications/org.chromium.ChromiumMobile.desktop

su fuxi -s /bin/bash -c '
  export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
  install -d ~/.local/share/applications
  cp /opt/chromium/share/applications/org.chromium.ChromiumMobile.desktop ~/.local/share/applications/
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  gio mime x-scheme-handler/https org.chromium.ChromiumMobile.desktop 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable fuxi-mobile-chromium.service
  systemctl --user restart fuxi-mobile-chromium.service
  sleep 3
  systemctl --user is-active fuxi-mobile-chromium.service
'
# remove the legacy desktop-mode launcher so the app grid shows exactly ONE Chromium icon
rm -f /opt/chromium/share/applications/org.chromium.Chromium.desktop /home/fuxi/.local/share/applications/org.chromium.Chromium.desktop 2>/dev/null || true
echo "mobile UI layer deployed"
R
