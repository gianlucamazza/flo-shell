pragma Singleton

import QtQuick
import Quickshell

// Application index. Quickshell parses the .desktop files once and updates
// the model on change; the sorted list below is recomputed only then.
Singleton {
    id: root

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

    function launch(entry: DesktopEntry): void {
        entry.execute();
    }
}
