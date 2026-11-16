#!/usr/bin/env python3
"""Check real shell navigation in the isolated instance from run-nested.sh."""
import argparse
import json
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument("--path", default=str(Path(__file__).resolve().parents[1] / "shell"))
a = p.parse_args()
base = ["quickshell", "ipc", "-p", str(Path(a.path).resolve()), "call", "flo"]


def call(*args):
    # A development edit triggers Quickshell's asynchronous reload.
    deadline = time.monotonic() + 10
    while True:
        out = subprocess.check_output(base + list(args), text=True).strip()
        if not out.startswith("Not ready to accept queries"):
            return out
        if time.monotonic() >= deadline:
            raise RuntimeError("Quickshell did not finish reloading")
        time.sleep(.1)


def state():
    return json.loads(call("state"))


call("home")
assert state().get("home") is True, "Home must show a real home surface"
call("home")
assert state()["home"] is True, "Home must be idempotent"
call("launcher")
assert state()["launcher"] is True
call("back")
assert state()["launcher"] is False and state()["home"] is True
call("quickSettings")
assert state()["quickSettings"] is True
call("back")
assert state()["quickSettings"] is False and state()["home"] is True
call("powerMenu")
assert state()["powerMenu"] is True
call("home")
s = state()
assert s["home"] and not s["powerMenu"] and not s["launcher"]
call("textSize", "1.5")
assert state()["textScale"] == 1.5
for angle in (90, 180, 270, 0):
    call("rotate", str(angle))
    end = time.monotonic() + 4
    while state()["rotation"] != angle and time.monotonic() < end:
        time.sleep(.1)
    assert state()["rotation"] == angle
    assert state()["home"] is True
call("textSize", "1")
# A real client proves Home keeps the application, and restoring the same
# focused client dismisses Home even if activeWindow does not change.
client = subprocess.Popen(["foot", "--app-id=flo-ui-test", "sh", "-c", "sleep 120"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    end = time.monotonic() + 8
    while (state()["windows"] == 0 or state()["home"]) and time.monotonic() < end:
        time.sleep(.1)
    assert state()["windows"] == 1, "Run this test with no other nested clients"
    assert state()["home"] is False
    call("home")
    assert state()["home"] and state()["windows"] == 1
    call("activateWindow", "0")
    assert state()["home"] is False
    call("closeWindow", "0")
    end = time.monotonic() + 4
    while state()["windows"] and time.monotonic() < end:
        time.sleep(.1)
    assert state()["windows"] == 0 and state()["home"]
finally:
    client.terminate()
    client.wait(timeout=5)
    call("textSize", "1")
print("PASS: stable Home, panels, Back, text scale, rotations and real app restore")
