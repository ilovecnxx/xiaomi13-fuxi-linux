#!/usr/bin/python3
# 设置 NAS 语音域/使用偏好（只写这两项，不动模式偏好）。
# 用法（手机上 root）：fuxi-qmi-prefs.py [voice=cs|ps] [usage=data|voice]
#   默认只读取当前值。cs=CS_PREFERRED（会促成 combined attach，短信走 SGs），ps=PS_PREFERRED（VoLTE 优先）
import sys
import gi

gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import GLib, Qmi, Qrtr

VOICE = {"cs": Qmi.NasVoiceDomainPreference.CS_PREFERRED, "ps": Qmi.NasVoiceDomainPreference.PS_PREFERRED}
USAGE = {"data": Qmi.NasUsagePreference.DATA_CENTRIC, "voice": Qmi.NasUsagePreference.VOICE_CENTRIC}

args = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
loop = GLib.MainLoop()
st = {}


def quit_():
    d = st.pop("dev", None)
    if d:
        d.close_async(10, None, lambda dd, r: loop.quit())
    else:
        loop.quit()


def shown(c, res):
    o = c.get_system_selection_preference_finish(res)
    o.get_result()
    for k in ("voice_domain_preference", "usage_preference", "service_domain_preference",
              "mode_preference"):
        try:
            print("  %-28s %s" % (k + ":", getattr(o, "get_" + k)()))
        except Exception as e:  # noqa: BLE001
            print("  %-28s n/a (%s)" % (k + ":", e))
    quit_()


def set_done(c, res):
    try:
        o = c.set_system_selection_preference_finish(res)
        o.get_result()
        print("set ok")
    except GLib.Error as e:
        print("ERR", e.message)
        quit_()
        return
    c.get_system_selection_preference(None, 10, None, shown)


def got(c, res):
    c = st["dev"].allocate_client_finish(res)
    st["c"] = c
    if not args:
        c.get_system_selection_preference(None, 10, None, shown)
        return
    inp = Qmi.MessageNasSetSystemSelectionPreferenceInput.new()
    if "voice" in args:
        inp.set_voice_domain_preference(VOICE[args["voice"]])
    if "usage" in args:
        inp.set_usage_preference(USAGE[args["usage"]])
    if args.get("when") == "perm":
        inp.set_change_duration(Qmi.NasChangeDuration.PERMANENT)
    elif args.get("when") != "now":  # 不设 TLV = 立即生效（枚举里没有 IMMEDIATE）
        inp.set_change_duration(Qmi.NasChangeDuration.POWER_CYCLE)
    c.set_system_selection_preference(inp, 10, None, set_done)


def opened(d, res):
    st["dev"] = d
    d.open_finish(res)
    d.allocate_client(Qmi.Service.NAS, Qmi.CID_NONE, 10, None, got)


def created(_s, res):
    d = Qmi.Device.new_from_node_finish(res)
    d.open(Qmi.DeviceOpenFlags.PROXY, 10, None, opened)


def bus(_s, res):
    b = Qrtr.Bus.new_finish(res)
    Qmi.Device.new_from_node(b.peek_node(0), None, created)


Qrtr.Bus.new(1000, None, bus)
GLib.timeout_add_seconds(20, lambda: (loop.quit(), False)[1])
loop.run()
