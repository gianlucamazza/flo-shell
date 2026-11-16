pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Client of flo-sessiond (docs/SESSIOND.md): the shell owns the background
// app freezer policy and tells the daemon which app is in the foreground.
//
// - On connect: `freeze-policy on`, then the lock state and the foreground.
// - Focused window changes: `foreground <unit>`, where <unit> is the app
//   scope (relative to app.slice) of the focused window's process, or `-`
//   when no app window has the focus. Apps get their own scope from
//   Apps.launch() (systemd-run --scope).
// - Session lock: `lock on` / `lock off` (the daemon thaws everything while
//   locked).
// - Closing a window: `thaw <unit>` first (Compositor.beforeClose), so a
//   frozen app can handle the close request.
// - Connection lost (daemon restarted): reconnect with backoff; the daemon
//   thaws everything as soon as the owner goes away.
// - No daemon: a few attempts with backoff, one log line, then nothing until
//   the next app launch or unlock. No error spam, no periodic timer.
//
// FLO_SESSIOND_SOCKET overrides the socket path (same variable as floctl);
// FLO_SESSIOND=0 disables the client.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("FLO_SESSIOND_SOCKET") || "/run/flo-sessiond.sock"
    readonly property bool enabled: (Quickshell.env("FLO_SESSIOND") || "") !== "0"

    // True once the socket is open.
    readonly property bool connected: sock.connected
    // True while this shell owns the freeze policy.
    property bool policy: false
    // Unit last sent with `foreground` ("" = none, sent as "-").
    property string foregroundUnit: ""

    // ---- Connection ------------------------------------------------------
    readonly property int maxAttempts: 8
    property int _attempts: 0
    property bool _gaveUp: false
    property bool _announcedFailure: false
    // Callbacks of the commands sent, in order: one OK/ERR line each.
    property var _pending: []

    function start(): void {
        if (!enabled || sock.connected || retry.running || probe.running)
            return;
        _gaveUp = false;
        _connect();
    }

    // Event-driven retry hint (app launch, unlock) after giving up.
    function poke(): void {
        if (enabled && _gaveUp && !sock.connected && !retry.running && !probe.running) {
            _attempts = 0;
            _gaveUp = false;
            _connect();
        }
    }

    // Quickshell's Socket logs a warning for every failed connection, so
    // the socket file is looked for first: a missing daemon costs one
    // `test -S` per attempt and no log line.
    function _connect(): void {
        retry.stop();
        if (!sock.connected && !probe.running)
            probe.running = true;
    }
    Process {
        id: probe
        command: ["test", "-S", root.socketPath]
        onExited: code => {
            if (code === 0)
                sock.connected = true;
            else
                root._scheduleRetry("no socket");
        }
    }

    function _scheduleRetry(reason: string): void {
        if (sock.connected || retry.running || _gaveUp)
            return;
        _attempts++;
        if (_attempts > maxAttempts) {
            _gaveUp = true;
            if (!_announcedFailure)
                console.info("flo-sessiond: not available at " + socketPath + " (" + reason + "), freezer integration idle");
            _announcedFailure = true;
            return;
        }
        retry.interval = Math.min(64, 1 << (_attempts - 1)) * 1000;
        retry.start();
    }

    function _onConnected(): void {
        retry.stop();
        _pending = [];
        console.info("flo-sessiond: connected to " + socketPath);
        // Without window pids (wlr backend) the foreground app is unknown:
        // taking the policy would freeze the visible app. Thaw and boost
        // still work.
        if (!Compositor.supportsWindowPid) {
            console.info("flo-sessiond: the compositor backend gives no window pids, freezer policy not taken");
            return;
        }
        _send("freeze-policy on", (ok, line) => {
            if (!ok) {
                console.info("flo-sessiond: freeze-policy refused: " + line);
                // busy: another client owns the policy (floctl -i in a
                // test): try again later, with the same bounded backoff.
                // disabled (freezer_enabled = no): keep the connection for
                // thaw and boost, without driving the policy.
                if (line.startsWith("ERR busy"))
                    sock.connected = false;
                return;
            }
            root._attempts = 0;
            root._announcedFailure = false;
            root.policy = true;
            if (Session.locked)
                _send("lock on");
            root.foregroundUnit = "";
            root._sentForeground = null;
            root.updateForeground();
        });
    }

    function _onDisconnected(): void {
        const pending = _pending;
        _pending = [];
        policy = false;
        foregroundUnit = "";
        _sentForeground = null;
        for (let i = 0; i < pending.length; i++)
            if (pending[i])
                pending[i](false, "ERR disconnected");
        if (enabled)
            _scheduleRetry("disconnected");
    }

    // One command line; cb(ok, line) gets the final reply line.
    function _send(line: string, cb: var): void {
        if (!sock.connected) {
            if (cb)
                cb(false, "ERR not-connected");
            return;
        }
        _pending.push(cb || null);
        sock.write(line + "\n");
        sock.flush();
    }

    function _onLine(line: string): void {
        // Data lines (only `status` has them) are not used here.
        if (!line.startsWith("OK") && !line.startsWith("ERR"))
            return;
        const cb = _pending.shift();
        // Commands sent without a callback have nobody else to report to.
        if (!cb && !line.startsWith("OK"))
            console.info("flo-sessiond: " + line);
        if (cb)
            cb(line.startsWith("OK"), line);
    }

    Socket {
        id: sock

        path: root.socketPath
        parser: SplitParser {
            onRead: data => root._onLine(data)
        }
        onConnectionStateChanged: {
            if (connected)
                root._onConnected();
            else
                root._onDisconnected();
        }
        // QLocalSocket::LocalSocketError: 0 refused, 2 not found, 3 access.
        onError: error => {
            if (!connected)
                root._scheduleRetry(error === 2 ? "no socket" : error === 3 ? "permission denied" : error === 0 ? "connection refused" : "error " + error);
        }
    }
    Timer {
        id: retry
        repeat: false
        onTriggered: root._connect()
    }

    // ---- Units -----------------------------------------------------------
    // App unit (first path component below app.slice) of a process, from
    // /proc/<pid>/cgroup (cgroup v2: "0::/user.slice/.../app.slice/<unit>").
    function _unitFromCgroup(text: string): string {
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            if (!lines[i].startsWith("0::"))
                continue;
            const path = lines[i].slice(3);
            const at = path.indexOf("/app.slice/");
            if (at < 0)
                return "";
            return path.slice(at + 11).split("/")[0];
        }
        return "";
    }

    property var _cgQueue: []
    property var _cgCurrent: null
    function unitOfPid(pid: int, cb: var): void {
        if (pid <= 0) {
            cb("");
            return;
        }
        _cgQueue.push({ pid: pid, cb: cb });
        _cgNext();
    }
    function _cgNext(): void {
        if (cgRead.running || _cgCurrent || _cgQueue.length === 0)
            return;
        _cgCurrent = _cgQueue.shift();
        cgRead.command = ["cat", "/proc/" + _cgCurrent.pid + "/cgroup"];
        cgRead.running = true;
    }
    function _cgDone(text: string): void {
        const job = _cgCurrent;
        _cgCurrent = null;
        if (job)
            job.cb(_unitFromCgroup(text));
        _cgNext();
    }
    Process {
        id: cgRead
        stdout: StdioCollector {
            onStreamFinished: root._cgDone(text)
        }
        stderr: StdioCollector {}
        onRunningChanged: root._cgNext()
    }

    // Unit of a window: "" if it is not in an app scope, null if the
    // lookup failed (window gone, no pid).
    function unitOfWindow(w: var, cb: var): void {
        if (!w) {
            cb("");
            return;
        }
        Compositor.windowPid(w, pid => {
            if (pid <= 0)
                cb(null);
            else
                root.unitOfPid(pid, cb);
        });
    }

    // ---- Foreground ------------------------------------------------------
    property var _sentForeground: null
    property int _fgSeq: 0
    function updateForeground(): void {
        if (!policy)
            return;
        const seq = ++_fgSeq;
        unitOfWindow(Compositor.activeWindow, unit => {
            // A failed lookup keeps the previous foreground: sending "-"
            // would freeze the app that is still on screen.
            if (unit === null || seq !== root._fgSeq || !root.policy || unit === root._sentForeground)
                return;
            root._sentForeground = unit;
            root._send("foreground " + (unit === "" ? "-" : unit), ok => {
                if (ok && seq === root._fgSeq)
                    root.foregroundUnit = unit;
            });
        });
    }

    Connections {
        target: Compositor
        function onActiveWindowChanged(): void {
            root.updateForeground();
        }
    }
    Connections {
        target: Session
        function onLockedChanged(): void {
            if (root.policy)
                root._send(Session.locked ? "lock on" : "lock off");
            if (!Session.locked)
                root.poke();
        }
    }

    // ---- Hooks for the rest of the shell ---------------------------------
    // App launch: short CPU boost for the start-up, and a chance to connect.
    function launching(): void {
        poke();
        if (sock.connected)
            _send("boost 500", () => {}); // ERR disabled is fine
    }

    // Installed as Compositor.beforeClose: thaw the window's app before the
    // close request, so a frozen app can answer it. done() runs exactly
    // once; closeGuard closes anyway if the lookup or the reply stalls.
    function beforeClose(w: var, done: var): void {
        if (!sock.connected) {
            done();
            return;
        }
        let called = false;
        const finish = () => {
            if (called)
                return;
            called = true;
            done();
        };
        closeGuard.pending.push(finish);
        closeGuard.restart();
        unitOfWindow(w, unit => {
            if (!unit)
                finish();
            else
                root._send("thaw " + unit, () => finish());
        });
    }
    Timer {
        id: closeGuard
        property var pending: []
        interval: 1000
        onTriggered: {
            const p = pending;
            pending = [];
            for (let i = 0; i < p.length; i++)
                p[i]();
        }
    }

    Component.onCompleted: Compositor.beforeClose = root.beforeClose
}
