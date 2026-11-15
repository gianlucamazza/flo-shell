import QtQuick
import Quickshell

// Fake authentication for development and for the first on-device trial of
// the lock surface: accepts FLO_AUTH_DRY_SECRET (default "1234"). Never
// looks at real credentials. Selected with FLO_AUTH=dry.
QtObject {
    id: root

    readonly property string secret: Quickshell.env("FLO_AUTH_DRY_SECRET") || "1234"
    readonly property bool canLaunch: true

    signal succeeded
    signal failed(string reason)
    signal info(string message, bool error)
    signal launched

    function submit(user: string, secret: string): void {
        const ok = secret === root.secret;
        // Answer on the next event-loop turn, like a real backend.
        Qt.callLater(() => {
            if (ok)
                root.succeeded();
            else
                root.failed("wrong");
        });
    }
    function cancel(): void {
    }
    function launch(command: list<string>, environment: list<string>): void {
        console.info("flo-auth: dry-run launch", JSON.stringify(command), JSON.stringify(environment));
        root.launched();
    }
}
