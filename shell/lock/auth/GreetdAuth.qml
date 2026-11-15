import QtQuick
import Quickshell
import Quickshell.Services.Greetd

// greetd authentication for the greeter: create a session for the user,
// answer the first prompt with the secret, then launch() the session
// command, which also makes Quickshell quit.
QtObject {
    id: root

    readonly property bool canLaunch: true
    readonly property bool available: Greetd.available

    signal succeeded
    signal failed(string reason)
    signal info(string message, bool error)
    signal launched

    property string _secret: ""
    property bool _answered: false
    property bool _done: true

    function _finish(ok: bool, reason: string): void {
        if (_done)
            return;
        _done = true;
        _secret = "";
        if (ok)
            root.succeeded();
        else
            root.failed(reason);
    }

    function submit(user: string, secret: string): void {
        if (!Greetd.available) {
            _done = false;
            _finish(false, "noGreetd");
            return;
        }
        if (Greetd.state !== GreetdState.Inactive)
            return;
        _secret = secret;
        _answered = false;
        _done = false;
        Greetd.createSession(user);
    }
    function cancel(): void {
        _done = true;
        _secret = "";
        if (Greetd.available && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
    }
    function launch(command: list<string>, environment: list<string>): void {
        Greetd.launch(command, environment, true);
    }

    property Connections _greetd: Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) {
                if (root._answered) {
                    Greetd.cancelSession();
                    root._finish(false, "wrong");
                } else {
                    root._answered = true;
                    Greetd.respond(root._secret);
                }
            } else if (message !== "") {
                root.info(message, error);
            }
        }
        function onAuthFailure(message: string): void {
            root._finish(false, "wrong");
        }
        function onError(error: string): void {
            console.warn("flo-auth: greetd error", error);
            root._finish(false, "error");
        }
        function onReadyToLaunch(): void {
            root._finish(true, "");
        }
        function onLaunched(): void {
            root.launched();
        }
    }
}
