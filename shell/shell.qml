import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.bar
import qs.home
import qs.launcher
import qs.quicksettings
import qs.notifications
import qs.osd
import qs.power
import qs.overview
import qs.lock

// flo-shell entry point. One process; the two bars are always present, every
// other surface is created on first use.
ShellRoot {
    id: root
    property int knownWindows: 0
    // Background app freezer: connect to flo-sessiond (no-op without it).
    Component.onCompleted: {
        Sessiond.start();
        knownWindows = Compositor.windows.length;
        if (knownWindows > 0) Ui.showApplication();
    }

    StatusBar {}
    HomeBar {}
    Home {}
    LaunchFeedback {}

    Connections {
        target: Apps
        function onLaunchRequested(name: string): void { Ui.beginLaunch(name); }
    }
    Connections {
        target: Compositor
        function onActiveWindowChanged(): void {
            if (Compositor.activeWindow && !Ui.keepHome)
                Ui.showApplication();
        }
        function onWindowsChanged(): void {
            const count = Compositor.windows.length;
            // A newly mapped app may not gain keyboard focus while Home's
            // layer is focused. Reveal it without waiting for that focus.
            if (count > root.knownWindows && !Ui.keepHome)
                Ui.showApplication();
            else if (count === 0 && Ui.launchingName === "")
                Ui.home();
            root.knownWindows = count;
        }
    }

    LazyLoader {
        active: Ui.launcherLoaded
        Launcher {}
    }
    LazyLoader {
        active: Ui.quickSettingsLoaded
        QuickSettings {}
    }
    LazyLoader {
        active: Ui.powerMenuLoaded
        PowerMenu {}
    }
    LazyLoader {
        active: Ui.overviewLoaded
        Overview {}
    }
    LazyLoader {
        active: Session.lockLoaded
        Lock {}
    }
    LazyLoader {
        active: Ui.osdLoaded
        Osd {}
    }
    LazyLoader {
        active: Notifications.popups.length > 0
        NotificationPopups {}
    }

    // Level changes (hardware volume keys, other clients, IPC) raise the OSD.
    Connections {
        target: Audio
        function onLevelChanged(): void {
            Ui.showOsd("volume");
        }
    }
    Connections {
        target: Brightness
        function onLevelChanged(): void {
            Ui.showOsd("brightness");
        }
    }

    // The adapter has no native app switcher: the shell draws the overview.
    Connections {
        target: Compositor
        function onAppSwitcherRequested(): void {
            Ui.toggleOverview();
        }
    }

    // Locking dismisses every panel and the keyboard; nothing may be left
    // open underneath for the moment the lock goes away.
    Connections {
        target: Session
        function onLockedChanged(): void {
            if (Session.locked) {
                Ui.closeAll();
                Keyboard.hide();
            }
        }
    }

    // Lock after a period without input (ext-idle-notify, event driven).
    // The compositor has no idle handling of its own (no hypridle in the
    // session): gating this monitor is all the idle inhibit IPC needs.
    IdleMonitor {
        enabled: Session.idleSeconds > 0 && !Session.idleInhibited
        timeout: Math.max(1, Session.idleSeconds)
        onIsIdleChanged: {
            if (isIdle)
                Session.idle();
        }
    }

    // `quickshell ipc -p shell call flo <function>`: for compositor key
    // bindings (volume keys, power key) and for testing.
    IpcHandler {
        target: "flo"

        function home(): void { Ui.home(); }
        function textSize(value: real): void { UiPreferences.setTextScale(value); }
        function launcher(): void { Ui.toggleLauncher(); }
        function quickSettings(): void { Ui.toggleQuickSettings(); }
        function powerMenu(): void { Ui.openPowerMenu(); }
        function closeAll(): void { Ui.closeAll(); }
        function back(): void { Ui.back(); }
        function appSwitcher(): void { Compositor.showAppSwitcher(); }
        function overview(): void { Compositor.showAppSwitcher(); }
        function lock(): void { Session.lock(); }
        // For automated tests: no idle lock or blanking while on. Does not
        // unlock a session that is already locked.
        function idleInhibit(on: bool): void { Session.idleInhibited = on; }
        // Power key: short press on release, long press while held.
        function powerKey(): void { Session.powerKey(); }
        function powerKeyLong(): void {
            if (Session.powerKeyLong())
                Ui.openPowerMenu();
        }
        // Development only, inert without FLO_DEV_INPUT=1.
        function authInput(text: string): void { Ui.devInput(text === "ENTER" ? "\n" : text); }
        function rotate(degrees: int): void { RotationLock.set(degrees); }
        function rotateNext(): void { RotationLock.next(); }
        function keyboard(action: string): void {
            if (action === "on")
                Keyboard.show();
            else if (action === "off")
                Keyboard.hide();
            else
                Keyboard.toggle();
        }
        // Launch an app by desktop id, the same way the launcher does.
        function launch(desktopId: string): string { return Apps.launchById(desktopId); }
        // Close the window at this index of Compositor.windows (tests).
        function closeWindow(index: int): void { Compositor.closeWindow(Compositor.windows[index] || null); }
        function activateWindow(index: int): void {
            const w = Compositor.windows[index];
            if (w) {
                Ui.closeAll();
                Compositor.focusWindow(w);
            }
        }
        function workspace(id: int): void { Compositor.focusWorkspace(id); }
        function volume(deltaPercent: int): void { Audio.step(deltaPercent / 100); }
        function mute(): void { Audio.toggleMute(); }
        function brightness(deltaPercent: int): void { Brightness.step(deltaPercent / 100); }
        function osd(kind: string): void { Ui.showOsd(kind); }
        function state(): string {
            return JSON.stringify({
                compositor: Compositor.backendName,
                home: Ui.homeOpen,
                launching: Ui.launchingName,
                feedback: Ui.feedback,
                textScale: Theme.textScale,
                reducedMotion: Theme.reducedMotion,
                screen: Device.screen ? Device.screen.name : "",
                windows: Compositor.windows.length,
                workspace: Compositor.activeWorkspaceId,
                landscape: Device.landscape,
                launcher: Ui.launcherOpen,
                quickSettings: Ui.quickSettingsOpen,
                powerMenu: Ui.powerMenuOpen,
                overview: Ui.overviewOpen,
                locked: Session.locked,
                displayOn: Session.displayOn,
                idleInhibited: Session.idleInhibited,
                rotation: RotationLock.degrees,
                rotationSupported: RotationLock.supported,
                keyboardAvailable: Keyboard.available,
                keyboard: Keyboard.visible,
                lang: I18n.lang,
                notifications: Notifications.count,
                popups: Notifications.popups.length,
                volume: Math.round(Audio.volume * 100),
                brightness: Math.round(Brightness.value * 100),
                brightnessMethod: Brightness.method,
                network: Network.active.kind,
                battery: Battery.percent,
                appScopes: Apps.scoped,
                sessiond: {
                    connected: Sessiond.connected,
                    policy: Sessiond.policy,
                    foreground: Sessiond.foregroundUnit
                }
            });
        }
    }
}
