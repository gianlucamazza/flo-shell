import QtQuick
import Quickshell
import Quickshell.Io

// Remote-agent launcher entries. The companion CLI (`flo-agents`, from
// nexus7-flo-linux) owns SSH/mosh; this object only lists configured
// tools and starts `flo-agent-session` in the session terminal.
//
// The list is read once when refresh() is called (launcher open). No
// timer, no background process: the Process below is idle except during
// that one-shot read. Extra memory is a handful of JS objects.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // [{ id, name, tool, isAgent, icon, genericName, keywords }]
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
            const tab = line.indexOf("\t");
            if (tab <= 0)
                continue;
            const id = line.slice(0, tab);
            const name = line.slice(tab + 1);
            if (id === "" || name === "")
                continue;
            out.push({
                id: "flo-agent-" + id,
                name: name,
                tool: id,
                isAgent: true,
                icon: "",
                genericName: "remote agent",
                keywords: ["agent", "remote", id]
            });
        }
        tools = out;
    }

    Process {
        id: proc
        // Missing helper → empty list, exit 0, no log line.
        command: ["sh", "-c", "command -v flo-agent-session >/dev/null 2>&1 && exec flo-agent-session list || true"]
        stdout: StdioCollector {
            onStreamFinished: root._apply(text)
        }
        onExited: code => {
            if (code !== 0)
                root.tools = [];
        }
    }
}
