#!/usr/bin/env python3
"""Exercise the real overview and focus path in dev/run-nested.sh."""

import json
from pathlib import Path
import subprocess
import time


shell = Path(__file__).resolve().parents[1] / "shell"
ipc = ["quickshell", "ipc", "-p", str(shell), "call", "flo"]


def call(*args: str) -> str:
    return subprocess.check_output(ipc + list(args), text=True).strip()


def state() -> dict:
    return json.loads(call("state"))


def active_class() -> str:
    return json.loads(subprocess.check_output(["hyprctl", "-j", "activewindow"], text=True)).get("class", "")


call("home")
clients = [
    subprocess.Popen(["foot", f"--app-id=flo-switch-test-{n}", "sh", "-c", "sleep 60"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for n in (0, 1)
]
try:
    deadline = time.monotonic() + 8
    while state()["windows"] != 2 and time.monotonic() < deadline:
        time.sleep(.1)
    assert state()["windows"] == 2

    seen = set()
    for index in (0, 1):
        call("overview")
        assert state()["overview"] is True
        call("activateWindow", str(index))
        assert state()["overview"] is False and state()["home"] is False
        seen.add(active_class())
    assert seen == {"flo-switch-test-0", "flo-switch-test-1"}, seen
finally:
    call("home")
    for client in clients:
        client.terminate()
        client.wait(timeout=5)

print("PASS: two apps open, both can be selected from the overview")
