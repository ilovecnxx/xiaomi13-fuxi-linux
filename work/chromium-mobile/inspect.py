#!/usr/bin/env python3
import urllib.request, urllib.parse, json, sys
B="http://127.0.0.1:9223"
def ev(expr):
    return urllib.request.urlopen(B+"/eval?e="+urllib.parse.quote(expr),timeout=10).read().decode()
expr = ("JSON.stringify({title:document.title,href:location.href,"
        "text:(document.body?document.body.innerText:'').slice(0,400)})")
print(ev(expr))
