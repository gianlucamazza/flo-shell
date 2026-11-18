import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// Touch-first agent configuration. flo-agents is the only writer of the
// config: this panel never edits files. The CLI runs only on open, save,
// test, Create key, Crush install/uninstall and secret set/unset.
// Loaded lazily from shell.qml. The API key is written to Process stdin
// and is not kept in a QML property after save.
PanelWindow {
    id: win

    readonly property bool open: Ui.agentSettingsOpen
    property real progress: open ? 1 : 0
    property bool raisedKeyboard: false
    property bool saving: false
    property bool testing: false
    property bool keyBusy: false
    property bool wlCopyAvailable: false

    property string host: ""
    property string user: ""
    property string port: "22"
    property string transport: "mosh"
    property bool claudeOn: false
    property bool codexOn: false
    property bool grokOn: false
    property string claudeCmd: "claude"
    property string codexCmd: "codex"
    property string grokCmd: "grok"
    property string defaultAgent: ""
    property bool tmuxOn: true
    property string tmuxPrefix: "flo"
    property var fieldErrors: ({})
    property var loaded: ({})

    property bool checkDone: false
    property bool reachable: false
    property string checkError: ""
    property var agentStatus: ({})
    property string hostKey: ""

    property string publicKey: ""
    property bool keyPresent: false
    property string qrPath: ""

    property string localProvider: ""
    property string localBaseUrl: ""
    property string localModel: ""
    property bool crushInstalled: false
    property string crushVersion: ""
    property string crushPath: ""
    property string localActionMsg: ""
    property bool secretSet: false
    property string secretLast4: ""
    property bool secretBusy: false
    property bool apiKeyTyped: false

    readonly property var toolOrder: ["claude", "codex", "grok"]
    readonly property var localProviders: ["anthropic", "openai", "xai", "openai-compat", "ollama", "llamacpp"]
    readonly property bool needsBaseUrl: localProvider === "openai-compat" || localProvider === "ollama" || localProvider === "llamacpp"
    readonly property bool needsApiKey: localProvider !== "ollama" && localProvider !== "llamacpp"
    readonly property bool localBusy: localActionProc.running

    Behavior on progress {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Theme.easing
        }
    }

    function errOf(key: string): string {
        const e = fieldErrors;
        return e && e[key] ? e[key] : "";
    }

    function raiseKeyboard(): void {
        if (Keyboard.available && !Keyboard.visible) {
            Keyboard.show();
            win.raisedKeyboard = true;
        }
    }

    function agentsValue(): string {
        const ids = [];
        if (claudeOn)
            ids.push("claude");
        if (codexOn)
            ids.push("codex");
        if (grokOn)
            ids.push("grok");
        return ids.join(",");
    }

    function enabledDefault(): string {
        if (defaultAgent === "claude" && claudeOn)
            return "claude";
        if (defaultAgent === "codex" && codexOn)
            return "codex";
        if (defaultAgent === "grok" && grokOn)
            return "grok";
        if (claudeOn)
            return "claude";
        if (codexOn)
            return "codex";
        if (grokOn)
            return "grok";
        return "";
    }

    function snapshot(): var {
        return {
            host: host,
            user: user,
            port: port,
            transport: transport,
            agents: agentsValue(),
            default: enabledDefault(),
            "cmd.claude": claudeCmd,
            "cmd.codex": codexCmd,
            "cmd.grok": grokCmd,
            tmux: tmuxOn ? "on" : "off",
            tmux_prefix: tmuxPrefix,
            "local.provider": localProvider,
            "local.base_url": localBaseUrl,
            "local.model": localModel
        };
    }

    readonly property bool isDirty: host !== (loaded.host || "")
        || user !== (loaded.user || "")
        || port !== (loaded.port || "")
        || transport !== (loaded.transport || "")
        || agentsValue() !== (loaded.agents || "")
        || enabledDefault() !== (loaded.default || "")
        || claudeCmd !== (loaded["cmd.claude"] || "")
        || codexCmd !== (loaded["cmd.codex"] || "")
        || grokCmd !== (loaded["cmd.grok"] || "")
        || (tmuxOn ? "on" : "off") !== (loaded.tmux || "")
        || tmuxPrefix !== (loaded.tmux_prefix || "")
        || localProvider !== (loaded["local.provider"] || "")
        || localBaseUrl !== (loaded["local.base_url"] || "")
        || localModel !== (loaded["local.model"] || "")

    function applyConfig(text: string): void {
        let o;
        try {
            o = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!o || typeof o !== "object")
            return;
        host = o.host || "";
        user = o.user || "";
        port = o.port === undefined || o.port === null ? "22" : String(o.port);
        transport = o.transport === "ssh" ? "ssh" : "mosh";
        const agents = o.agents || [];
        claudeOn = agents.indexOf("claude") >= 0;
        codexOn = agents.indexOf("codex") >= 0;
        grokOn = agents.indexOf("grok") >= 0;
        const cmd = o.cmd || {};
        claudeCmd = cmd.claude || "claude";
        codexCmd = cmd.codex || "codex";
        grokCmd = cmd.grok || "grok";
        defaultAgent = o.default || "";
        tmuxOn = !!o.tmux;
        tmuxPrefix = o.tmux_prefix || "flo";
        const key = o.key || {};
        keyPresent = !!key.present;
        publicKey = key.public || "";
        const loc = o.local || {};
        localProvider = loc.provider || "";
        localBaseUrl = loc.base_url || "";
        localModel = loc.model || "";
        crushInstalled = !!loc.installed;
        crushVersion = loc.version || "";
        if (typeof loc.key_set === "boolean" && !loc.key_set) {
            secretSet = false;
            secretLast4 = "";
        }
        loaded = snapshot();
    }

    function applyLocalStatus(text: string): void {
        let o;
        try {
            o = JSON.parse(text || "");
        } catch (e) {
            return;
        }
        if (!o || typeof o !== "object")
            return;
        crushInstalled = !!o.installed;
        if (o.version !== undefined && o.version !== null)
            crushVersion = String(o.version);
        crushPath = o.path || "";
    }

    function applySecretStatus(text: string): void {
        const t = (text || "").trim();
        if (t === "")
            return;
        let o;
        try {
            o = JSON.parse(t);
        } catch (e) {
            o = null;
        }
        if (o && typeof o === "object") {
            secretSet = !!(o.set || o.key_set);
            const last = String(o.last4 || o.last || "");
            secretLast4 = last.slice(-4);
            return;
        }
        if (t.indexOf("unset") === 0) {
            secretSet = false;
            secretLast4 = "";
            return;
        }
        secretSet = t.indexOf("set") === 0;
        const m = t.match(/([A-Za-z0-9]{4})\s*$/);
        secretLast4 = secretSet && m ? m[1] : "";
    }

    function load(): void {
        if (getProc.running)
            return;
        fieldErrors = ({});
        checkDone = false;
        getProc.running = true;
        if (!secretStatusProc.running)
            secretStatusProc.running = true;
        if (!localStatusProc.running)
            localStatusProc.running = true;
    }

    function save(): void {
        if (saving || applyProc.running || !isDirty)
            return;
        const now = snapshot();
        const was = loaded;
        const order = ["host", "user", "port", "transport", "agents", "default", "cmd.claude", "cmd.codex", "cmd.grok", "tmux", "tmux_prefix", "local.provider", "local.base_url", "local.model"];
        const cmd = ["flo-agent-config", "apply"];
        for (let i = 0; i < order.length; i++) {
            const k = order[i];
            const v = now[k] || "";
            if (v !== (was[k] || "")) {
                cmd.push(k);
                cmd.push(v);
            }
        }
        if (cmd.length === 2)
            return;
        saving = true;
        fieldErrors = ({});
        applyProc.command = cmd;
        applyProc.running = true;
    }

    function testConn(): void {
        if (testing || checkProc.running)
            return;
        testing = true;
        checkDone = false;
        checkProc.running = true;
    }

    function createKey(): void {
        if (keyBusy || keyProc.running)
            return;
        keyBusy = true;
        qrPath = "";
        keyProc.running = true;
    }

    function copyKey(): void {
        if (publicKey === "" || !wlCopyAvailable || copyProc.running)
            return;
        copyProc.command = ["wl-copy", publicKey];
        copyProc.running = true;
    }

    function runLocal(kind: string): void {
        if (localActionProc.running)
            return;
        localActionMsg = "";
        localActionProc.command = ["flo-agent-config", kind === "uninstall" ? "local-uninstall" : "local-install"];
        localActionProc.running = true;
    }

    function saveApiKey(): void {
        if (secretBusy || secretSetProc.running)
            return;
        if (apiKeyField.currentValue() === "")
            return;
        secretBusy = true;
        secretSetProc.stdinEnabled = true;
        secretSetProc.running = true;
    }

    function removeApiKey(): void {
        if (secretBusy || secretUnsetProc.running)
            return;
        secretBusy = true;
        secretUnsetProc.running = true;
    }

    function _onApply(text: string, code: int): void {
        saving = false;
        const fe = {};
        let jsonText = text || "";
        if (jsonText.indexOf("ERR\t") === 0) {
            const nl = jsonText.indexOf("\n");
            const line = nl < 0 ? jsonText : jsonText.slice(0, nl);
            jsonText = nl < 0 ? "" : jsonText.slice(nl + 1);
            const parts = line.split("\t");
            if (parts.length >= 3)
                fe[parts[1]] = parts[2];
        }
        fieldErrors = fe;
        if (jsonText.trim() !== "")
            applyConfig(jsonText.trim());
    }

    function _onCheck(text: string, code: int): void {
        testing = false;
        checkDone = true;
        let o;
        try {
            o = JSON.parse(text || "{}");
        } catch (e) {
            reachable = false;
            checkError = text || "";
            agentStatus = ({});
            hostKey = "unknown";
            return;
        }
        reachable = !!o.reachable;
        checkError = o.error || "";
        agentStatus = o.agents || ({});
        hostKey = o.host_key || "unknown";
    }

    function hostKeyText(): string {
        if (hostKey === "new")
            return I18n.t("agents.hostKeyNew");
        if (hostKey === "changed")
            return I18n.t("agents.hostKeyChanged");
        return "";
    }

    function agentState(id: string): string {
        const s = agentStatus[id];
        if (s === "present")
            return I18n.t("agents.present");
        if (s === "missing")
            return I18n.t("agents.missing");
        return "";
    }

    onOpenChanged: {
        if (open) {
            load();
        } else {
            if (win.raisedKeyboard)
                Keyboard.hide();
            win.raisedKeyboard = false;
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Normal
    visible: open || progress > 0
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flo-agent-settings"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Process {
        id: getProc
        command: ["flo-agent-config", "get"]
        stdout: StdioCollector {
            id: getOut
        }
        onExited: code => win.applyConfig(getOut.text)
    }
    Process {
        id: applyProc
        stdout: StdioCollector {
            id: applyOut
        }
        onExited: code => win._onApply(applyOut.text, code)
    }
    Process {
        id: checkProc
        command: ["flo-agent-config", "check"]
        stdout: StdioCollector {
            id: checkOut
        }
        onExited: code => win._onCheck(checkOut.text, code)
    }
    Process {
        id: keyProc
        command: ["flo-agent-config", "key-ensure"]
        stdout: StdioCollector {
            id: keyOut
        }
        onExited: code => {
            if (code === 0)
                win.publicKey = (keyOut.text || "").replace(/\n+$/, "");
            win.keyPresent = win.publicKey !== "";
            win.keyBusy = false;
            if (code === 0 && !qrProc.running)
                qrProc.running = true;
        }
    }
    Process {
        id: qrProc
        command: ["flo-agent-config", "key-qr"]
        stdout: StdioCollector {
            id: qrOut
        }
        onExited: code => {
            win.qrPath = code === 0 ? (qrOut.text || "").replace(/\n+$/, "") : "";
        }
    }
    Process {
        id: copyProc
    }
    Process {
        id: wlCopyProbe
        command: ["sh", "-c", "command -v wl-copy >/dev/null 2>&1"]
        running: true
        onExited: code => win.wlCopyAvailable = code === 0
    }
    Process {
        id: localStatusProc
        command: ["flo-agent-config", "local-status"]
        stdout: StdioCollector {
            id: localStatusOut
        }
        onExited: code => {
            if (code === 0)
                win.applyLocalStatus(localStatusOut.text);
        }
    }
    Process {
        id: localActionProc
        stdout: StdioCollector {
            id: localActionOut
        }
        stderr: StdioCollector {
            id: localActionErr
        }
        onExited: code => {
            const out = (localActionOut.text || "").replace(/\n+$/, "");
            const err = (localActionErr.text || "").replace(/\n+$/, "");
            win.localActionMsg = out !== "" ? out : err;
            if (!localStatusProc.running)
                localStatusProc.running = true;
            if (!getProc.running)
                getProc.running = true;
        }
    }
    Process {
        id: secretStatusProc
        command: ["flo-agent-config", "secret-status"]
        stdout: StdioCollector {
            id: secretStatusOut
        }
        onExited: code => {
            if (code === 0)
                win.applySecretStatus(secretStatusOut.text);
        }
    }
    Process {
        id: secretSetProc
        command: ["flo-agent-config", "secret-set"]
        stdinEnabled: true
        onStarted: {
            const k = apiKeyField.currentValue();
            apiKeyField.clear();
            win.apiKeyTyped = false;
            secretSetProc.write(k);
            secretSetProc.stdinEnabled = false;
        }
        onExited: code => {
            win.secretBusy = false;
            secretSetProc.stdinEnabled = true;
            if (!secretStatusProc.running)
                secretStatusProc.running = true;
        }
    }
    Process {
        id: secretUnsetProc
        command: ["flo-agent-config", "secret-unset"]
        onExited: code => {
            win.secretBusy = false;
            if (code === 0) {
                win.secretSet = false;
                win.secretLast4 = "";
            }
            if (!secretStatusProc.running)
                secretStatusProc.running = true;
        }
    }

    Item {
        id: content

        readonly property int pad: Theme.spaceL

        anchors.fill: parent
        opacity: win.progress
        transform: Translate {
            y: (1 - win.progress) * 28
        }

        Item {
            id: header
            width: parent.width
            height: Theme.touch

            Label {
                x: content.pad
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("agents.settings")
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
            }
            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceXs
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                onTapped: Ui.agentSettingsOpen = false
            }
        }

        Flickable {
            id: flick
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.bottomMargin: Theme.spaceS
            x: content.pad
            width: parent.width - 2 * content.pad
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: form.height

            Column {
                id: form
                width: flick.width
                spacing: Theme.spaceM

                FormField {
                    label: I18n.t("agents.host")
                    text: win.host
                    error: win.errOf("host")
                    onEdited: value => win.host = value
                    onFocused: win.raiseKeyboard()
                }
                FormField {
                    label: I18n.t("agents.user")
                    text: win.user
                    error: win.errOf("user")
                    onEdited: value => win.user = value
                    onFocused: win.raiseKeyboard()
                }
                FormField {
                    label: I18n.t("agents.port")
                    text: win.port
                    error: win.errOf("port")
                    inputMethodHints: Qt.ImhDigitsOnly
                    onEdited: value => win.port = value
                    onFocused: win.raiseKeyboard()
                }

                Label {
                    text: I18n.t("agents.transport")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Row {
                    width: parent.width
                    spacing: Theme.spaceS

                    ToggleTile {
                        width: Math.floor((parent.width - parent.spacing) / 2)
                        icon: "bolt"
                        label: I18n.t("agents.mosh")
                        active: win.transport === "mosh"
                        onTapped: win.transport = "mosh"
                    }
                    ToggleTile {
                        width: Math.floor((parent.width - parent.spacing) / 2)
                        icon: "lock"
                        label: I18n.t("agents.ssh")
                        active: win.transport === "ssh"
                        onTapped: win.transport = "ssh"
                    }
                }
                Label {
                    visible: win.errOf("transport") !== ""
                    width: parent.width
                    text: win.errOf("transport")
                    color: Theme.danger
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.Wrap
                }

                Label {
                    text: I18n.t("agents.tools")
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: win.toolOrder
                    delegate: Column {
                        required property string modelData
                        width: form.width
                        spacing: Theme.spaceXs

                        ToggleTile {
                            width: parent.width
                            icon: "bolt"
                            label: modelData === "claude" ? "Claude Code" : modelData === "codex" ? "Codex" : "Grok Build"
                            detail: I18n.t("agents.remote")
                            active: modelData === "claude" ? win.claudeOn : modelData === "codex" ? win.codexOn : win.grokOn
                            onTapped: {
                                if (modelData === "claude")
                                    win.claudeOn = !win.claudeOn;
                                else if (modelData === "codex")
                                    win.codexOn = !win.codexOn;
                                else
                                    win.grokOn = !win.grokOn;
                                win.defaultAgent = win.enabledDefault();
                            }
                        }
                        FormField {
                            visible: modelData === "claude" ? win.claudeOn : modelData === "codex" ? win.codexOn : win.grokOn
                            label: I18n.t("agents.remoteCmd")
                            text: modelData === "claude" ? win.claudeCmd : modelData === "codex" ? win.codexCmd : win.grokCmd
                            error: win.errOf("cmd." + modelData)
                            onEdited: value => {
                                if (modelData === "claude")
                                    win.claudeCmd = value;
                                else if (modelData === "codex")
                                    win.codexCmd = value;
                                else
                                    win.grokCmd = value;
                            }
                            onFocused: win.raiseKeyboard()
                        }
                    }
                }
                Label {
                    visible: win.errOf("agents") !== ""
                    width: parent.width
                    text: win.errOf("agents")
                    color: Theme.danger
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.Wrap
                }

                Label {
                    visible: win.claudeOn || win.codexOn || win.grokOn
                    text: I18n.t("agents.default")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Row {
                    visible: win.claudeOn || win.codexOn || win.grokOn
                    width: parent.width
                    spacing: Theme.spaceS

                    Repeater {
                        model: win.toolOrder
                        delegate: Pressable {
                            required property string modelData
                            visible: modelData === "claude" ? win.claudeOn : modelData === "codex" ? win.codexOn : win.grokOn
                            width: visible ? Math.floor((form.width - 2 * Theme.spaceS) / Math.max(1, (win.claudeOn ? 1 : 0) + (win.codexOn ? 1 : 0) + (win.grokOn ? 1 : 0))) : 0
                            height: Theme.touch
                            background: win.defaultAgent === modelData ? Theme.accent : Theme.surfaceAlt
                            onTapped: win.defaultAgent = modelData

                            Label {
                                anchors.centerIn: parent
                                text: modelData === "claude" ? "Claude" : modelData === "codex" ? "Codex" : "Grok"
                                color: win.defaultAgent === modelData ? Theme.accentText : Theme.text
                            }
                        }
                    }
                }
                Label {
                    visible: win.errOf("default") !== ""
                    width: parent.width
                    text: win.errOf("default")
                    color: Theme.danger
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.Wrap
                }

                ToggleTile {
                    width: parent.width
                    icon: "windows"
                    label: I18n.t("agents.tmux")
                    detail: win.tmuxOn ? I18n.t("qs.on") : I18n.t("qs.off")
                    active: win.tmuxOn
                    onTapped: win.tmuxOn = !win.tmuxOn
                }
                FormField {
                    visible: win.tmuxOn
                    label: I18n.t("agents.tmuxPrefix")
                    text: win.tmuxPrefix
                    error: win.errOf("tmux_prefix")
                    onEdited: value => win.tmuxPrefix = value
                    onFocused: win.raiseKeyboard()
                }

                Label {
                    text: I18n.t("agents.localCrush")
                    font.weight: Font.DemiBold
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: I18n.t("agents.installHint")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Pressable {
                    width: parent.width
                    height: Theme.touch
                    background: Theme.surfaceAlt
                    opacity: win.localBusy ? 0.45 : 1
                    enabled: !win.localBusy
                    onTapped: win.runLocal(win.crushInstalled ? "uninstall" : "install")

                    Label {
                        anchors.centerIn: parent
                        text: win.localBusy ? (win.crushInstalled ? I18n.t("agents.uninstalling") : I18n.t("agents.installing")) : (win.crushInstalled ? I18n.t("agents.uninstall") : I18n.t("agents.install"))
                        font.weight: Font.DemiBold
                    }
                }
                Label {
                    visible: win.crushVersion !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: I18n.t("agents.crushVersion", win.crushVersion)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Label {
                    visible: win.localActionMsg !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.localActionMsg
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Label {
                    visible: win.errOf("local.provider") !== "" || win.errOf("local.base_url") !== "" || win.errOf("local.model") !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.errOf("local.provider") || win.errOf("local.base_url") || win.errOf("local.model")
                    color: Theme.danger
                    font.pixelSize: Theme.fontSmall
                }
                Label {
                    text: I18n.t("agents.provider")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Flow {
                    width: parent.width
                    spacing: Theme.spaceS

                    Repeater {
                        model: win.localProviders
                        delegate: Pressable {
                            required property string modelData
                            width: Math.floor((form.width - 2 * Theme.spaceS) / 3)
                            height: Theme.touch
                            background: win.localProvider === modelData ? Theme.accent : Theme.surfaceAlt
                            onTapped: win.localProvider = modelData

                            Label {
                                anchors.centerIn: parent
                                text: modelData
                                color: win.localProvider === modelData ? Theme.accentText : Theme.text
                                font.pixelSize: Theme.fontSmall
                            }
                        }
                    }
                }
                FormField {
                    visible: win.needsBaseUrl
                    label: I18n.t("agents.baseUrl")
                    text: win.localBaseUrl
                    error: win.errOf("local.base_url")
                    onEdited: value => win.localBaseUrl = value
                    onFocused: win.raiseKeyboard()
                }
                FormField {
                    label: I18n.t("agents.model")
                    text: win.localModel
                    error: win.errOf("local.model")
                    onEdited: value => win.localModel = value
                    onFocused: win.raiseKeyboard()
                }
                FormField {
                    id: apiKeyField
                    visible: win.needsApiKey
                    masked: true
                    label: I18n.t("agents.apiKey")
                    onEdited: value => win.apiKeyTyped = value !== ""
                    onFocused: win.raiseKeyboard()
                }
                Label {
                    visible: win.secretSet
                    width: parent.width
                    text: I18n.t("agents.keySet", win.secretLast4)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Label {
                    visible: !win.secretSet && win.needsApiKey
                    width: parent.width
                    text: I18n.t("agents.keyUnset")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Pressable {
                    visible: win.needsApiKey
                    width: parent.width
                    height: Theme.touch
                    background: Theme.surfaceAlt
                    opacity: win.secretBusy || !win.apiKeyTyped ? 0.45 : 1
                    enabled: !win.secretBusy && win.apiKeyTyped
                    onTapped: win.saveApiKey()

                    Label {
                        anchors.centerIn: parent
                        text: win.secretBusy ? I18n.t("agents.working") : I18n.t("agents.saveKey")
                        font.weight: Font.DemiBold
                    }
                }
                Pressable {
                    visible: win.secretSet
                    width: parent.width
                    height: Theme.touch
                    background: Theme.surfaceAlt
                    opacity: win.secretBusy ? 0.45 : 1
                    enabled: !win.secretBusy
                    onTapped: win.removeApiKey()

                    Label {
                        anchors.centerIn: parent
                        text: I18n.t("agents.removeKey")
                    }
                }

                Label {
                    text: I18n.t("agents.deviceKey")
                    font.weight: Font.DemiBold
                }
                Pressable {
                    width: parent.width
                    height: Theme.touch
                    background: Theme.surfaceAlt
                    onTapped: win.createKey()

                    Label {
                        anchors.centerIn: parent
                        text: win.keyBusy ? I18n.t("agents.working") : (win.keyPresent ? I18n.t("agents.showKey") : I18n.t("agents.createKey"))
                    }
                }
                TextEdit {
                    visible: win.publicKey !== ""
                    width: parent.width
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: Theme.text
                    selectedTextColor: Theme.accentText
                    selectionColor: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    text: win.publicKey
                }
                Pressable {
                    visible: win.publicKey !== "" && win.wlCopyAvailable
                    width: parent.width
                    height: Theme.touch
                    background: Theme.surfaceAlt
                    onTapped: win.copyKey()

                    Label {
                        anchors.centerIn: parent
                        text: I18n.t("agents.copy")
                    }
                }
                Label {
                    visible: win.publicKey !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: I18n.t("agents.authorizedKeysHint")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
                Image {
                    visible: win.qrPath !== ""
                    width: Math.min(parent.width, 220)
                    height: visible ? width : 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: win.qrPath === "" ? "" : "file://" + win.qrPath
                }

                Label {
                    visible: win.checkDone
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.reachable ? I18n.t("agents.reachable") : I18n.t("agents.unreachable")
                    color: win.reachable ? Theme.ok : Theme.danger
                    font.weight: Font.DemiBold
                }
                Label {
                    visible: win.checkDone && win.checkError !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.checkError
                    color: Theme.danger
                }
                Repeater {
                    model: win.checkDone ? win.toolOrder : []
                    delegate: Label {
                        required property string modelData
                        width: form.width
                        visible: win.agentState(modelData) !== ""
                        text: (modelData === "claude" ? "Claude Code" : modelData === "codex" ? "Codex" : "Grok Build") + ": " + win.agentState(modelData)
                        color: (win.agentStatus[modelData] === "missing") ? Theme.warn : Theme.text
                    }
                }
                Label {
                    visible: win.checkDone && win.hostKeyText() !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.hostKeyText()
                    color: win.hostKey === "changed" ? Theme.danger : Theme.textDim
                }
            }
        }

        Column {
            id: footer
            x: content.pad
            width: parent.width - 2 * content.pad
            anchors.bottom: parent.bottom
            anchors.bottomMargin: content.pad
            spacing: Theme.spaceS

            Pressable {
                width: parent.width
                height: Theme.touch
                background: Theme.accent
                opacity: win.saving || !win.isDirty ? 0.45 : 1
                enabled: !win.saving && win.isDirty
                onTapped: win.save()

                Label {
                    anchors.centerIn: parent
                    text: win.saving ? I18n.t("agents.saving") : I18n.t("agents.save")
                    color: Theme.accentText
                    font.weight: Font.DemiBold
                }
            }
            Pressable {
                width: parent.width
                height: Theme.touch
                background: Theme.surfaceAlt
                opacity: win.testing ? 0.45 : 1
                enabled: !win.testing
                onTapped: win.testConn()

                Label {
                    anchors.centerIn: parent
                    text: win.testing ? I18n.t("agents.testing") : I18n.t("agents.test")
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
