#!/usr/bin/env python3
"""Functional self-test of the mobile overlay via the bridge (single CDP owner)."""
import sys, time
sys.path.insert(0, "/opt/chromium/mobile")
import probe

def ev(expr):
    import urllib.request, urllib.parse
    return urllib.request.urlopen("http://127.0.0.1:9223/eval?e=" + urllib.parse.quote(expr), timeout=10).read().decode()

print("state:", probe.get("/state").decode())
print("overlay:", ev("JSON.stringify({top:!!document.getElementById('fx-top'),bottom:!!document.getElementById('fx-bottom'),btns:document.querySelectorAll('#fx-bottom button').length,addr:document.getElementById('fx-url').textContent})"))
print("click home:", ev("document.querySelector('#fx-bottom button[data-a=home]').click(), 'ok'"))
time.sleep(3)
print("state after home:", probe.get("/state").decode())
open("/tmp/ui-final.png","wb").write(probe.get("/shot"))
print("shot saved")
