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

    property bool launcherLoaded: false
    property bool quickSettingsLoaded: false
    property bool powerMenuLoaded: false
    property bool osdLoaded: false

    readonly property bool anyOpen: launcherOpen || quickSettingsOpen || powerMenuOpen

    // OSD: kind is "volume" or "brightness".
    property string osdKind: ""
    property bool osdVisible: false

    function openLauncher(): void {
        quickSettingsOpen = false;
        powerMenuOpen = false;
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
        launcherOpen = false;
        powerMenuOpen = false;
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
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuLoaded = true;
        powerMenuOpen = true;
    }

    function closeAll(): void {
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
    }

    // Home bar action: dismiss whatever is open, otherwise show the launcher.
    function home(): void {
        if (anyOpen)
            closeAll();
        else
            openLauncher();
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
