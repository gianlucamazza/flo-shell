import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.bar
import qs.home
import qs.launcher
import qs.quicksettings
import qs.notifications
import qs.osd
import qs.power

// flo-shell entry point. One process; the two bars are always present, every
// other surface is created on first use.
ShellRoot {
    StatusBar {}
    HomeBar {}

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

    // `quickshell ipc -p shell call flo <function>`: for compositor key
    // bindings (volume keys, power key) and for testing.
    IpcHandler {
        target: "flo"

        function home(): void { Ui.home(); }
        function launcher(): void { Ui.toggleLauncher(); }
        function quickSettings(): void { Ui.toggleQuickSettings(); }
        function powerMenu(): void { Ui.openPowerMenu(); }
        function closeAll(): void { Ui.closeAll(); }
        function back(): void { Compositor.goBack(); }
        function appSwitcher(): void { Compositor.showAppSwitcher(); }
        function workspace(id: int): void { Compositor.focusWorkspace(id); }
        function volume(deltaPercent: int): void { Audio.step(deltaPercent / 100); }
        function mute(): void { Audio.toggleMute(); }
        function brightness(deltaPercent: int): void { Brightness.step(deltaPercent / 100); }
        function osd(kind: string): void { Ui.showOsd(kind); }
        function state(): string {
            return JSON.stringify({
                compositor: Compositor.backendName,
                windows: Compositor.windows.length,
                workspace: Compositor.activeWorkspaceId,
                landscape: Device.landscape,
                launcher: Ui.launcherOpen,
                quickSettings: Ui.quickSettingsOpen,
                powerMenu: Ui.powerMenuOpen,
                notifications: Notifications.count,
                popups: Notifications.popups.length,
                volume: Math.round(Audio.volume * 100),
                brightness: Math.round(Brightness.value * 100),
                brightnessMethod: Brightness.method,
                network: Network.active.kind,
                battery: Battery.percent
            });
        }
    }
}
