import QtQuick
import Quickshell
import Quickshell.Services.Pam

// PAM authentication for the lock screen. The PAM service is "flo-shell"
// in /etc/pam.d (installed from session/pam/flo-shell); FLO_PAM_CONFIG and
// FLO_PAM_CONFIG_DIR override both, which is how dev/run-nested.sh points
// it at a throw-away service that never sees real credentials.
//
// The secret is handed to the first prompt that wants a response. A second
// prompt in the same conversation means the stack wants something this
// pad cannot provide (new password, second factor): the attempt is aborted.
QtObject {
    id: root

    readonly property bool canLaunch: false

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
        if (pam.active)
            return;
        _secret = secret;
        _answered = false;
        _done = false;
        pam.user = user;
        if (!pam.start())
            _finish(false, "error");
    }
    function cancel(): void {
        if (pam.active)
            pam.abort();
        _done = true;
        _secret = "";
    }
    function launch(command: list<string>, environment: list<string>): void {
    }

    property PamContext pam: PamContext {
        config: Quickshell.env("FLO_PAM_CONFIG") || "flo-shell"
        configDirectory: Quickshell.env("FLO_PAM_CONFIG_DIR") || "/etc/pam.d"

        onPamMessage: {
            if (responseRequired) {
                if (root._answered) {
                    abort();
                    root._finish(false, "wrong");
                } else {
                    root._answered = true;
                    respond(root._secret);
                }
            } else if (message !== "") {
                root.info(message, messageIsError);
            }
        }
        onCompleted: result => root._finish(result === PamResult.Success, result === PamResult.MaxTries ? "tooMany" : result === PamResult.Failed ? "wrong" : "error")
        onError: error => console.warn("flo-auth: pam error", PamError.toString(error))
    }
}
