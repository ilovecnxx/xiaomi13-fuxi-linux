#!/bin/bash
# 补齐已有 Phosh 的基础应用、HTTPS 根证书和本地时区；不重刷内核、不修改用户密码。
# 用法: scripts/fuxi-basic-desktop.sh
# 需要手机已启动 Linux，USB SSH 和已配置的软件源可用。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
[ "$#" -eq 0 ] || { echo "用法: $0" >&2; exit 2; }
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/basic-desktop-install-$(date +%Y%m%d-%H%M%S).log"
timeout 900 "$B/scripts/fuxi-ssh.sh" 'bash -s' <<'REMOTE' | tee "$LOG"
set -euo pipefail
grep -q 'fuxi.fb=' /proc/cmdline
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ]
[ "$(id -u fuxi)" = 1000 ]
backup="/root/fuxi-mainline-backup/basic-desktop-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
dpkg-query -W -f='${Package}\t${Version}\n' > "$backup/packages-before.tsv"
timedatectl show -p Timezone --value > "$backup/timezone-before.txt"
runuser -u fuxi -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  gsettings get mobi.phosh.osk scaling > "$backup/keyboard-scaling-before.txt"
for path in /home/fuxi/.config/mimeapps.list /home/fuxi/.local/share/applications/mimeapps.list /etc/xdg/xdg-desktop-portal/phosh-portals.conf; do
  if [ -f "$path" ]; then cp --parents -a "$path" "$backup/"; fi
done
export DEBIAN_FRONTEND=noninteractive
apt-get update -o APT::Update::Error-Mode=any
apt-get install -y --no-install-recommends ca-certificates xdg-utils xdg-desktop-portal-gtk \
  epiphany-browser gnome-text-editor language-pack-zh-hans language-pack-gnome-zh-hans
test -s /etc/ssl/certs/ca-certificates.crt
install -D -m 0644 /dev/stdin /etc/xdg/xdg-desktop-portal/phosh-portals.conf <<'PORTALCONF'
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
runuser -u fuxi -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  systemctl --user restart xdg-desktop-portal.service
timedatectl set-timezone Asia/Shanghai
u() { runuser -u fuxi -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "$@"; }
# On this simpledrm image, automatic portrait sizing compresses all four rows
# into a narrow strip. Keep the tested natural key height and other flags.
python3 - <<'PY'
import ast
from pathlib import Path
import subprocess
if not any(path.is_char_device() for path in Path('/dev/dri').glob('renderD*')):
    user = ['runuser', '-u', 'fuxi', '--', 'env', 'XDG_RUNTIME_DIR=/run/user/1000',
            'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus']
    flags = ast.literal_eval(subprocess.check_output(
        user + ['gsettings', 'get', 'mobi.phosh.osk', 'scaling'], text=True).strip())
    if 'auto-portrait' in flags:
        flags.remove('auto-portrait')
        subprocess.run(user + ['gsettings', 'set', 'mobi.phosh.osk', 'scaling', repr(flags)], check=True)
    print('Keyboard scaling flags:', flags)
PY
# 仅在旧默认项不存在或指向已卸载程序时补默认浏览器，不覆盖可用的个人选择。
for scheme in x-scheme-handler/http x-scheme-handler/https text/html; do
  current=$(u xdg-mime query default "$scheme" || true)
  if [ -z "$current" ] || { [ ! -f "/usr/share/applications/$current" ] && \
     [ ! -f "/home/fuxi/.local/share/applications/$current" ]; }; then
    test -f /usr/share/applications/org.gnome.Epiphany.desktop
    u xdg-mime default org.gnome.Epiphany.desktop "$scheme"
  fi
done
printf '%s basic desktop: CA roots/browser/editor/Chinese translations; GTK file chooser portal preferred; timezone Asia/Shanghai; natural portrait keyboard height on simpledrm; backup=%s\n' \
  "$(date -Iseconds)" "$backup" >> /root/fuxi-mainline-backup/CHANGES.txt
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' ca-certificates \
  epiphany-browser gnome-text-editor language-pack-zh-hans language-pack-gnome-zh-hans
python3 - <<'PY'
import ssl
context = ssl.create_default_context()
stats = context.cert_store_stats()
assert stats['x509_ca'] > 0, stats
print('System CA store:', stats)
PY
timedatectl show -p Timezone -p NTPSynchronized
printf 'Backup: %s\n' "$backup"
REMOTE
# Keep the original package launchers intact. Local overrides survive upgrades;
# rerunning this script refreshes translations/actions from the packaged file.
timeout 30 "$B/scripts/fuxi-ssh.sh" 'bash -s' <<'REMOTE' | tee -a "$LOG"
set -euo pipefail
backup="/root/fuxi-mainline-backup/desktop-rendering-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for path in /usr/local/bin/fuxi-desktop-app /usr/local/share/applications/org.gnome.Epiphany.desktop /usr/local/share/applications/org.gnome.TextEditor.desktop /usr/local/share/applications/mobi.phosh.MobileSettings.desktop /usr/local/share/applications/org.gnome.Settings.desktop; do
  if [ -f "$path" ]; then cp --parents -a "$path" "$backup/"; else printf '%s\n' "$path" >> "$backup/previously-absent.txt"; fi
done
printf '%s desktop software rendering launcher backup=%s\n' "$(date -Iseconds)" "$backup" >> /root/fuxi-mainline-backup/CHANGES.txt
REMOTE
timeout 30 "$B/scripts/fuxi-ssh.sh" 'install -D -m 755 /dev/stdin /usr/local/bin/fuxi-desktop-app' \
  < "$B/work/rootfs-overlay/usr/local/bin/fuxi-desktop-app"
timeout 30 "$B/scripts/fuxi-ssh.sh" 'python3 -' <<'PY' | tee -a "$LOG"
from pathlib import Path
import re
import subprocess
target = Path('/usr/local/share/applications')
target.mkdir(parents=True, exist_ok=True)
for desktop, app in (('org.gnome.Epiphany.desktop', 'epiphany'),
                     ('org.gnome.TextEditor.desktop', 'gnome-text-editor'),
                     ('mobi.phosh.MobileSettings.desktop', 'phosh-mobile-settings'),
                     ('org.gnome.Settings.desktop', 'gnome-control-center')):
    source = (Path('/usr/share/applications') / desktop).read_text()
    text, count = re.subn(r'^Exec=(?:/usr/bin/)?' + re.escape(app) + r'(?=\s|$)',
                         'Exec=/usr/local/bin/fuxi-desktop-app ' + app, source, flags=re.M)
    if not count:
        raise SystemExit('Unexpected launcher format: ' + desktop)
    text = re.sub(r'^DBusActivatable=.*\n', '', text, flags=re.M)
    if app == 'phosh-mobile-settings':
        # The shipped OnlyShowIn=Phosh is understood by Phosh but rejected by
        # desktop-file-validate as an unregistered environment identifier.
        text = re.sub(r'^OnlyShowIn=.*\n', '', text, flags=re.M)
    text = text.replace('[Desktop Entry]\n', '[Desktop Entry]\nDBusActivatable=false\n', 1)
    output = target / desktop
    temporary = output.with_name('.staging-' + output.name)
    temporary.write_text(text)
    subprocess.run(['desktop-file-validate', str(temporary)], check=True)
    temporary.replace(output)
    print('Installed launcher:', output)
subprocess.run(['update-desktop-database', str(target)], check=True)
PY
"$B/scripts/fuxi-chinese-input.sh"
echo "基础桌面组件、软件渲染与中文输入配置已部署。日志: $LOG"
