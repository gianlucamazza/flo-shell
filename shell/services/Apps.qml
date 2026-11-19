pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Application index. Quickshell parses the .desktop files once and updates
// the model on change; the sorted list below is recomputed only then.
Singleton {
    id: root

    signal launchRequested(string name)
    readonly property var shortcuts: {
        const wanted = (Quickshell.env("FLO_FAVORITES") || "org.gnome.Epiphany,org.gnome.Nautilus,org.gnome.Settings,org.gnome.TextEditor").split(",");
        const found = [];
        for (const id of wanted) {
            const entry = all.find(e => e.id === id.trim());
            if (entry && !found.includes(entry)) found.push(entry);
        }
        return found.length > 0 ? found : all.slice(0, 4);
    }

    // Desktop entries that make no sense on the tablet: input-method setup
    // (the shell drives the on-screen keyboard) and parental controls.
    readonly property var hiddenIds: ["org.freedesktop.IBus.Setup", "org.freedesktop.MalcontentControl"]

    readonly property var all: {
        const out = [];
        const src = DesktopEntries.applications.values;
        for (let i = 0; i < src.length; i++) {
            const e = src[i];
            // Terminal-only entries are useless without a keyboard.
            if (!e.noDisplay && !e.runInTerminal && e.name !== "" && !root.hiddenIds.includes(e.id))
                out.push(e);
        }
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }

    function search(query: string): var {
        const q = query.trim().toLowerCase();
        if (q === "")
            return all;
        const starts = [];
        const contains = [];
        for (let i = 0; i < all.length; i++) {
            const e = all[i];
            const name = e.name.toLowerCase();
            if (name.startsWith(q))
                starts.push(e);
            else if (name.includes(q) || e.genericName.toLowerCase().includes(q) || e.keywords.join(" ").toLowerCase().includes(q))
                contains.push(e);
        }
        return starts.concat(contains);
    }

    function iconSource(entry: DesktopEntry): string {
        const icon = entry.icon;
        if (icon === "")
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, true);
    }

    // ---- Launching -------------------------------------------------------
    // Every app runs in its own transient systemd user scope,
    // app-<desktop id>-<random>.scope in app.slice, so that flo-sessiond
    // can freeze it in the background (docs/SESSIOND.md). Without systemd
    // (no systemd-run or no user manager) entry.execute() is used.
    // FLO_APP_SCOPE=0 forces the plain launch.
    // The probe starts with this singleton (first launcher use); launches
    // asked for before it answers wait for it.
    property bool scoped: false
    property bool _probed: (Quickshell.env("FLO_APP_SCOPE") || "") === "0"
    property var _queued: []

    Process {
        running: !root._probed
        command: ["sh", "-c", "command -v systemd-run > /dev/null && systemctl --user show -p Version --value > /dev/null 2>&1"]
        onExited: code => {
            root.scoped = code === 0;
            root._probed = true;
            console.info("flo-apps: " + (root.scoped ? "launching apps in systemd user scopes" : "no systemd user manager, plain launch"));
            const q = root._queued;
            root._queued = [];
            for (let i = 0; i < q.length; i++)
                root._launchReady(q[i]);
        }
    }

    // Unit name escaping as systemd does it (systemd-escape): keep
    // [A-Za-z0-9:_.], everything else, "-" included, becomes \xHH per
    // UTF-8 byte, so the daemon can decode the desktop id back.
    function unitEscape(id: string): string {
        let out = "";
        const enc = encodeURIComponent(id);
        for (let i = 0; i < enc.length; i++) {
            let c = enc.charCodeAt(i);
            if (enc.charAt(i) === "%") {
                c = parseInt(enc.substr(i + 1, 2), 16);
                i += 2;
            }
            const ch = String.fromCharCode(c);
            if (c < 128 && /[A-Za-z0-9:_.]/.test(ch))
                out += ch;
            else
                out += "\\x" + (c < 16 ? "0" : "") + c.toString(16);
        }
        return out.slice(0, 200);
    }
    function scopeUnit(entry: DesktopEntry): string {
        const rnd = Math.floor(Math.random() * 0x100000000).toString(16);
        return "app-" + unitEscape(entry.id) + "-" + "00000000".slice(rnd.length) + rnd;
    }

    // By desktop id (IPC). Quickshell reads the .desktop files in the
    // background on first use, so a request that comes before the index
    // waits for it.
    property var _queuedIds: []
    function launchById(id: string): string {
        const entry = DesktopEntries.byId(id);
        if (entry) {
            launch(entry);
            return "ok";
        }
        if (DesktopEntries.applications.values.length > 0)
            return "not found";
        _queuedIds.push(id);
        return "queued";
    }
    onAllChanged: {
        if (_queuedIds.length === 0 || DesktopEntries.applications.values.length === 0)
            return;
        const ids = _queuedIds;
        _queuedIds = [];
        for (let i = 0; i < ids.length; i++) {
            const entry = DesktopEntries.byId(ids[i]);
            if (entry)
                launch(entry);
            else
                console.warn("flo-apps: no desktop entry " + ids[i]);
        }
    }

    function launch(entry: DesktopEntry): void {
        if (!entry)
            return;
        // Reuse a running app before creating a scope. A single-instance
        // app cannot answer a new activation while its old scope is frozen.
        const id = entry.id.replace(/\.desktop$/, "").toLowerCase();
        const existing = Compositor.windows.find(w => Compositor.windowAppId(w).replace(/\.desktop$/, "").toLowerCase() === id);
        if (existing) {
            Ui.closeAll();
            Compositor.focusWindow(existing);
            return;
        }
        root.launchRequested(entry.name);
        if (!_probed) {
            _queued.push(entry);
            return;
        }
        _launchReady(entry);
    }
    function _launchReady(entry: DesktopEntry): void {
        if (scoped) {
            _launchQueue.push(entry);
            _probeLaunch();
        } else {
            _startEntry(entry);
        }
    }

    // A startup cancelled with Home can be frozen before its first window.
    // Reuse and thaw that scope before forwarding single-instance activation.
    property var _launchQueue: []
    property var _launchJob: null
    function _probeLaunch(): void {
        if (scopeProbe.running || _launchJob || _launchQueue.length === 0) return;
        _launchJob = _launchQueue.shift();
        const pattern = "app-" + unitEscape(_launchJob.id).replace(/\\/g, "\\\\") + "-*.scope";
        scopeProbe.command = ["systemctl", "--user", "list-units", "--state=active", "--no-legend", "--plain", "--full", pattern];
        scopeProbe.running = true;
    }
    function _launchProbeDone(text: string): void {
        const entry = _launchJob;
        _launchJob = null;
        if (!entry) return;
        const unit = text.trim().split(/\s+/)[0] || "";
        if (unit.startsWith("app-") && unit.endsWith(".scope")) {
            Sessiond.launching(unit);
            entry.execute();
        } else {
            _startEntry(entry);
        }
        _probeLaunch();
    }
    Process {
        id: scopeProbe
        stdout: StdioCollector { onStreamFinished: root._launchProbeDone(text) }
        stderr: StdioCollector {}
        onRunningChanged: root._probeLaunch()
    }
    function _startEntry(entry: DesktopEntry): void {
        const unit = scoped ? scopeUnit(entry) : "";
        Sessiond.launching(unit === "" ? "" : unit + ".scope");
        const cmd = [];
        const src = entry.command;
        for (let i = 0; src && i < src.length; i++)
            cmd.push(src[i]);
        if (!scoped || cmd.length === 0) {
            entry.execute();
            return;
        }
        // Same as DesktopEntry.execute() (command and working directory,
        // the shell's environment), with systemd-run in front: with --scope
        // it execs the command itself, so nothing else changes for the app.
        const ctx = {
            command: ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--unit=" + unit, "--"].concat(cmd)
        };
        if (entry.workingDirectory !== "")
            ctx.workingDirectory = entry.workingDirectory;
        Quickshell.execDetached(ctx);
    }
}
