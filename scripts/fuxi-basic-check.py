#!/usr/bin/env python3
"""Read-only desktop acceptance; --network additionally makes two verified HTTPS GETs.

Does not unlock the phone, launch applications, change volume, scan WiFi, read
credentials, or treat installed applications as proof of touch interaction.
"""
import argparse
import ast
import datetime
import json
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import urllib.request


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip()[-600:]
                           or f"{args[0]} exited {result.returncode}")
    return result.stdout.strip()


def user_command(*args):
    return command("runuser", "-u", "fuxi", "--", "env",
                   "XDG_RUNTIME_DIR=/run/user/1000",
                   "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus", *args)


def device_check(network):
    result = {"captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
              "checks": [], "manual_acceptance": {
                  "touch_typing": "not assessed", "physical_charging": "not assessed",
                  "application_rendering": "not assessed", "sound": "not assessed"}}

    def check(name, probe, predicate=bool, failure="fail"):
        try:
            evidence = probe()
            status = "pass" if predicate(evidence) else failure
        except Exception as exc:
            evidence = f"{type(exc).__name__}: {exc}"
            status = failure
        result["checks"].append({"name": name, "status": status, "evidence": evidence})

    check("Linux rootfs on sda33", lambda: command("findmnt", "-n", "-o", "SOURCE", "/"),
          lambda value: value == "/dev/sda33")
    check("Rootfs has at least 1 GiB free", lambda: shutil.disk_usage("/").free,
          lambda value: value >= 1024**3)
    check("System startup complete", lambda: command("systemctl", "is-system-running"),
          lambda value: value == "running")
    check("Phosh and sensor services active", lambda: command("systemctl", "is-active",
          "phosh", "hexagonrpcd", "iio-sensor-proxy"),
          lambda value: value.splitlines() == ["active"] * 3)
    check("Keyboard and user audio services active", lambda: user_command("systemctl",
          "--user", "is-active", "mobi.phosh.OSK.service", "pipewire", "wireplumber"),
          lambda value: value.splitlines() == ["active"] * 3)
    check("Wayland session socket", lambda: Path("/run/user/1000/wayland-0").is_socket())
    check("Readable portrait keyboard sizing", lambda: user_command("gsettings", "get", "mobi.phosh.osk", "scaling"),
          lambda value: 'auto-portrait' not in value or
          any(path.is_char_device() for path in Path('/dev/dri').glob('renderD*')))
    check("Chinese on-screen Pinyin engine installed",
          lambda: command("dpkg-query", "-W", "-f=${Status}", "phosh-osk-stevia-uim"),
          lambda value: value == "install ok installed")
    check("Pinyin and English keyboard layouts configured",
          lambda: ast.literal_eval(user_command("gsettings", "get",
              "org.gnome.desktop.input-sources", "sources")),
          lambda value: ('ibus', 'uim:cn') in value and ('xkb', 'us') in value
              and ('xkb', 'cn') not in value)
    check("Timezone Asia/Shanghai", lambda: command("timedatectl", "show", "-p", "Timezone", "--value"),
          lambda value: value == "Asia/Shanghai")
    check("Network time synchronized", lambda: command("timedatectl", "show", "-p", "NTPSynchronized", "--value"),
          lambda value: value == "yes", failure="warn")
    check("HTTPS system trust store", lambda: ssl.create_default_context().cert_store_stats(),
          lambda value: value["x509_ca"] > 0)
    for app in ("epiphany", "gnome-text-editor", "kgx", "nautilus", "xdg-mime"):
        check(f"Application installed: {app}", lambda app=app: shutil.which(app))
    for package in ("language-pack-zh-hans", "language-pack-gnome-zh-hans"):
        check(f"Chinese translation package: {package}",
              lambda package=package: command("dpkg-query", "-W", "-f=${Status}", package),
              lambda value: value == "install ok installed")
    for mime in ("x-scheme-handler/http", "x-scheme-handler/https"):
        check(f"Usable default handler: {mime}",
              lambda mime=mime: user_command("xdg-mime", "query", "default", mime),
              lambda value: bool(value) and any((Path(base) / value).is_file() for base in
                  ("/usr/share/applications", "/home/fuxi/.local/share/applications")))
    check("Default speaker sink registered", lambda: user_command("wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"),
          lambda value: 'node.name = "alsa_output.platform-sound.HiFi__Speaker__sink"' in value)
    check("Default speaker volume readable", lambda: user_command("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"),
          lambda value: value.startswith("Volume:"))
    check("Battery percentage readable", lambda: int(Path("/sys/class/power_supply/qcom-battmgr-bat/capacity").read_text()),
          lambda value: 0 <= value <= 100)
    check("Default network route", lambda: json.loads(command("ip", "-j", "route", "show", "default")))
    check("WiFi associated", lambda: command("nmcli", "-t", "-f", "TYPE,STATE", "device"),
          lambda value: any(line == "wifi:connected" for line in value.splitlines()), failure="warn")
    check("Backlight control exposed", lambda: [path.name for path in Path("/sys/class/backlight").glob("*")],
          failure="warn")
    if network:
        for url in ("https://example.com/", "https://ports.ubuntu.com/ubuntu-ports/"):
            def https_probe(url=url):
                with urllib.request.urlopen(url, timeout=15, context=ssl.create_default_context()) as response:
                    return {"status": response.status, "bytes_sampled": len(response.read(256)),
                            "final_url": response.url, "certificate_verification": True}
            check(f"Verified HTTPS: {url}", https_probe,
                  lambda value: value["status"] == 200 and value["bytes_sampled"] > 0
                  and value["final_url"].startswith("https://"))
    result["summary"] = {status: sum(item["status"] == status for item in result["checks"])
                         for status in ("pass", "warn", "fail")}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", action="store_true")
    parser.add_argument("--device", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.device:
        print(json.dumps(device_check(args.network), indent=2))
        return 0
    root = Path(__file__).resolve().parents[1]
    remote = "python3 - --device" + (" --network" if args.network else "")
    response = subprocess.run([str(root / "scripts/fuxi-ssh.sh"), remote],
                              input=Path(__file__).read_text(), capture_output=True,
                              text=True, timeout=150)
    if response.returncode:
        sys.stderr.write(response.stderr + response.stdout)
        return response.returncode
    result = json.loads(response.stdout)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S-%fZ")
    log = root / "work/claude-logs" / f"basic-check-{stamp}.json"
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(json.dumps(result, indent=2) + "\n")
    for item in result["checks"]:
        print(f"{item['status'].upper()} {item['name']}")
        if item["status"] != "pass":
            print(f"  {item['evidence']}")
    print(f"Summary: {result['summary']}")
    print(f"Evidence: {log}")
    print("Touch, typing, app rendering, physical charging and sound require separate evidence.")
    return int(result["summary"]["fail"] > 0)


if __name__ == "__main__":
    sys.exit(main())
