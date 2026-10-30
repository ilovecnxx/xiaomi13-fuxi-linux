#!/usr/bin/env python3
# Set NAS usage preference on the fuxi modem until the next power cycle.
# Usage: fuxi-qmi-usage-pref.py data-centric|voice-centric
import sys

import gi
gi.require_version("Qmi", "1.0")
gi.require_version("Qrtr", "1.0")
from gi.repository import Gio, GLib, Qmi, Qrtr

PREFS = {
    "data-centric": Qmi.NasUsagePreference.DATA_CENTRIC,
    "voice-centric": Qmi.NasUsagePreference.VOICE_CENTRIC,
}

if len(sys.argv) != 2 or sys.argv[1] not in PREFS:
    sys.exit(f"usage: {sys.argv[0]} {'|'.join(PREFS)}")

loop = GLib.MainLoop()
state = {"rc": 1}


def fail(msg):
    print(msg, file=sys.stderr)
    loop.quit()


def on_set(client, res, dev):
    try:
        out = client.set_system_selection_preference_finish(res)
        out.get_result()
        print(f"usage preference set to {sys.argv[1]} (power-cycle)")
        state["rc"] = 0
    except GLib.Error as e:
        fail(f"set failed: {e.message}")
    dev.release_client(client, Qmi.DeviceReleaseClientFlags.RELEASE_CID, 10,
                       None, lambda d, r: loop.quit())


def on_client(dev, res):
    try:
        client = dev.allocate_client_finish(res)
    except GLib.Error as e:
        return fail(f"allocate failed: {e.message}")
    inp = Qmi.MessageNasSetSystemSelectionPreferenceInput.new()
    inp.set_usage_preference(PREFS[sys.argv[1]])
    inp.set_change_duration(Qmi.NasChangeDuration.POWER_CYCLE)
    client.set_system_selection_preference(inp, 10, None, on_set, dev)


def on_open(dev, res):
    try:
        dev.open_finish(res)
    except GLib.Error as e:
        return fail(f"open failed: {e.message}")
    dev.allocate_client(Qmi.Service.NAS, Qmi.CID_NONE, 10, None, on_client)


def on_device(_src, res):
    try:
        dev = Qmi.Device.new_from_node_finish(res)
    except GLib.Error as e:
        return fail(f"device failed: {e.message}")
    dev.open(Qmi.DeviceOpenFlags.NONE, 10, None, on_open)


def on_node(bus, res):
    try:
        node = bus.wait_for_node_finish(res)
    except GLib.Error as e:
        return fail(f"qrtr node failed: {e.message}")
    Qmi.Device.new_from_node(node, None, on_device)


def on_bus(_src, res):
    try:
        bus = Qrtr.Bus.new_finish(res)
    except GLib.Error as e:
        return fail(f"qrtr bus failed: {e.message}")
    state["bus"] = bus
    bus.wait_for_node(0, 10000, None, on_node)


Qrtr.Bus.new(1000, None, on_bus)
loop.run()
sys.exit(state["rc"])
