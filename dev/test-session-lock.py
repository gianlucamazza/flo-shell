#!/usr/bin/env python3
"""Real Session.qml must wait for lock acknowledgement before powering off."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1] / 'shell/services/Session.qml'
with tempfile.TemporaryDirectory(prefix='flo-lock-') as temp:
    root = Path(temp)
    services = root / 'services'
    services.mkdir()
    (services / 'Session.qml').symlink_to(SOURCE)
    (services / 'Compositor.qml').write_text('''pragma Singleton
import Quickshell
Singleton {
    property var calls: []
    function setDisplayPower(on: bool): void { calls = calls.concat([on]); }
}
''')
    (root / 'shell.qml').write_text('''import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    IpcHandler {
        target: "test"
        function state(): string { return JSON.stringify({locked: Session.locked, displayOn: Session.displayOn, calls: Compositor.calls, suspendPending: Session._suspendPending}); }
        function blank(): void { Session.lock(); Session.setDisplay(false); }
        function confirm(): void { Session.lockSecure = true; }
        function wake(): void { Session.setDisplay(true); }
        function unlock(): void { Session.unlock(); Session.lockSecure = false; }
        function suspend(): void { Session.suspend(); }
    }
}
''')
    bindir = root / 'bin'
    bindir.mkdir()
    remover = bindir / 'rm'
    remover.write_text('#!/bin/sh\nsleep 0.3\nexec /usr/bin/rm "$@"\n')
    remover.chmod(0o755)
    fake_busctl = bindir / 'busctl'
    fake_busctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$FLO_TEST_LOGIND_LOG"\n')
    fake_busctl.chmod(0o755)
    logind_log = root / 'logind'
    logind_log.touch()
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QSG_RHI_BACKEND='software',
               FLO_STATE_DIR=str(root / 'state'), FLO_TEST_LOGIND_LOG=str(logind_log),
               PATH=str(bindir) + ':' + os.environ['PATH'])
    (root / 'state').mkdir()
    log = (root / 'log').open('w+')
    proc = subprocess.Popen(['dbus-run-session', '--config-file=' + str(SOURCE.parents[2] / 'dev/dbus-session.conf'),
                             '--', 'quickshell', '-p', str(root)], env=env, stdout=log,
                            stderr=log, start_new_session=True)
    base = ['quickshell', 'ipc', '-p', str(root), 'call', 'test']
    def call(*args):
        return subprocess.check_output(base + list(args), env=env, text=True, stderr=subprocess.DEVNULL).strip()
    def state():
        return json.loads(call('state'))
    try:
        end = time.monotonic() + 6
        while True:
            try:
                if state()['displayOn']:
                    break
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            if time.monotonic() > end:
                raise AssertionError('Session did not load: ' + (root / 'log').read_text()[-1500:])
            time.sleep(.025)
        call('blank')
        s = state()
        assert s['locked'] and s['displayOn'] and not s['calls'], 'display turned off before compositor confirmed the lock'
        call('confirm')
        s = state()
        assert s['locked'] and not s['displayOn'] and s['calls'] == [False], 'confirmed lock did not apply pending blank'
        call('wake')
        assert state()['locked'] and state()['displayOn'], 'wake must preserve authentication requirement'
        call('unlock')
        call('blank')
        call('wake')
        before = state()['calls']
        call('confirm')
        assert state()['displayOn'] and state()['calls'] == before, 'late acknowledgement overrode a newer wake request'
        # An old asynchronous cleaner must never remove a newer lock marker.
        call('unlock')
        call('blank')
        time.sleep(.5)
        marker = root / 'state/flo-shell.locked'
        assert marker.exists() and marker.read_text().strip() == 'locked', 'unlock cleanup removed a newer lock marker'
        call('unlock')
        # Suspend may only start after the compositor confirms the lock.
        before_suspend = logind_log.read_text().count('Suspend')
        call('suspend')
        assert state()['locked'] and state()['suspendPending'], 'suspend was not held for the secure lock'
        assert logind_log.read_text().count('Suspend') == before_suspend, 'suspend started before the lock acknowledgement'
        call('suspend')
        call('confirm')
        end = time.monotonic() + 2
        while logind_log.read_text().count('Suspend') == before_suspend:
            assert time.monotonic() < end, 'confirmed lock did not start suspend'
            time.sleep(.025)
        assert logind_log.read_text().count('Suspend') == before_suspend + 1, 'duplicate suspend request'
        assert not state()['suspendPending'], 'suspend remained pending after dispatch'
        call('unlock')
        call('suspend')
        call('unlock')
        assert not state()['suspendPending'], 'unlock did not cancel the pending suspend'
        call('confirm')
        # _logind launches an asynchronous Process, so give a late dispatch
        # time to reach the fake busctl before checking the absence of a call.
        time.sleep(.5)
        assert logind_log.read_text().count('Suspend') == before_suspend + 1, 'cancelled suspend started after a late acknowledgement'
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
        proc = subprocess.Popen(['dbus-run-session', '--config-file=' + str(SOURCE.parents[2] / 'dev/dbus-session.conf'),
                                 '--', 'quickshell', '-p', str(root)], env=env, stdout=log,
                                stderr=log, start_new_session=True)
        end = time.monotonic() + 6
        while True:
            try:
                s = state()
                if s.get('displayOn'):
                    break
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            assert time.monotonic() < end, 'Session did not restart'
            time.sleep(.025)
        time.sleep(.1)
        assert not state()['locked'], 'an empty unlock marker relocked a restarted shell'
        call('blank')
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
        proc = subprocess.Popen(['dbus-run-session', '--config-file=' + str(SOURCE.parents[2] / 'dev/dbus-session.conf'),
                                 '--', 'quickshell', '-p', str(root)], env=env, stdout=log,
                                stderr=log, start_new_session=True)
        end = time.monotonic() + 6
        while True:
            try:
                if state()['locked']:
                    break
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            assert time.monotonic() < end, 'restart lost the active lock marker'
            time.sleep(.025)
        print('session lock: acknowledgement, pending blank, wake, marker ordering and restart passed')
    finally:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
        log.close()
