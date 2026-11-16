pragma Singleton

import QtQuick
import Quickshell
import qs

// Shell-wide UI state. Panels are created lazily: the *Loaded flags flip on
// first use and stay set so that reopening is instant.
Singleton {
    id: root

    property bool homeOpen: true
    property string launchingName: ""
    property string feedback: ""

    function showApplication(): void {
        homeOpen = false;
        launchingName = "";
        feedback = "";
        launchTimer.stop();
        feedbackTimer.stop();
    }
    function beginLaunch(name: string): void {
        closeAll();
        homeOpen = false;
        launchingName = name;
        feedback = I18n.t("home.starting", name);
        launchTimer.restart();
    }
    Timer {
        id: launchTimer
        interval: 20000
        onTriggered: {
            root.launchingName = "";
            root.feedback = I18n.t("home.slowLaunch");
            feedbackTimer.restart();
        }
    }
    Timer {
        id: feedbackTimer
        interval: 8000
        onTriggered: root.feedback = ""
    }

    property bool launcherOpen: false
    property bool quickSettingsOpen: false
    property bool powerMenuOpen: false
    property bool overviewOpen: false

    property bool launcherLoaded: false
    property bool quickSettingsLoaded: false
    property bool powerMenuLoaded: false
    property bool osdLoaded: false
    property bool overviewLoaded: false

    readonly property bool anyOpen: launcherOpen || quickSettingsOpen || powerMenuOpen || overviewOpen

    // OSD: kind is "volume" or "brightness".
    property string osdKind: ""
    property bool osdVisible: false

    function openLauncher(): void {
        overviewOpen = false;
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
        overviewOpen = false;
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
        overviewOpen = false;
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuLoaded = true;
        powerMenuOpen = true;
    }

    function openOverview(): void {
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
        overviewLoaded = true;
        overviewOpen = true;
    }
    function toggleOverview(): void {
        if (overviewOpen)
            overviewOpen = false;
        else
            openOverview();
    }

    function closeAll(): void {
        overviewOpen = false;
        launcherOpen = false;
        quickSettingsOpen = false;
        powerMenuOpen = false;
    }

    // Home always returns to the same surface, preserving running apps.
    function home(): void {
        closeAll();
        launchingName = "";
        feedback = "";
        launchTimer.stop();
        feedbackTimer.stop();
        homeOpen = true;
        Keyboard.hide();
    }

    // Development only: text for the lock pad, see lock/AuthPad.qml.
    signal devInput(string text)

    // Back: dismiss a shell panel first, otherwise ask the application.
    function back(): void {
        if (anyOpen)
            closeAll();
        else if (!homeOpen)
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
