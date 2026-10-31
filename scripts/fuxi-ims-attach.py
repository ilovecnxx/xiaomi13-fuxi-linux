#!/usr/bin/python3
# IMS 承载建立矩阵测试（手机上 root 运行）。
# 背景：qmicli 在 qrtr 上不能「bind + 动作」同进程，且没有 Android 用的 WDS Start Network Interface；
# 这里用 libqmi-glib（GI）在同一进程里依次尝试多种启动方式，一次上机就能把变体试完。
#   1) profile 4（APN 档，type=ims）        2) apn=IMS + ipv6        3) apn=ims + ipv6
#   4) apn=IMS + ipv4                      5) apn=IMS 不指定 ip 族   6) profile 4 + 绑定 mux 1
# 第一个成功的承载会**保留**（便于接着查 imsa 注册），并打印 P-CSCF / 地址；其余失败只记录原因。
import sys

import gi

gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import GLib, Qmi, Qrtr

ATTEMPTS = [
    ("profile4", {"profile": 4}),
    ("apn=IMS ipv6", {"apn": "IMS", "ip": Qmi.WdsIpFamily.IPV6}),
    ("apn=ims ipv6", {"apn": "ims", "ip": Qmi.WdsIpFamily.IPV6}),
    ("apn=IMS ipv4", {"apn": "IMS", "ip": Qmi.WdsIpFamily.IPV4}),
    ("apn=IMS dual", {"apn": "IMS"}),
    ("profile4 + mux1", {"profile": 4, "mux": 1}),
]

loop = GLib.MainLoop()
st = {"dev": None, "idx": 0, "client": None, "fails": [], "ok": [], "handle": None, "cur": None}


def release_then(fn):
    c, st["client"] = st["client"], None
    if c is None:
        fn()
        return

    def done(dev, res):
        try:
            dev.release_client_finish(res)
        except GLib.Error:
            pass
        fn()

    st["dev"].release_client(c, Qmi.DeviceReleaseClientFlags.RELEASE_CID, 10, None, done)


def finish(rc=0):
    def end():
        st["dev"].close_async(10, None, lambda d, r: loop.quit())
        st["rc"] = rc

    st["rc"] = rc
    release_then(end)


def report():
    print()
    print("== 结果 ==")
    for name, why in st["fails"]:
        print("  ✗ %-18s %s" % (name, why))
    for name in st["ok"]:
        print("  ✓ %-18s 承载已建立" % name)
    if st["handle"] is not None:
        print("  packet data handle = %s（保留中，断开用 qmicli --wds-stop-network=%s）"
              % (st["handle"], st["handle"]))
    if not st["ok"]:
        print("  结论：全部失败。下一步考虑用原始 QMI 发 WDS Start Network Interface(0x00A0)。")


# ---- 各步骤 ----
def on_settings(client, res):
    try:
        out = client.get_current_settings_finish(res)
        out.get_result()
    except GLib.Error as e:
        print("  (读 current settings 失败: %s)" % e.message)
        return after_success()
    for getter in ("get_pcscf_address", "get_ipv4_address", "get_ipv6_address", "get_mtu"):
        try:
            print("  %-20s %s" % (getter[4:] + ":", getattr(out, getter)()))
        except Exception:
            pass
    after_success()


def after_success():
    # 有承载了，顺带查一次 imsa 注册状态（外部脚本，避免重复实现）
    try:
        r = subprocess_run()
        print("  --- imsa/ims ---")
        print(r)
    except Exception as e:  # noqa: BLE001
        print("  (imsa 查询失败: %s)" % e)
    report()


def subprocess_run():
    import subprocess
    p = subprocess.run(["/usr/local/sbin/fuxi-qmi-ims.py"], capture_output=True, text=True, timeout=40)
    return (p.stdout + p.stderr).strip()


def on_started(name, a, client, res):
    try:
        out = client.start_network_finish(res)
        out.get_result()
    except GLib.Error as e:
        st["fails"].append((name, "%s (%s)" % (e.message, a)))
        print("  ✗ %-18s %s" % (name, e.message))
        release_then(next_attempt)
        return
    try:
        st["handle"] = out.get_packet_data_handle()
    except Exception:
        st["handle"] = None
    st["ok"].append(name)
    print("  ✓ %-18s handle=%s" % (name, st["handle"]))
    try:
        inp = Qmi.MessageWdsGetCurrentSettingsInput.new()
        client.get_current_settings(inp, 15, None, on_settings)
    except Exception:
        after_success()


