#!/usr/bin/python3
# fuxi 基带守护：通过 D-Bus 监视 ModemManager。
# 1. 每出现一个新的 modem 对象（开机、SSR、reprobe），把 NAS usage preference 设为 data-centric
#    （调用 fuxi-qmi-usage.py，change duration = power-cycle，不写 NV）。
# 2. 收到网络拒绝后 REJECT_GRACE 秒内没重新注册，或连续 STALL_LIMIT 秒没注册，做一次射频循环：
#    Enable(false) -> SetPowerState(low) -> SetPowerState(on) -> Enable(true)，然后重设 data-centric。
#    循环之间按 MIN_GAP 起步、失败翻倍、最多 MAX_GAP 退避。
# 只在 modem 处于 enabled/searching 时动作；被人为 disable 的 modem 不碰。
import os
import subprocess
import sys
import time

from gi.repository import Gio, GLib

MM = "org.freedesktop.ModemManager1"
IF_MODEM = MM + ".Modem"
IF_3GPP = MM + ".Modem.Modem3gpp"
USAGE = os.environ.get("FUXI_USAGE_TOOL", "/usr/local/sbin/fuxi-qmi-usage.py")
POLL = 5
REJECT_GRACE = int(os.environ.get("FUXI_REJECT_GRACE", "30"))
STALL_LIMIT = int(os.environ.get("FUXI_STALL_LIMIT", "300"))
MIN_GAP = 120
MAX_GAP = 1800
STABLE_RESET = 600

# MMModemState
ST_ENABLED, ST_SEARCHING = 6, 7
# MMModem3gppRegistrationState：home、roaming、sms-only、csfb-not-preferred
REGISTERED = {1, 5, 6, 7, 9, 10}
# MMModemPowerState
PWR_LOW, PWR_ON = 2, 3


def log(msg):
    up = open("/proc/uptime").read().split()[0]
    print(f"[{up}] {msg}", flush=True)


class Keeper:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.path = None
        self.unreg_since = None
        self.reject_at = None
        self.last_cycle = 0.0
        self.gap = MIN_GAP
        self.reg_since = None
        self.busy = False
        self.bus.signal_subscribe(MM, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                  None, None, Gio.DBusSignalFlags.NONE, self.on_props)

    def call(self, path, iface, method, args=None, timeout=60000):
        return self.bus.call_sync(MM, path, iface, method, args, None,
                                  Gio.DBusCallFlags.NONE, timeout, None)

    def modems(self):
        try:
            r = self.call("/org/freedesktop/ModemManager1", "org.freedesktop.DBus.ObjectManager",
                          "GetManagedObjects", timeout=10000)
        except GLib.Error:
            return {}
        return {p: ifs for p, ifs in r.unpack()[0].items() if IF_MODEM in ifs}

    def on_props(self, _c, _s, path, _i, _sig, params):
        iface, changed, _inv = params.unpack()
        if iface != IF_3GPP or path != self.path or "NetworkRejection" not in changed:
            return
        rej = changed["NetworkRejection"]
        if rej:
            self.reject_at = time.monotonic()
            log(f"network rejection: {dict(rej)}")

    def set_data_centric(self):
        try:
            out = subprocess.run([USAGE, "data"], capture_output=True, text=True, timeout=40)
            text = " ".join(out.stdout.split())
            log(f"usage data: rc={out.returncode} {text}")
        except (OSError, subprocess.TimeoutExpired) as e:
            log(f"usage data failed: {e}")

    def cycle(self):
        log(f"radio cycle start (gap {self.gap}s)")
        self.busy = True
        try:
            self.call(self.path, IF_MODEM, "Enable", GLib.Variant("(b)", (False,)))
            self.call(self.path, IF_MODEM, "SetPowerState", GLib.Variant("(u)", (PWR_LOW,)))
            time.sleep(5)
            self.call(self.path, IF_MODEM, "SetPowerState", GLib.Variant("(u)", (PWR_ON,)))
            self.call(self.path, IF_MODEM, "Enable", GLib.Variant("(b)", (True,)))
            log("radio cycle done")
        except GLib.Error as e:
            log(f"radio cycle error: {e.message}")
        self.busy = False
        self.set_data_centric()
        self.last_cycle = time.monotonic()
        self.unreg_since = self.last_cycle
        self.reject_at = None

    def tick(self):
        if self.busy:
            return True
        mods = self.modems()
        if self.path not in mods:
            self.path = next(iter(sorted(mods)), None)
            self.unreg_since = self.reject_at = self.reg_since = None
            if self.path:
                log(f"new modem {self.path}")
                self.set_data_centric()
            return True
        ifs = mods[self.path]
        state = ifs[IF_MODEM].get("State", 0)
        reg = ifs.get(IF_3GPP, {}).get("RegistrationState", 4)
        now = time.monotonic()
        if reg in REGISTERED or state > ST_SEARCHING:
            if self.unreg_since is not None:
                log(f"registered (state {state}, reg {reg})")
            self.unreg_since = self.reject_at = None
            self.reg_since = self.reg_since or now
            if now - self.reg_since > STABLE_RESET:
                self.gap = MIN_GAP
            return True
        self.reg_since = None
        if state not in (ST_ENABLED, ST_SEARCHING):
            self.unreg_since = None
            return True
        if self.unreg_since is None:
            self.unreg_since = now
            log(f"not registered (state {state}, reg {reg})")
        lost = now - self.unreg_since
        rejected = self.reject_at is not None and now - self.reject_at >= REJECT_GRACE
        if (rejected and lost >= REJECT_GRACE) or lost >= STALL_LIMIT:
            if now - self.last_cycle < self.gap:
                return True
            if self.last_cycle:
                self.gap = min(self.gap * 2, MAX_GAP)
            log(f"trigger: {'rejection' if rejected else 'stall'}, unregistered {int(lost)}s")
            self.cycle()
        return True


def main():
    k = Keeper()
    log(f"start: reject_grace={REJECT_GRACE}s stall_limit={STALL_LIMIT}s")
    GLib.timeout_add_seconds(POLL, k.tick)
    GLib.MainLoop().run()


if __name__ == "__main__":
    sys.exit(main())
