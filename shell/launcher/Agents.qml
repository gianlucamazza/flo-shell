import QtQuick
import Quickshell
import Quickshell.Io

// Remote-agent launcher entries. The companion CLI (`flo-agents`, from
// nexus7-flo-linux) owns SSH/mosh and the config file; this object only
// lists tools / onboarding rows and starts `flo-agent-session` or the
// settings panel.
//
// The list is read once when refresh() is called (launcher open). No
// timer, no background process: the Process below is idle except during
// that one-shot read. Extra memory is a handful of JS objects.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // [{ id, name, tool, isAgent, isSettings, icon, genericName, keywords }]
    property var tools: []

    function refresh(): void {
        if (proc.running)
            return;
        proc.running = true;
    }

    function matching(query: string): var {
        const q = query.trim().toLowerCase();
        const src = tools;
        const out = [];
        for (let i = 0; i < src.length; i++) {
            const e = src[i];
            if (q === "") {
                out.push(e);
                continue;
            }
            const hay = (e.name + " " + e.tool + " " + e.keywords.join(" ")).toLowerCase();
            if (hay.indexOf(q) >= 0)
                out.push(e);
        }
        return out;
    }

    function launch(tool: string): void {
        Quickshell.execDetached(["flo-agent-session", "launch", tool]);
    }

    function _apply(text: string): void {
        const out = [];
        const lines = (text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line === "")
                continue;
            const parts = line.split("\t");
            if (parts.length < 2)
                continue;
            const id = parts[0];
            const name = parts[1];
            const kind = parts.length > 2 ? parts[2] : "launch";
            if (id === "" || name === "")
                continue;
            if (kind === "settings") {
                out.push({
                    id: "flo-agent-settings",
                    name: name,
                    tool: "",
                    isAgent: true,
                    isSettings: true,
                    icon: "",
                    genericName: "agent settings",
                    keywords: ["agent", "settings", "configure"]
                });
                continue;
            }
            const local = id === "crush";
            out.push({
                id: "flo-agent-" + id,
                name: name,
                tool: id,
                isAgent: true,
                isSettings: false,
                icon: "",
                genericName: local ? "local agent" : "remote agent",
                keywords: local ? ["agent", "local", "crush"] : ["agent", "remote", id]
            });
        }
        tools = out;
    }

    Process {
        id: proc
        // Missing helper → empty list, exit 0, no log line.
        command: ["sh", "-c", "command -v flo-agent-config >/dev/null 2>&1 && exec flo-agent-config entries || true"]
        stdout: StdioCollector {
            onStreamFinished: root._apply(text)
        }
        onExited: code => {
            if (code !== 0)
                root.tools = [];
        }
    }
}
