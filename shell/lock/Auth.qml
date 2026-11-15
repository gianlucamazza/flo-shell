import QtQuick
import Quickshell
import qs

// One authentication attempt at a time, over a backend chosen at run time:
//   pam     PamContext (lock screen)
//   greetd  the greetd socket (greeter)
//   dry     fake, for development (FLO_AUTH=dry)
// FLO_AUTH overrides `backend`. Backends live in lock/auth/ and are loaded
// by name, so the shell never imports the greetd module and the greeter
// never needs PAM.
Item {
    id: root

    property string backend: "pam"
    // Empty means the current user (PAM only).
    property string user: ""

    readonly property string effectiveBackend: Quickshell.env("FLO_AUTH") || backend
    readonly property bool dry: effectiveBackend === "dry"
    readonly property bool ready: loader.status === Loader.Ready
    property bool busy: false
    // Text for the user: backend message or the translated failure.
    property string status: ""
    property bool statusIsError: false
    property int failures: 0

    signal succeeded
    signal failed
    signal launched

    function submit(secret: string): void {
        if (busy || !ready || secret === "")
            return;
        busy = true;
        status = I18n.t("lock.checking");
        statusIsError = false;
        loader.item.submit(user, secret);
    }
    function cancel(): void {
        if (ready)
            loader.item.cancel();
        busy = false;
    }
    function clearStatus(): void {
        if (!busy)
            status = "";
    }
    // Greeter only: start the session after `succeeded`.
    function launch(command: list<string>, environment: list<string>): void {
        if (ready)
            loader.item.launch(command, environment);
    }

    Loader {
        id: loader
        source: root.effectiveBackend === "dry" ? "auth/DryAuth.qml" : root.effectiveBackend === "greetd" ? "auth/GreetdAuth.qml" : "auth/PamAuth.qml"
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("flo-auth: backend", root.effectiveBackend, "failed to load");
        }
    }
    Connections {
        target: loader.item

        function onSucceeded(): void {
            root.busy = false;
            root.failures = 0;
            root.status = "";
            root.succeeded();
        }
        function onFailed(reason: string): void {
            root.busy = false;
            root.failures += 1;
            root.statusIsError = true;
            root.status = I18n.t(reason === "wrong" ? "lock.wrong" : reason === "tooMany" ? "lock.tooMany" : reason === "noGreetd" ? "greeter.noGreetd" : "lock.error");
            root.failed();
        }
        function onInfo(message: string, error: bool): void {
            root.status = message;
            root.statusIsError = error;
        }
        function onLaunched(): void {
            root.launched();
        }
    }
}
