import QtQuick
import qs

// Labeled single-line field. Raises the on-screen keyboard through the
// focused() signal (the same path as the launcher search box).
Item {
    id: root

    property string label
    property string text: ""
    property string error: ""
    property bool masked: false
    property bool fieldEnabled: true
    property int inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

    signal focused
    signal edited(string value)

    function currentValue(): string {
        return input.text;
    }

    function clear(): void {
        input.text = "";
        if (root.text !== "")
            root.text = "";
    }

    implicitHeight: col.height
    width: parent ? parent.width : 0

    onTextChanged: {
        if (input.text !== text)
            input.text = text;
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.spaceXs

        Label {
            width: parent.width
            text: root.label
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
        }
        Rectangle {
            width: parent.width
            height: Theme.touch
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.width: input.activeFocus || root.error !== "" ? 2 : 0
            border.color: root.error !== "" ? Theme.danger : Theme.accent
            opacity: root.fieldEnabled ? 1 : 0.45

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceL
                anchors.rightMargin: Theme.spaceL
                verticalAlignment: Text.AlignVCenter
                clip: true
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                echoMode: root.masked ? TextInput.Password : TextInput.Normal
                passwordCharacter: "•"
                inputMethodHints: root.masked ? (Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase) : root.inputMethodHints
                readOnly: !root.fieldEnabled
                onTextEdited: root.edited(text)
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.fieldEnabled && !input.activeFocus
                onClicked: {
                    input.forceActiveFocus();
                    root.focused();
                }
            }
        }
        Label {
            visible: root.error !== ""
            width: parent.width
            text: root.error
            color: Theme.danger
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.Wrap
        }
    }
}
