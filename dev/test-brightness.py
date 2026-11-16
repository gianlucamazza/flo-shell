#!/usr/bin/env python3
"""Exercise the real QML service with a backlight file and controlled writer."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1] / 'shell/services/Brightness.qml'

with tempfile.TemporaryDirectory(prefix='flo-brightness-') as temp:
    root = Path(temp)
    services = root / 'services'
    services.mkdir()
    (services / 'Brightness.qml').symlink_to(SOURCE)
    (root / 'shell.qml').write_text('''import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    IpcHandler {
        target: "test"
        function state(): string { return JSON.stringify({raw: Brightness.raw, available: Brightness.available, primed: Brightness._primed}); }
        function set(v: real): void { Brightness.set(v); }
        function select(logind: bool, cli: bool): string {
            return typeof Brightness._selectMethod === "function" ? Brightness._selectMethod(logind, cli) : "missing";
        }
    }
}
''')
    backlight = root / 'backlight'
    backlight.mkdir()
    (backlight / 'brightness').write_text('40\n')
    (backlight / 'max_brightness').write_text('255\n')
    bindir = root / 'bin'
    bindir.mkdir()
    wrapper = bindir / 'sh'
    wrapper.write_text('''#!/bin/sh
case "$2" in
  printf*)
    [ ! -e "${0%/*}/../fail" ] || exit 1
    /bin/sh "$@"
    [ ! -e "${0%/*}/../delay" ] || sleep 0.2
    ;;
  *) exec /bin/sh "$@" ;;
esac
''')
    wrapper.chmod(0o755)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QSG_RHI_BACKEND='software',
               FLO_BACKLIGHT_DIR=str(backlight), PATH=str(bindir) + ':' + os.environ['PATH'])
    log = (root / 'log').open('w+')
    process = subprocess.Popen(['dbus-run-session', '--config-file=' + str(SOURCE.parents[2] / 'dev/dbus-session.conf'), '--', 'quickshell', '-p', str(root)],
                               env=env, stdout=log, stderr=log, start_new_session=True)
    base = ['quickshell', 'ipc', '-p', str(root), 'call', 'test']

    def call(*args):
        return subprocess.check_output(base + list(args), env=env, text=True, stderr=subprocess.DEVNULL).strip()

    def state():
        return json.loads(call('state'))

    def wait_for(predicate, message):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(0.025)
        log.flush()
        raise AssertionError(message + '\n' + (root / 'log').read_text()[-2000:])

    try:
        wait_for(lambda: state()['primed'], 'initial brightness did not load')
        # Reject a denied write visually, too: optimistic UI must roll back.
        (root / 'fail').touch()
        call('set', '0.8')
        wait_for(lambda: state()['raw'] == 40, 'failed write left a false brightness in the UI')
        assert (backlight / 'brightness').read_text().strip() == '40'
        (root / 'fail').unlink()
        # Hold first writer after its write: a file event must not replace a newer intent.
        (root / 'delay').touch()
        call('set', '0.4')
        call('set', '0.8')
        time.sleep(0.07)
        assert state()['raw'] == 204, 'an older file event replaced the latest pending brightness'
        wait_for(lambda: (backlight / 'brightness').read_text().strip() == '204' and state()['raw'] == 204,
                 'latest queued value did not reach hardware and UI')
        for logind, cli, expected in [('true', 'true', 'logind'), ('true', 'false', 'logind'),
                                      ('false', 'true', 'brightnessctl'), ('false', 'false', '')]:
            assert call('select', logind, cli) == expected, 'wrong backend priority/capability detection'
        print('brightness: denied write, queued updates and backend selection passed')
    finally:
        import signal
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
        log.close()
