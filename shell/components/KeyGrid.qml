import QtQuick
import qs

// Minimal QWERTY keyboard drawn by the shell itself, for the places where
// no on-screen keyboard client can appear: above a session lock and in the
// greeter. It edits nothing: it only reports keys.
//
// Every row spans the full width; a key is width / 10 wide (60 px in
// portrait) and Theme.touchMin tall. Press feedback is a colour swap.
Item {
    id: root

    property bool shift: false
    property bool symbols: false
    property string enterIcon: "enter"

    signal key(string text)
    signal backspace
    signal enter

    readonly property real unit: width / 10
    readonly property int rowHeight: Theme.touchMin

    // Entries: a character, or a named key {k, w} with a width in units.
    readonly property var letters: [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        [{ k: "shift", w: 1.5 }, "z", "x", "c", "v", "b", "n", "m", { k: "back", w: 1.5 }],
        [{ k: "sym", w: 1.5 }, ",", { k: "space", w: 5 }, ".", { k: "enter", w: 1.5 }]
    ]
    readonly property var symbolRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["@", "#", "€", "_", "&", "-", "+", "(", ")"],
        [{ k: "more", w: 1.5 }, "*", "\"", "'", ":", ";", "!", "?", { k: "back", w: 1.5 }],
        [{ k: "sym", w: 1.5 }, "/", { k: "space", w: 5 }, "=", { k: "enter", w: 1.5 }]
    ]
    readonly property var moreRows: [
        ["~", "`", "|", "\\", "^", "%", "$", "£", "{", "}"],
        ["[", "]", "<", ">", "°", "§", "à", "è", "é"],
        [{ k: "more", w: 1.5 }, "ì", "ò", "ù", "ç", "¿", "¡", "…", { k: "back", w: 1.5 }],
        [{ k: "sym", w: 1.5 }, ",", { k: "space", w: 5 }, ".", { k: "enter", w: 1.5 }]
    ]
    property bool more: false
    readonly property var rows: !symbols ? letters : more ? moreRows : symbolRows

    implicitHeight: 4 * rowHeight

    function press(entry: var): void {
        if (typeof entry === "string") {
            root.key(root.shift && !root.symbols ? entry.toUpperCase() : entry);
            root.shift = false;
        } else if (entry.k === "shift") {
            root.shift = !root.shift;
        } else if (entry.k === "sym") {
            root.symbols = !root.symbols;
            root.more = false;
        } else if (entry.k === "more") {
            root.more = !root.more;
        } else if (entry.k === "back") {
            root.backspace();
        } else if (entry.k === "space") {
            root.key(" ");
        } else if (entry.k === "enter") {
            root.enter();
        }
    }

    Column {
        anchors.fill: parent

        Repeater {
            model: root.rows

            Row {
                id: row

                required property var modelData

                anchors.horizontalCenter: parent.horizontalCenter
                height: root.rowHeight

                Repeater {
                    model: row.modelData

                    Item {
                        id: cell

                        required property var modelData
                        readonly property bool named: typeof modelData !== "string"
                        readonly property string kind: named ? modelData.k : ""
                        readonly property string glyph: kind === "back" ? "backspace" : kind === "shift" ? "shift" : kind === "enter" ? root.enterIcon : ""

                        width: Math.floor(root.unit * (named ? modelData.w : 1))
                        height: root.rowHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 8
                            color: area.pressed ? Theme.pressed : cell.kind === "enter" ? Theme.accent : (cell.kind === "shift" && root.shift) ? Theme.border : cell.named && cell.kind !== "space" ? Theme.surface : Theme.surfaceAlt
                            border.width: cell.named && cell.kind !== "space" && cell.kind !== "enter" ? 1 : 0
                            border.color: Theme.border
                        }
                        Icon {
                            visible: cell.glyph !== ""
                            anchors.centerIn: parent
                            name: cell.glyph
                            size: 22
                            color: cell.kind === "enter" && !area.pressed ? Theme.accentText : Theme.text
                        }
                        Label {
                            visible: cell.glyph === "" && cell.kind !== "space"
                            anchors.centerIn: parent
                            text: !cell.named ? (root.shift && !root.symbols ? cell.modelData.toUpperCase() : cell.modelData) : cell.kind === "sym" ? (root.symbols ? "abc" : "123") : cell.kind === "more" ? (root.more ? "123" : "#+=") : ""
                            font.pixelSize: cell.named ? Theme.fontSmall : Theme.fontTitle
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            onPressed: root.press(cell.modelData)
                        }
                    }
                }
            }
        }
    }
}
