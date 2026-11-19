#!/usr/bin/env python3
"""A new Wayland window must dismiss the shell's full-screen quick settings."""
import json
from pathlib import Path
import subprocess
import time


shell = Path(__file__).resolve().parents[1] / "shell"
command = ["quickshell", "ipc", "-p", str(shell), "call", "flo"]


def call(*args):
    return subprocess.check_output(command + list(args), text=True).strip()


def state():
    return json.loads(call("state"))


def wait_windows(count):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if state()["windows"] == count:
            return
        time.sleep(0.1)
    raise AssertionError(f"expected {count} windows, got {state()['windows']}")


assert state()["windows"] == 0, "run in an empty nested shell"
first = subprocess.Popen(["foot", "--app-id=flo-dialog-base", "sh", "-c", "sleep 120"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
second = None
try:
    wait_windows(1)
    call("activateWindow", "0")
    call("quickSettings")
    assert state()["quickSettings"] is True
    second = subprocess.Popen(["foot", "--app-id=flo-dialog-popup", "sh", "-c", "sleep 120"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_windows(2)
    assert state()["quickSettings"] is False, "new window remains behind quick settings"
finally:
    if second:
        second.terminate()
        second.wait(timeout=5)
    first.terminate()
    first.wait(timeout=5)
