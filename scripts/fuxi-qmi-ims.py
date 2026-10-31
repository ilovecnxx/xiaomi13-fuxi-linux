#!/usr/bin/python3
# 只读查询基带 IMS 状态。qmicli 在 qrtr 上无法「bind + 查询」同进程（报 too many IMSA actions），
# 这里用 libqmi-glib（GI）在同一进程内 bind 后再查询。
# 用法（手机上，root）：fuxi-qmi-ims.py [status]   # 目前只实现只读 status
import sys

import gi

gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import GLib, Qmi, Qrtr

loop = GLib.MainLoop()
state = {"dev": None, "clients": [], "rc": 1, "steps": []}


def fail(msg, err=None):
    print("FAIL:", msg, err.message if err is not None else "")
    state["rc"] = 1
    shutdown()


def show(obj, names):
    for n in names:
        try:
            print("  %-46s %s" % (n + ":", getattr(obj, "get_" + n)()))
        except Exception as e:  # noqa: BLE001
            print("  %-46s n/a (%s)" % (n + ":", e))


def shutdown():
    if state["clients"]:
        c = state["clients"].pop(0)
        state["dev"].release_client(c, Qmi.DeviceReleaseClientFlags.RELEASE_CID, 10, None,
                                    lambda d, r: shutdown())
        return
    if state["dev"]:
        d = state["dev"]
        state["dev"] = None
        d.close_async(10, None, lambda dd, r: loop.quit())
        return
    loop.quit()


def step_next():
    if not state["steps"]:
        state["rc"] = 0
        shutdown()
        return
    state["steps"].pop(0)()


# ---- IMSA：注册状态 ----
def imsa_reg_done(client, res):
    try:
        out = client.get_ims_registration_status_finish(res)
        out.get_result()
    except GLib.Error as e:
        fail("imsa get_ims_registration_status", e)
        return
    print("[imsa] 注册状态")
    show(out, ["ims_registration_status", "ims_registration_technology",
               "ims_registration_error_code", "ims_registration_error_message"])


def imsa_svc_done(client, res):
    try:
        out = client.get_ims_services_status_finish(res)
        out.get_result()
    except GLib.Error as e:
        fail("imsa get_ims_services_status", e)
        return
    print("[imsa] 各业务")
    show(out, ["ims_voice_service_status", "ims_voice_service_registration_technology",
               "ims_sms_service_status", "ims_sms_service_registration_technology",
               "ims_video_telephony_service_status", "ims_ue_to_tas_service_status",
               "ims_video_share_service_status"])
    step_next()


def imsa_bound(client, res):
    try:
        out = client.bind_finish(res)
        out.get_result()
    except GLib.Error as e:
        fail("imsa bind(0)", e)
        return
    client.get_ims_registration_status(None, 10, None, imsa_reg_done)
    client.get_ims_services_status(None, 10, None, imsa_svc_done)


def imsa_alloc(dev, res):
    try:
        client = dev.allocate_client_finish(res)
    except GLib.Error as e:
        fail("allocate IMSA client", e)
        return
    state["clients"].append(client)
    inp = Qmi.MessageImsaBindInput.new()
    inp.set_binding(0)  # 0 = primary
    client.bind(inp, 10, None, imsa_bound)


# ---- IMS settings：业务开关 ----
def ims_setting_done(client, res):
    try:
        out = client.get_ims_services_enabled_setting_finish(res)
        out.get_result()
    except GLib.Error as e:
        fail("ims get_ims_services_enabled_setting", e)
        return
    print("[ims] 业务开关")
    show(out, ["ims_voice_service_enabled", "ims_sms_service_enabled",
               "ims_video_telephony_service_enabled", "ims_ut_service_enabled",
               "ims_ussd_service_enabled", "ims_voice_wifi_service_enabled"])
    step_next()


def ims_bound(client, res):
    try:
        out = client.bind_finish(res)
        out.get_result()
    except GLib.Error as e:
        fail("ims bind(0)", e)
        return
    client.get_ims_services_enabled_setting(None, 10, None, ims_setting_done)


def ims_alloc(dev, res):
    try:
        client = dev.allocate_client_finish(res)
    except GLib.Error as e:
        fail("allocate IMS settings client", e)
        return
    state["clients"].append(client)
    inp = Qmi.MessageImsBindInput.new()
    inp.set_binding(0)
    client.bind(inp, 10, None, ims_bound)


# ---- 启动 ----
def device_opened(dev, res):
    try:
        dev.open_finish(res)
    except GLib.Error as e:
        fail("device open", e)
        return
    state["dev"] = dev
    state["steps"] = [
        lambda: dev.allocate_client(Qmi.Service.IMSA, Qmi.CID_NONE, 10, None, imsa_alloc),
        lambda: dev.allocate_client(Qmi.Service.IMS, Qmi.CID_NONE, 10, None, ims_alloc),
    ]
    step_next()


def device_created(_src, res):
    try:
        dev = Qmi.Device.new_from_node_finish(res)
    except GLib.Error as e:
        fail("new_from_node", e)
        return
    dev.open(Qmi.DeviceOpenFlags.PROXY, 10, None, device_opened)


def bus_ready(_src, res):
    try:
        bus = Qrtr.Bus.new_finish(res)
    except GLib.Error as e:
        fail("qrtr bus", e)
        return
    node = bus.peek_node(0)
    if node is None:
        fail("qrtr node 0 not found")
        return
    Qmi.Device.new_from_node(node, None, device_created)


Qrtr.Bus.new(1000, None, bus_ready)
GLib.timeout_add_seconds(30, lambda: (fail("timeout"), False)[1])
try:
    loop.run()
except GLib.Error as e:
    print("error", e.message)
sys.exit(state["rc"])
