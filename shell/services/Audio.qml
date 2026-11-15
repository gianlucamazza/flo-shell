pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default output volume through PipeWire. Hardware volume keys are expected
// to change the sink volume (compositor binding or the `flo volume` IPC
// call); the resulting PipeWire event is what raises the OSD.
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool available: sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available ? sink.audio.muted : false

    // Emitted when the level changes after the initial state was read.
    signal levelChanged

    property real _lastVolume: -1
    property bool _lastMuted: false

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    onAvailableChanged: _lastVolume = -1
    onVolumeChanged: _notify()
    onMutedChanged: _notify()

    function _notify(): void {
        if (!available)
            return;
        const first = _lastVolume < 0;
        const changed = Math.abs(volume - _lastVolume) > 0.004 || muted !== _lastMuted;
        _lastVolume = volume;
        _lastMuted = muted;
        if (!first && changed)
            root.levelChanged();
    }

    function setVolume(v: real): void {
        if (!available)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }
    function step(delta: real): void {
        setVolume(volume + delta);
    }
    function toggleMute(): void {
        if (available)
            sink.audio.muted = !sink.audio.muted;
    }
}
