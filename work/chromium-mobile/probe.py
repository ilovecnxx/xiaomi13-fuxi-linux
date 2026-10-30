#!/usr/bin/env python3
"""Probe the fuxi mobile shell bridge: state / overlay presence / optional screenshot + navigate."""
import base64
import json
import sys
import urllib.request
import urllib.parse

B = "http://127.0.0.1:9223"


def get(path, **q):
    url = B + path + ("?" + urllib.parse.urlencode(q) if q else "")
    return urllib.request.urlopen(url, timeout=10).read()


def post(path, obj):
    req = urllib.request.Request(B + path, data=json.dumps(obj).encode(),
                                 headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=10).read()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "state"
    if cmd == "state":
        print(get("/state").decode())
    elif cmd == "eval":
        print(get("/eval", e=sys.argv[2]).decode())
    elif cmd == "shot":
        open(sys.argv[2], "wb").write(get("/shot"))
        print("saved", sys.argv[2])
    elif cmd == "nav":
        print(post("/navigate", {"url": sys.argv[2]}).decode())
    elif cmd == "overlay":
        expr = ("JSON.stringify({top:!!document.getElementById('fx-top'),"
                "bottom:!!document.getElementById('fx-bottom'),"
                "dark:matchMedia('(prefers-color-scheme: dark)').matches,"
                "title:document.title,href:location.href,"
                "bottomBg:document.getElementById('fx-bottom')?getComputedStyle(document.getElementById('fx-bottom')).backgroundColor:null})")
        print(get("/eval", e=expr).decode())


if __name__ == "__main__":
    main()
