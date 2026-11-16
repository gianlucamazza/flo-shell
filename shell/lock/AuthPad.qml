import QtQuick
import Quickshell
import qs
import qs.components

// Touch entry for a PIN or a password, shared by the lock screen and the
// greeter. Numeric pad by default; the "abc" key switches to a full text
// field with the shell's own keyboard (no on-screen keyboard client can be
// shown over a session lock). A hardware keyboard works in both modes.
//
// The pad never checks anything: it emits submitted(secret) and clears.
Item {
    id: root

    property string prompt: ""
    property string status: ""
    property bool statusIsError: false
    property bool busy: false
    property bool textMode: false
    property bool reveal: false
    property string secret: ""
    readonly property int maxLength: 128

    signal submitted(string secret)
    // Emitted on every edit, e.g. to clear an old error.
    signal edited

    // Numeric pad is narrow and centred; the keyboard uses the full width.
    readonly property int padWidth: Math.min(width, Theme.padMaxWidth)

    implicitHeight: column.implicitHeight

    function add(text: string): void {
        if (busy || secret.length >= maxLength)
            return;
        secret += text;
        root.edited();
    }
    function backspace(): void {
        if (busy)
            return;
        secret = secret.substring(0, secret.length - 1);
        root.edited();
    }
    function clear(): void {
        secret = "";
    }
    function submit(): void {
        if (busy || secret === "")
            return;
        const s = secret;
        secret = "";
        root.submitted(s);
    }

    // Development only (FLO_DEV_INPUT=1, set by dev/run-nested.sh): lets
    // the IPC type into the pad, because nothing can inject touches into
    // the nested compositor. "\n" submits. Inert otherwise.
    readonly property bool devInput: (Quickshell.env("FLO_DEV_INPUT") || "") === "1"
    function devType(text: string): void {
        if (!devInput)
            return;
        if (text === "\n")
            submit();
        else if (text === "abc")
            textMode = true;
        else
            add(text);
    }

    // Hardware keyboard (USB OTG, Bluetooth).
    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit();
        } else if (event.key === Qt.Key_Backspace) {
            root.backspace();
        } else if (event.key === Qt.Key_Escape) {
            root.clear();
        } else if (event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
            if (!/[0-9]/.test(event.text))
                root.textMode = true;
            root.add(event.text);
        } else {
            return;
        }
        event.accepted = true;
    }

    Column {
        id: column

        width: parent.width
        spacing: Theme.spaceS

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.prompt
            color: Theme.textDim
        }

        // Entered secret: dots, or the text when revealed.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.padWidth
            height: Theme.touch
            radius: Theme.radius
            color: Theme.surface
            border.width: 1
            border.color: root.statusIsError && root.secret === "" ? Theme.danger : Theme.border

            Label {
                visible: root.textMode && root.reveal
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceL
                anchors.right: eye.left
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideLeft
                text: root.secret
                font.pixelSize: Theme.fontTitle
            }
            Row {
                visible: !(root.textMode && root.reveal)
                anchors.centerIn: parent
                spacing: Theme.spaceS

                Repeater {
                    model: Math.min(root.secret.length, 14)

                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.text
                    }
                }
            }
            IconButton {
                id: eye
                visible: root.textMode
                anchors.right: parent.right
                width: Theme.touch
                height: parent.height
                icon: "eye"
                iconColor: root.reveal ? Theme.accent : Theme.textDim
                onTapped: root.reveal = !root.reveal
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            // Keeps its line when empty so the pad does not jump.
            text: root.status !== "" ? root.status : " "
            color: root.statusIsError ? Theme.danger : Theme.textDim
            font.pixelSize: Theme.fontSmall
        }

        // ---- Numeric pad ---------------------------------------------------
        Grid {
            id: pad

            readonly property var keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "abc", "0", "back"]

            visible: !root.textMode
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.padWidth
            columns: 3

            Repeater {
                model: pad.keys

                Item {
                    id: cell

                    required property string modelData
                    enabled: !root.busy
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData === "back" ? I18n.t("lock.delete") : modelData === "abc" ? I18n.t("lock.enterPassword") : modelData
                    Accessible.onPressAction: activate()
                    Keys.onReturnPressed: activate()
                    Keys.onSpacePressed: activate()
                    function activate(): void {
                        if (root.busy) return;
                        if (modelData === "back") root.backspace();
                        else if (modelData === "abc") root.textMode = true;
                        else root.add(modelData);
                    }

                    width: Math.floor(pad.width / 3)
                    height: Theme.padKeyHeight + 6

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Theme.radius
                        color: area.pressed ? Theme.pressed : cell.modelData.length === 1 ? Theme.surfaceAlt : Theme.surface
                        border.width: cell.activeFocus ? 2 : cell.modelData.length === 1 ? 0 : 1
                        border.color: cell.activeFocus ? Theme.accent : Theme.border
                    }
                    Icon {
                        visible: cell.modelData === "back"
                        anchors.centerIn: parent
                        name: "backspace"
                    }
                    Label {
                        visible: cell.modelData !== "back"
                        anchors.centerIn: parent
                        text: cell.modelData === "abc" ? I18n.t("lock.usePassword") : cell.modelData
                        font.pixelSize: cell.modelData.length === 1 ? 26 : Theme.fontBody
                        color: cell.modelData.length === 1 ? Theme.text : Theme.textDim
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        onClicked: cell.activate()
                    }
                }
            }
        }
        Pressable {
            visible: !root.textMode
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.padWidth - 6
            height: Theme.touch
            background: root.secret !== "" && !root.busy ? Theme.accent : Theme.surface
            pressedColor: Qt.darker(Theme.accent, 1.2)
            onTapped: root.submit()
            accessibleName: I18n.t("lock.submit")
            enabled: !root.busy && root.secret !== ""

            Icon {
                anchors.centerIn: parent
                name: "check"
                size: 28
                color: root.secret !== "" && !root.busy ? Theme.accentText : Theme.textDim
            }
        }

        // ---- Text mode -----------------------------------------------------
        KeyGrid {
            visible: root.textMode
            width: parent.width
            enterIcon: "check"
            onKey: text => root.add(text)
            onBackspace: root.backspace()
            onEnter: root.submit()
        }
        Pressable {
            visible: root.textMode
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.touch * 2
            accessibleName: I18n.t("lock.enterPin")
            height: Theme.touchMin
            onTapped: {
                root.textMode = false;
                root.reveal = false;
            }

            Label {
                anchors.centerIn: parent
                text: I18n.t("lock.usePin")
                color: Theme.textDim
            }
        }
    }
}