def do_start(name, a, client):
    inp = Qmi.MessageWdsStartNetworkInput.new()
    if "profile" in a:
        inp.set_profile_index_3gpp(a["profile"])
    if "apn" in a:
        inp.set_apn(a["apn"])
    if "ip" in a:
        inp.set_ip_family_preference(a["ip"])
    client.start_network(inp, 30, None, lambda c, r: on_started(name, a, c, r))


def on_bound(name, a, client, res):
    try:
        out = client.bind_mux_data_port_finish(res)
        out.get_result()
        print("  (mux 1 已绑定)")
    except GLib.Error as e:
        st["fails"].append((name, "bind_mux: " + e.message))
        print("  ✗ %-18s bind_mux: %s" % (name, e.message))
        release_then(next_attempt)
        return
    do_start(name, a, client)


def bind_mux(name, a, client):
    inp = Qmi.MessageWdsBindMuxDataPortInput.new()
    inp.set_mux_id(a["mux"])
    inp.set_client_type(Qmi.WdsClientType.TETHERED)
    inp.set_endpoint_info(Qmi.DataEndpointType.EMBEDDED, 0)
    client.bind_mux_data_port(inp, 15, None, lambda c, r: on_bound(name, a, c, r))


def on_link(dev, res):
    name, a, _client = st["cur"]
    try:
        ifname = dev.add_link_finish(res, a["mux"])
        print("  (已建链路 %s, mux %s)" % (ifname, a["mux"]))
    except GLib.Error as e:
        print("  (add_link 失败，继续: %s)" % e.message)
    bind_mux(*st["cur"])


def with_mux(name, a, client):
    st["cur"] = (name, a, client)
    try:
        st["dev"].add_link(a["mux"], "rmnet_ipa0", "rmnet", None, on_link)
    except Exception as e:  # noqa: BLE001
        print("  (add_link 不可用: %s)" % e)
        bind_mux(name, a, client)


def on_client(name, a, dev, res):
    try:
        client = dev.allocate_client_finish(res)
    except GLib.Error as e:
        st["fails"].append((name, "allocate: " + e.message))
        print("  ✗ %-18s allocate: %s" % (name, e.message))
        next_attempt()
        return
    st["client"] = client
    if a.get("mux"):
        with_mux(name, a, client)
    else:
        do_start(name, a, client)


def next_attempt():
    if st["idx"] >= len(ATTEMPTS):
        report()
        finish(0 if st["ok"] else 1)
        return
    name, a = ATTEMPTS[st["idx"]]
    st["idx"] += 1
    print("-- 尝试 %s" % name)
    st["dev"].allocate_client(Qmi.Service.WDS, Qmi.CID_NONE, 10, None,
                              lambda d, r: on_client(name, a, d, r))


def on_opened(dev, res):
    try:
        dev.open_finish(res)
    except GLib.Error as e:
        print("device open 失败:", e.message)
        loop.quit()
        return
    st["dev"] = dev
    next_attempt()


def on_created(_s, res):
    try:
        dev = Qmi.Device.new_from_node_finish(res)
    except GLib.Error as e:
        print("new_from_node 失败:", e.message)
        loop.quit()
        return
    dev.open(Qmi.DeviceOpenFlags.PROXY, 10, None, on_opened)


def on_bus(_s, res):
    try:
        bus = Qrtr.Bus.new_finish(res)
    except GLib.Error as e:
        print("qrtr bus 失败:", e.message)
        loop.quit()
        return
    node = bus.peek_node(0)
    if node is None:
        print("qrtr node 0 不存在")
        loop.quit()
        return
    Qmi.Device.new_from_node(node, None, on_created)


if __name__ == "__main__":
    arg = sys.argv[1] if sys.argv[1:] else "up"
    if arg == "mux":
        ATTEMPTS = [a for a in ATTEMPTS if a[1].get("mux")]
    elif arg not in ("up",):
        print("用法: fuxi-ims-attach.py [up|mux]")
        sys.exit(2)
    Qrtr.Bus.new(1000, None, on_bus)
    GLib.timeout_add_seconds(180, lambda: (print("超时"), loop.quit(), False)[2])
    loop.run()
    sys.exit(st.get("rc", 1))
