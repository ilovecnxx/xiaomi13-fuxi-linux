#!/usr/bin/python3
# 设置基带 NAS usage preference（voice-centric / data-centric），生效期限只到基带下次重启（power-cycle）。
# 没有 IMS 时 voice-centric 会在 LTE 附着后放弃 LTE（TS 24.301 5.5.3.2.5），data-centric 不会。
# 用法（手机上，root）：fuxi-qmi-usage.py [data|voice|get]，需先停 ModemManager 或确保 qrtr 客户端可用。
import sys
import gi
gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import GLib, Qmi, Qrtr

mode = sys.argv[1] if len(sys.argv) > 1 else "get"
loop = GLib.MainLoop()
state = {"dev": None, "cid": None, "rc": 1}


def finish():
    if state["dev"] and state["cid"]:
        state["dev"].release_client(state["cid"], Qmi.DeviceReleaseClientFlags.RELEASE_CID, 10, None,
                                    lambda d, r: (d.release_client_finish(r), loop.quit()))
    else:
        loop.quit()


def got_pref(client, res):
    out = client.get_system_selection_preference_finish(res)
    out.get_result()
    for name in ("usage_preference", "voice_domain_preference", "service_domain_preference"):
        try:
            print(name, getattr(out, "get_" + name)())
        except GLib.Error as e:
            print(name, "n/a", e.message)
    state["rc"] = 0
    finish()


def set_done(client, res):
    out = client.set_system_selection_preference_finish(res)
    out.get_result()
    print("set ok")
    client.get_system_selection_preference(None, 10, None, got_pref)


def got_client(dev, res):
    client = dev.allocate_client_finish(res)
    state["cid"] = client
    if mode == "get":
        client.get_system_selection_preference(None, 10, None, got_pref)
        return
    inp = Qmi.MessageNasSetSystemSelectionPreferenceInput.new()
    inp.set_usage_preference(Qmi.NasUsagePreference.DATA_CENTRIC if mode == "data"
                             else Qmi.NasUsagePreference.VOICE_CENTRIC)
    inp.set_change_duration(Qmi.NasChangeDuration.POWER_CYCLE)
    client.set_system_selection_preference(inp, 10, None, set_done)


def opened(dev, res):
    dev.open_finish(res)
    dev.allocate_client(Qmi.Service.NAS, Qmi.CID_NONE, 10, None, got_client)


def created(_src, res):
    dev = Qmi.Device.new_from_node_finish(res)
    state["dev"] = dev
    dev.open(Qmi.DeviceOpenFlags.PROXY, 10, None, opened)


def bus_ready(_src, res):
    bus = Qrtr.Bus.new_finish(res)
    state["bus"] = bus
    node = bus.peek_node(0)
    if node is None:
        print("qrtr node 0 not found")
        loop.quit()
        return
    Qmi.Device.new_from_node(node, None, created)


Qrtr.Bus.new(1000, None, bus_ready)


def guard():
    print("timeout")
    loop.quit()


GLib.timeout_add_seconds(30, guard)
try:
    loop.run()
except GLib.Error as e:
    print("error", e.message)
sys.exit(state["rc"])
