pragma Singleton

import QtQuick
import Quickshell
import qs

// Shell-wide UI state. Panels are created lazily: the *Loaded flags flip on
// first use and stay set so that reopening is instant.
Singleton {
    id: root

    property bool launcherOpen: false
    property bool quickSettingsOpen: false
    property bool powerMenuOpen: false
    property bool overviewOpen: false
    property bool agentSettingsOpen: false

    property bool launcherLoaded: false
    property bool quickSettingsLoaded: false
    property bool powerMenuLoaded: false
    property bool osdLoaded: false
    property bool overviewLoaded: false
    property bool agentSettingsLoaded: false

    readonly property bool anyOpen: launcherOpen || quickSettingsOpen || powerMenuOpen || overviewOpen || agentSettingsOpen

    // OSD: kind is "volume" or "brightness".
    property string osdKind: ""
    property bool osdVisible: false

    function openLauncher(): void {
        overviewOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
        agentSettingsOpen = false;
        launcherLoaded = true;
        launcherOpen = true;
    }
    function toggleLauncher(): void {
        if (launcherOpen)
            launcherOpen = false;
        else
            openLauncher();
    }

    function openQuickSettings(): void {
        overviewOpen = false;
        launcherOpen = false;
        powerMenuOpen = false;
        agentSettingsOpen = false;
        osdVisible = false;
        quickSettingsLoaded = true;
        quickSettingsOpen = true;
    }
    function toggleQuickSettings(): void {
        if (quickSettingsOpen)
            quickSettingsOpen = false;
        else
            openQuickSettings();
    }

    function openPowerMenu(): void {
        overviewOpen = false;
        launcherOpen = false;
        quickSettingsOpen = false;
        agentSettingsOpen = false;
        powerMenuLoaded = true;
        powerMenuOpen = true;
    }

    function openOverview(): void {
        // With nothing open the overview would be an empty page: show the
        // launcher instead, which is what the gesture is for in that case.
        if (Compositor.windows.length === 0) {
            openLauncher();
            return;
        }
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
        agentSettingsOpen = false;
        overviewLoaded = true;
        overviewOpen = true;
    }
    function toggleOverview(): void {
        if (overviewOpen)
            overviewOpen = false;
        else
            openOverview();
    }

    function openAgentSettings(): void {
        overviewOpen = false;
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
        agentSettingsLoaded = true;
        agentSettingsOpen = true;
    }

    function closeAll(): void {
        overviewOpen = false;
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
        agentSettingsOpen = false;
    }

    // Home bar action: dismiss whatever is open, otherwise show the launcher.
    function home(): void {
        if (anyOpen)
            closeAll();
        else
            openLauncher();
    }

    // Development only: text for the lock pad, see lock/AuthPad.qml.
    signal devInput(string text)

    // Back: dismiss a shell panel first, otherwise ask the application.
    function back(): void {
        if (anyOpen)
            closeAll();
        else
            Compositor.goBack();
    }

    function showOsd(kind: string): void {
        // The quick settings sliders already show the level.
        if (quickSettingsOpen)
            return;
        osdKind = kind;
        osdLoaded = true;
        osdVisible = true;
        osdTimer.restart();
    }

    // One-shot hide timeout, armed only by showOsd(). Not a polling timer.
    Timer {
        id: osdTimer
        interval: Theme.osdTimeout
        onTriggered: root.osdVisible = false
    }
}
