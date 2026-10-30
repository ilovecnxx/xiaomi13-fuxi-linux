#!/bin/bash
# Single entry point for the fuxi mobile Chromium browser.
# Delegates to the systemd --user service so there is exactly ONE owner of the browser
# process and the bridge port (no double-launch race). Falls back to direct exec if the
# user bus is unavailable.
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
if systemctl --user -q is-enabled fuxi-mobile-chromium.service 2>/dev/null; then
  systemctl --user start fuxi-mobile-chromium.service && exit 0
fi
# fallback: direct
export WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 FUXI_FORCE_LIGHT=1
export FUXI_HOME="${FUXI_HOME:-https://www.example.com}"
if pgrep -u fuxi -f fuxi-mobile-shell.py >/dev/null; then exit 0; fi
exec /usr/bin/python3 -u /opt/chromium/mobile/fuxi-mobile-shell.py
