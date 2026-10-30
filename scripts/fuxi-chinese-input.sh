#!/bin/bash
# Enable Stevia's packaged UIM Pinyin engine on the existing Linux desktop.
# Does not change the hardware-keyboard IM module, PIN, or working key sizing.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
[ "$#" -eq 0 ] || { echo "用法: $0" >&2; exit 2; }
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/chinese-input-$(date +%Y%m%d-%H%M%S).log"
timeout 600 "$B/scripts/fuxi-ssh.sh" 'bash -s' <<'REMOTE' | tee "$LOG"
set -euo pipefail
grep -q 'fuxi.fb=' /proc/cmdline
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ]
[ "$(id -u fuxi)" = 1000 ]
u() { runuser -u fuxi -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "$@"; }
backup="/root/fuxi-mainline-backup/chinese-input-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
u gsettings get org.gnome.desktop.input-sources sources > "$backup/sources-before.txt"
u gsettings get mobi.phosh.osk scaling > "$backup/scaling-before.txt"
u gsettings get mobi.phosh.osk.Completers default > "$backup/default-completer-before.txt"
dpkg-query -W -f='${Package}\t${Version}\n' > "$backup/packages-before.tsv"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends phosh-osk-stevia-uim
u python3 - <<'PY'
from gi.repository import Gio, GLib
settings = Gio.Settings.new('org.gnome.desktop.input-sources')
old = [tuple(item) for item in settings.get_value('sources').unpack()]
# Stevia 0.58 maps this IBus-style source to its native UIM 'py' engine;
# no IBus daemon or second on-screen keyboard is needed.
sources = [('ibus', 'uim:cn')] + [item for item in old
                                  if item not in (('ibus', 'uim:cn'), ('xkb', 'cn'))]
if ('xkb', 'us') not in sources:
    sources.append(('xkb', 'us'))
if sources != old:
    if not settings.set_value('sources', GLib.Variant('a(ss)', sources)):
        raise SystemExit('Input-source setting was not writable')
    Gio.Settings.sync()
print('Input sources:', settings.get_value('sources').unpack())
completers = Gio.Settings.new('mobi.phosh.osk.Completers')
# UIM is selected for the specific uim:cn layout. A global UIM default also
# gets applied to English layouts and produces an unsupported-language warning.
if completers.get_string('default'):
    if not completers.set_string('default', ''):
        raise SystemExit('Default completer setting was not writable')
    Gio.Settings.sync()
print('Default completer:', repr(completers.get_string('default')))
PY
u systemctl --user restart mobi.phosh.OSK.service
u systemctl --user is-active mobi.phosh.OSK.service
u gsettings get mobi.phosh.osk scaling
printf '%s enabled Stevia UIM Pinyin; preserved existing sources and added English; backup=%s\n' \
  "$(date -Iseconds)" "$backup" >> /root/fuxi-mainline-backup/CHANGES.txt
echo "Backup: $backup"
REMOTE
echo "拼音组件与输入源已部署，实际选词/保存请另行验收。日志: $LOG"
