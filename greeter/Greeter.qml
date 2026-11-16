import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.components
import qs.lock

// Login screen: clock, user choice, session choice and the same pad as the
// lock screen. Opaque full-screen layer surface in the greeter compositor.
PanelWindow {
    id: win

    // ---- Users -----------------------------------------------------------
    readonly property string forcedUsers: Quickshell.env("FLO_GREETER_USERS") || ""
    readonly property var users: forcedUsers !== "" ? forcedUsers.split(",") : passwdUsers
    property var passwdUsers: []
    property string user: ""

    function selectUser(name: string): void {
        if (users.indexOf(name) < 0 || auth.busy)
            return;
        user = name;
        pad.clear();
        auth.clearStatus();
    }
    onUsersChanged: {
        if (users.indexOf(user) >= 0)
            return;
        const wanted = Quickshell.env("FLO_GREETER_USER") || "";
        user = users.indexOf(wanted) >= 0 ? wanted : users.length > 0 ? users[0] : "";
    }

    // Regular accounts: uid 1000..59999 with a login shell.
    function parsePasswd(text: string): var {
        const out = [];
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const f = lines[i].split(":");
            if (f.length < 7)
                continue;
            const uid = parseInt(f[2]);
            if (uid >= 1000 && uid < 60000 && !/(nologin|false)$/.test(f[6]))
                out.push(f[0]);
        }
        return out;
    }
    FileView {
        path: win.forcedUsers === "" ? "/etc/passwd" : ""
        printErrors: false
        onLoaded: win.passwdUsers = win.parsePasswd(text())
    }

    // ---- Sessions --------------------------------------------------------
    readonly property string defaultSession: Quickshell.env("FLO_GREETER_SESSION") || "flo-session"
    // Session files offered, by basename without ".desktop": only the
    // flo-shell session by default, so the stock hyprland.desktop and
    // hyprland-uwsm.desktop of the Hyprland package stay out of the way.
    // FLO_GREETER_SESSIONS=a,b replaces the list, "*" offers every file.
    readonly property var allowedSessions: (Quickshell.env("FLO_GREETER_SESSIONS") || "flo-shell").split(",").map(s => s.trim()).filter(s => s !== "")
    function sessionAllowed(id: string): bool {
        return allowedSessions.indexOf("*") >= 0 || allowedSessions.indexOf(id) >= 0;
    }
    // [{ id, name, exec }] from the wayland-sessions directory.
    property var sessions: []
    property int sessionIndex: 0
    readonly property string sessionCommand: sessions.length > 0 && sessionIndex >= 0 && sessionIndex < sessions.length ? sessions[sessionIndex].exec : defaultSession

    // One line per session file: basename, Name, Exec. Files with
    // Hidden=true or NoDisplay=true are skipped (desktop entry spec).
    Process {
        command: ["sh", "-c", "for f in \"$1\"/*.desktop; do [ -f \"$f\" ] || continue;"
            + " grep -qE '^(Hidden|NoDisplay)=true' \"$f\" && continue;"
            + " b=${f##*/}; b=${b%.desktop};"
            + " n=$(sed -n 's/^Name=//p' \"$f\" | head -n 1); e=$(sed -n 's/^Exec=//p' \"$f\" | head -n 1);"
            + " [ -n \"$e\" ] && printf '%s\\t%s\\t%s\\n' \"$b\" \"${n:-$e}\" \"$e\"; done; true",
            "sh", Quickshell.env("FLO_GREETER_SESSIONS_DIR") || "/usr/share/wayland-sessions"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let chosen = 0;
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const f = lines[i].split("\t");
                    if (f.length !== 3 || !win.sessionAllowed(f[0]))
                        continue;
                    if (f[2] === win.defaultSession)
                        chosen = out.length;
                    out.push({ id: f[0], name: f[1], exec: f[2] });
                }
                win.sessions = out;
                win.sessionIndex = chosen;
            }
        }
    }

    // ---- Authentication --------------------------------------------------
    readonly property string backend: auth.effectiveBackend
    readonly property string status: auth.status
    property bool launched: false

    function devType(text: string): void {
        pad.devType(text);
    }

    Auth {
        id: auth
        backend: "greetd"
        user: win.user
        onSucceeded: {
            status = I18n.t("greeter.starting");
            // The session command is a shell command line (Exec= syntax).
            // greetd joins the command words with spaces and runs the result
            // with /bin/sh -c (after sourcing the profile), so the session
            // command goes as one shell string. Wrapping it in "/bin/sh -c"
            // here made it "sh -c exec flo-session", which exits at once.
            launch([win.sessionCommand], ["XDG_SESSION_TYPE=wayland"]);
        }
        onLaunched: win.launched = true
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-greeter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        id: content

        readonly property bool land: width > height
        readonly property bool wide: land && !pad.textMode
        readonly property int margin: Theme.spaceXl

        anchors.fill: parent

        Row {
            anchors.right: parent.right
            anchors.rightMargin: content.margin
            y: Theme.spaceL
            spacing: Theme.spaceS
            visible: Battery.available

            Icon {
                visible: Battery.charging
                anchors.verticalCenter: parent.verticalCenter
                name: "bolt"
                size: 18
                color: Theme.ok
            }
            BatteryIcon {
                anchors.verticalCenter: parent.verticalCenter
                level: Battery.percent / 100
                charging: Battery.charging
                low: Battery.low
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Battery.percent + "%"
                color: Battery.low ? Theme.danger : Theme.textDim
            }
        }

        // Clock, users and sessions: top in portrait, left in landscape.
        Column {
            id: info

            visible: !(content.land && pad.textMode)
            width: content.wide ? Math.round(content.width / 2) - 2 * content.margin : content.width - 2 * content.margin
            x: content.margin
            y: content.wide ? Math.round((content.height - height) / 2) : Math.max(Theme.touch, Math.round((pad.y - height) / 2))
            spacing: Theme.spaceM

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.time
                font.pixelSize: pad.textMode ? Theme.fontDisplay : Theme.fontClock
                font.weight: Font.DemiBold
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.longDate
                color: Theme.textDim
            }
            Label {
                visible: auth.dry
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.t("lock.dryRun")
                color: Theme.warn
                font.pixelSize: Theme.fontSmall
            }

            Label {
                visible: win.users.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.t("greeter.noUsers")
                color: Theme.danger
            }
            Row {
                visible: !pad.textMode
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spaceS

                Repeater {
                    model: win.users

                    Pressable {
                        id: chip

                        required property string modelData
                        readonly property bool selected: win.user === modelData
                        readonly property color fg: selected ? Theme.accentText : Theme.text

                        width: chipRow.width + 2 * Theme.spaceL
                        height: Theme.touch
                        accessibleName: modelData
                        Accessible.selected: selected
                        background: selected ? Theme.accent : Theme.surfaceAlt
                        pressedColor: selected ? Qt.darker(Theme.accent, 1.2) : Theme.pressed
                        onTapped: win.selectUser(modelData)

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Theme.spaceS

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "user"
                                color: chip.fg
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData
                                color: chip.fg
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
            // Session choice, only when there is one to make.
            Row {
                visible: win.sessions.length > 1 && !pad.textMode
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spaceS

                Repeater {
                    model: win.sessions

                    Pressable {
                        id: sessionChip

                        required property var modelData
                        required property int index
                        readonly property bool selected: win.sessionIndex === index

                        width: sessionLabel.width + 2 * Theme.spaceL
                        height: Theme.touchMin
                        accessibleName: modelData.name
                        Accessible.selected: selected
                        background: Theme.surface
                        onTapped: win.sessionIndex = index

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: "transparent"
                            border.width: sessionChip.selected ? 2 : 1
                            border.color: sessionChip.selected ? Theme.accent : Theme.border
                        }
                        Label {
                            id: sessionLabel
                            anchors.centerIn: parent
                            text: sessionChip.modelData.name
                            color: sessionChip.selected ? Theme.text : Theme.textDim
                        }
                    }
                }
            }
        }

        AuthPad {
            id: pad

            x: content.wide ? Math.round(content.width / 2) : 0
            width: content.wide ? Math.round(content.width / 2) : content.width
            y: content.wide ? Math.round((content.height - height) / 2) : content.height - height - Theme.spaceL
            prompt: I18n.t(textMode ? "lock.enterPassword" : "lock.enterPin")
            status: auth.status
            statusIsError: auth.statusIsError
            busy: auth.busy || win.launched || win.user === ""
            onSubmitted: secret => auth.submit(secret)
            onEdited: auth.clearStatus()
            Component.onCompleted: forceActiveFocus()
        }
    }
}
