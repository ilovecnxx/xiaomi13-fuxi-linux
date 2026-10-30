#!/bin/bash
# Install GTK's file chooser portal for Phosh without redeploying the rest of the desktop.
# Default is deploy; --dry-run only simulates the package transaction and prints the config.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
mode=deploy
if [ "${1:-}" = --dry-run ]; then mode=dry-run; shift; fi
[ "$#" -eq 0 ] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }
LOG="$B/work/claude-logs/portal-gtk-${mode}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$B/work/claude-logs"
if [ "$mode" = dry-run ]; then
  timeout 120 "$B/scripts/fuxi-ssh.sh" 'bash -s' <<'REMOTE' | tee "$LOG"
set -euo pipefail
grep -q 'fuxi.fb=' /proc/cmdline
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ]
  apt-get -s install --no-install-recommends --no-upgrade --no-remove xdg-desktop-portal-gtk
printf '%s\n' '--- proposed Phosh portal config ---'
cat <<'PORTALCONF'
[preferred]
default=phrosh;phosh;gtk;
org.freedesktop.impl.portal.Access=phosh-shell;
org.freedesktop.impl.portal.Background=none;
org.freedesktop.impl.portal.Clipboard=none;
org.freedesktop.impl.portal.FileChooser=gtk;phrosh;
org.freedesktop.impl.portal.GlobalShortcuts=none;
org.freedesktop.impl.portal.InputCapture=none;
org.freedesktop.impl.portal.RemoteDesktop=none;
org.freedesktop.impl.portal.ScreenCast=wlr;
org.freedesktop.impl.portal.Screenshot=gtk;wlr;
org.freedesktop.impl.portal.Secret=gnome-keyring;
PORTALCONF
REMOTE
else
  timeout 300 "$B/scripts/fuxi-ssh.sh" 'bash -s' <<'REMOTE' | tee "$LOG"
set -euo pipefail
grep -q 'fuxi.fb=' /proc/cmdline
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ]
[ "$(id -u fuxi)" = 1000 ]
backup="/root/fuxi-mainline-backup/portal-gtk-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
dpkg-query -W -f='${Package}\t${Version}\n' xdg-desktop-portal xdg-desktop-portal-phosh > "$backup/packages-before.tsv"
conf=/etc/xdg/xdg-desktop-portal/phosh-portals.conf
if [ -e "$conf" ]; then cp -a --parents "$conf" "$backup/"; fi
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends --no-upgrade --no-remove xdg-desktop-portal-gtk
install -d -m 0755 /etc/xdg/xdg-desktop-portal
cat > "$conf.new" <<'PORTALCONF'
[preferred]
default=phrosh;phosh;gtk;
org.freedesktop.impl.portal.Access=phosh-shell;
org.freedesktop.impl.portal.Background=none;
org.freedesktop.impl.portal.Clipboard=none;
org.freedesktop.impl.portal.FileChooser=gtk;phrosh;
org.freedesktop.impl.portal.GlobalShortcuts=none;
org.freedesktop.impl.portal.InputCapture=none;
org.freedesktop.impl.portal.RemoteDesktop=none;
org.freedesktop.impl.portal.ScreenCast=wlr;
org.freedesktop.impl.portal.Screenshot=gtk;wlr;
org.freedesktop.impl.portal.Secret=gnome-keyring;
PORTALCONF
chmod 0644 "$conf.new"
mv "$conf.new" "$conf"
python3 - "$conf" <<'PYCONF'
import configparser, sys
p = configparser.ConfigParser(interpolation=None, delimiters=('='))
if not p.read(sys.argv[1]):
    raise SystemExit('portal preference file could not be read')
if p['preferred'].get('org.freedesktop.impl.portal.FileChooser') != 'gtk;phrosh;':
    raise SystemExit('unexpected FileChooser preference')
PYCONF
runuser -u fuxi -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  systemctl --user restart xdg-desktop-portal.service
dpkg-query -W -f='GTK portal: ${Version} ${db:Status-Status}\n' xdg-desktop-portal-gtk
grep '^org.freedesktop.impl.portal.FileChooser=' "$conf"
printf '%s GTK file chooser portal preferred for Phosh; backup=%s\n' "$(date -Iseconds)" "$backup" >> /root/fuxi-mainline-backup/CHANGES.txt
printf '%s\n' 'Restarted the portal frontend to apply the new backend routing.'
REMOTE
fi
printf 'log=%s\n' "$LOG"
