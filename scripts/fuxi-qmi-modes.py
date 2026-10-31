#!/usr/bin/python3
# 恢复/设置 RAT 模式偏好（qmicli 一次只能给一个值，这里用 GI 一次性写位掩码）。
# 用法（手机上 root）：fuxi-qmi-modes.py [all|lte|nr]  默认 all = gsm|umts|lte|nr5g（持久）
import sys
import gi

gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import GLib, Qmi, Qrtr

MASKS = {"all": 4 | 8 | 16 | 64, "lte": 16, "nr": 64 | 16}
mode = sys.argv[1] if len(sys.argv) > 1 else "all"
mask = MASKS.get(mode)
if mask is None:
    print("用法: fuxi-qmi-modes.py [all|lte|nr]")
    sys.exit(2)

loop = GLib.MainLoop()
st = {}


def quit_():
    d = st.pop("dev", None)
    if d:
        d.close_async(10, None, lambda dd, r: loop.quit())
    else:
        loop.quit()


def done(c, res):
    try:
        o = c.set_system_selection_preference_finish(res)
        o.get_result()
        print("ok mode_preference=%d" % mask)
    except GLib.Error as e:
        print("ERR", e.message)
    quit_()


def got(c, res):
    try:
        c = st["dev"].allocate_client_finish(res)
    except GLib.Error as e:
        print("ERR alloc", e.message)
        loop.quit()
        return
    st["c"] = c
    inp = Qmi.MessageNasSetSystemSelectionPreferenceInput.new()
    inp.set_mode_preference(mask)
    inp.set_change_duration(Qmi.NasChangeDuration.PERMANENT)
    c.set_system_selection_preference(inp, 10, None, done)


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
