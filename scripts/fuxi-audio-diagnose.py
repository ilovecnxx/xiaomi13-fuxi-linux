#!/usr/bin/env python3
"""Inspect fuxi speaker registers; optionally exercise desktop playback with silence.

Register definitions: build/linux/include/sound/cs35l41.h and cs35l41.c.
Reads regmap debugfs without changing cache policy or writing registers/mixers.
Never records audio. Passing --desktop-silence plays a bounded zero-filled WAV.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import wave


REGISTERS = {
    0x2014: "power1", 0x2018: "power2", 0x2C04: "pll_control",
    0x2C0C: "sample_rate", 0x4800: "asp_enables", 0x4808: "asp_format",
    0x4820: "rx_slots", 0x4840: "rx_word_length", 0x4C00: "dac_source",
    0x6000: "digital_volume", 0x6C04: "analog_gain",
    0x10010: "latched_status1", 0x10018: "latched_status3",
    0x10090: "raw_status1", 0x10098: "raw_status3",
}
FAULT_MASK = 0x800281C0  # amp/boost short, boost OV/UV, temperature warning/error


def command(*args, timeout=12):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT,
                                   timeout=timeout)


def read_text(path):
    return Path(path).read_text().strip()


def parse_registers(lines):
    result = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-fA-F]+):\s+([0-9a-fA-F]+)\s*", line)
        if not match:
            continue
        address, value = (int(part, 16) for part in match.groups())
        if address > max(REGISTERS):
            break  # Do not walk the large DSP memory area.
        if address in REGISTERS:
            result[REGISTERS[address]] = value
    return result


def snapshot(card):
    result = {"monotonic": time.monotonic(), "amplifiers": {}}
    pcm = Path(f"/proc/asound/card{card}/pcm0p/sub0")
    result["pcm_status"] = read_text(pcm / "status")
    result["pcm_hw_params"] = read_text(pcm / "hw_params")
    for address, prefix in (("0040", "B"), ("0042", "T")):
        candidates = list(Path("/sys/kernel/debug/regmap").glob(f"*-{address}"))
        if len(candidates) != 1:
            raise RuntimeError(f"Expected one amplifier @{address}: {candidates}")
        regmap = candidates[0]
        with (regmap / "registers").open() as registers:
            values = parse_registers(registers)
        dapm = list(Path("/sys/kernel/debug/asoc/Xiaomi-13").glob(
            f"cs35l41.*-{address}/dapm/{prefix} Main AMP"))
        if len(dapm) != 1:
            raise RuntimeError(f"Expected one {prefix} Main AMP DAPM path")
        result["amplifiers"][prefix] = {
            "regmap": regmap.name, "cache_only": read_text(regmap / "cache_only"),
            "registers": values, "dapm": read_text(dapm[0]),
        }
    return result


def playback_checks(sample):
    """Check the current speaker-only, 48 kHz / 16-bit / two-slot configuration."""
    checks = []

    def check(label, passed):
        checks.append({"check": label, "passed": bool(passed)})

    check("ALSA PCM is RUNNING", bool(re.search(r"^state:\s+RUNNING$",
          sample["pcm_status"], re.M)))
    for prefix, slot in (("B", 1), ("T", 0)):
        amp = sample["amplifiers"].get(prefix, {})
        regs = amp.get("registers", {})
        missing = set(REGISTERS.values()) - set(regs)
        check(f"{prefix} all diagnostic registers readable", not missing)
        if missing:
            continue
        check(f"{prefix} volatile status is not cache-only", amp["cache_only"] == "N")
        check(f"{prefix} DAPM amplifier on", amp["dapm"].startswith(f"{prefix} Main AMP: On"))
        check(f"{prefix} GLOBAL_EN and AMP_EN set",
              regs["power1"] & 1 and regs["power2"] & 1)
        check(f"{prefix} ASPRX1 enabled and routed to DAC",
              regs["asp_enables"] & 0x10000 and regs["dac_source"] & 0x7F == 8)
        check(f"{prefix} receives configured slot {slot}", regs["rx_slots"] & 0x3F == slot)
        check(f"{prefix} 48 kHz, I2S, 16-bit receive format",
              regs["sample_rate"] & 0x1F == 3 and
              (regs["asp_format"] >> 8) & 7 == 2 and
              (regs["asp_format"] >> 24) & 0xFF == 16 and
              regs["rx_word_length"] & 0x3F == 16)
        check(f"{prefix} PLL configured for 1.536 MHz BCLK",
              regs["pll_control"] & 0x817 == 0x10 and
              (regs["pll_control"] >> 5) & 0x3F == 0x1B)
        check(f"{prefix} live PLL locked without unlock",
              regs["raw_status3"] & 0x12 == 2)
        check(f"{prefix} no live thermal/boost/short fault",
              regs["raw_status1"] & FAULT_MASK == 0)
        check(f"{prefix} digital gain remains conservative (-30 dB)",
              (regs["digital_volume"] >> 3) & 0x7FF == (0x4CF + 577) & 0x7FF)
        check(f"{prefix} analog gain matches tested raw 5", (regs["analog_gain"] >> 5) & 0x1F == 5)
    return checks


def hw_pointer(sample):
    match = re.search(r"^hw_ptr\s*:\s*(\d+)$", sample["pcm_status"], re.M)
    return int(match.group(1)) if match else None


def pipewire_threads(user):
    pid = int(command(*user, "systemctl", "--user", "show", "pipewire.service",
                      "--property=MainPID", "--value").strip())
    if pid <= 0:
        raise RuntimeError("The fuxi PipeWire service is not running")
    result = []
    for task in sorted(Path(f"/proc/{pid}/task").iterdir()):
        try:
            tid = int(task.name)
            result.append({"tid": tid, "name": read_text(task / "comm"),
                           "scheduler": os.sched_getscheduler(tid),
                           "priority": os.sched_getparam(tid).sched_priority})
        except (FileNotFoundError, ProcessLookupError):
            continue
    return {"pid": pid, "threads": result}


def has_realtime_data_loop(pipewire):
    # RTKit deliberately sets RESET_ON_FORK; sched_getscheduler includes that flag.
    reset_on_fork = getattr(os, "SCHED_RESET_ON_FORK", 0x40000000)
    return any(thread["name"].startswith("data-loop") and
               (thread["scheduler"] & ~reset_on_fork) in (os.SCHED_FIFO, os.SCHED_RR) and
               thread["priority"] > 0 for thread in pipewire["threads"])


def device_run(play_silence):
    if "fuxi.fb=" not in read_text("/proc/cmdline"):
        raise RuntimeError("Not the expected fuxi Linux environment")
    cards = read_text("/proc/asound/cards")
    match = re.search(r"^\s*(\d+)\s+\[Xiaomi", cards, re.M)
    if not match:
        raise RuntimeError("Xiaomi soundcard is missing")
    card = match.group(1)
    user = ["runuser", "-u", "fuxi", "--", "env",
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus",
            "XDG_RUNTIME_DIR=/run/user/1000"]
    result = {"captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "kernel": command("uname", "-rv").strip(),
              "boot_id": read_text("/proc/sys/kernel/random/boot_id"),
              "mode": "desktop-silence" if play_silence else "snapshot",
              "physical_sound_assessed_by_this_test": False,
              "status": command(*user, "wpctl", "status"),
              "before": snapshot(card), "pipewire": pipewire_threads(user), "checks": []}
    if not play_silence:
        return result
    if result["before"]["pcm_status"] != "closed":
        raise RuntimeError("Playback PCM is busy; do not disturb an existing stream")
    cursor = command("journalctl", "-b", "-k", "-n", "0", "--show-cursor", "--no-pager")
    cursor = cursor.split("-- cursor: ", 1)[1].strip()
    process = None
    # TemporaryFile keeps player stderr bounded on disk and avoids pipe deadlocks.
    with tempfile.NamedTemporaryFile(prefix="fuxi-audio-diag-", suffix=".wav") as wav, \
            tempfile.TemporaryFile(mode="w+") as output:
        with wave.open(wav.name, "wb") as stream:
            stream.setnchannels(2)
            stream.setsampwidth(2)
            stream.setframerate(48000)
            stream.writeframes(bytes(48000 * 4 * 8))
        os.chmod(wav.name, 0o644)
        try:
            process = subprocess.Popen(["timeout", "15", *user, "pw-play", wav.name],
                                       stdout=output, stderr=output)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                status = read_text(f"/proc/asound/card{card}/pcm0p/sub0/status")
                if "RUNNING" in status or process.poll() is not None:
                    break
                time.sleep(0.1)
            result["during"] = snapshot(card)
            time.sleep(0.25)
            result["later_pcm_status"] = read_text(f"/proc/asound/card{card}/pcm0p/sub0/status")
            result["checks"] = playback_checks(result["during"])
            result["pipewire_during"] = pipewire_threads(user)
            result["checks"].append({"check": "PipeWire data loop has realtime scheduling",
                                     "passed": has_realtime_data_loop(result["pipewire_during"])})
            first = hw_pointer(result["during"])
            second = hw_pointer({"pcm_status": result["later_pcm_status"]})
            result["checks"].append({"check": "ALSA hardware pointer advances",
                                     "passed": first is not None and second is not None and first != second})
            rc = process.wait(timeout=18)
            output.seek(0)
            result["player_output"] = output.read()
            result["checks"].append({"check": "Silent desktop playback completed", "passed": rc == 0})
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait(timeout=18)
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if read_text(f"/proc/asound/card{card}/pcm0p/sub0/status") == "closed":
            break
        time.sleep(0.2)
    result["after"] = snapshot(card)
    for prefix in ("B", "T"):
        amp = result["after"]["amplifiers"][prefix]
        result["checks"].append({"check": f"{prefix} amplifier returns to idle",
                                 "passed": amp["dapm"].startswith(f"{prefix} Main AMP: Off") and
                                 amp["registers"].get("power1", 1) & 1 == 0 and
                                 amp["registers"].get("power2", 1) & 1 == 0})
    result["new_kernel_messages"] = command("journalctl", "-b", "-k", f"--after-cursor={cursor}", "--no-pager")
    errors = re.search(r"cs35l41.*(?:fault|error)|q6apm.*(?:timeout|error)|audioreach.*(?:error|fail)|ASoC.*failed|I/O error|PLL.*unlock",
                       result["new_kernel_messages"], re.I)
    result["checks"].append({"check": "No new audio driver errors", "passed": errors is None})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop-silence", action="store_true")
    parser.add_argument("--device", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.device:
        print(json.dumps(device_run(args.desktop_silence), indent=2))
        return 0
    root = Path(__file__).resolve().parents[1]
    remote = [str(root / "scripts/fuxi-ssh.sh"), "python3 - --device"]
    if args.desktop_silence:
        remote[-1] += " --desktop-silence"
    response = subprocess.run(remote, input=Path(__file__).read_text(), text=True,
                              capture_output=True, timeout=70)
    if response.returncode:
        sys.stderr.write(response.stderr + response.stdout)
        return response.returncode
    result = json.loads(response.stdout)
    logdir = root / "work/claude-logs"
    logdir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S-%fZ")
    logfile = logdir / f"audio-diagnose-{stamp}.json"
    logfile.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Evidence: {logfile}")
    for check in result["checks"]:
        print(f"{'PASS' if check['passed'] else 'FAIL'} {check['check']}")
    print("Silent diagnostics do not assess audibility; see the recorded listening results.")
    return int(any(not check["passed"] for check in result["checks"]))


if __name__ == "__main__":
    sys.exit(main())
