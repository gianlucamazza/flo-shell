pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Single source of visual tokens. Omarchy themes will be mapped onto the
// colour block later; sizes are derived from physical units in Device.
Singleton {
    id: root

    // Text size can grow without changing output scale or shrinking targets.
    readonly property real textScale: {
        const n = Number(Quickshell.env("FLO_TEXT_SCALE") || UiPreferences.textScale);
        return isFinite(n) ? Math.max(1, Math.min(1.5, n)) : 1;
    }
    readonly property bool reducedMotion: Quickshell.env("FLO_REDUCED_MOTION") === "1" || UiPreferences.reducedMotion

    // Colours (all opaque: the GPU budget does not allow blending layers).
    readonly property color bg: "#0f1115"
    readonly property color barBg: "#000000"
    readonly property color surface: "#171a20"
    readonly property color surfaceAlt: "#222630"
    readonly property color pressed: "#303644"
    readonly property color border: "#2c313c"
    readonly property color text: "#e8eaee"
    readonly property color textDim: "#9aa2af"
    readonly property color accent: "#7aa2f7"
    readonly property color accentText: "#0b0d11"
    readonly property color danger: "#f7768e"
    readonly property color ok: "#9ece6a"
    readonly property color warn: "#e0af68"

    // Spacing.
    readonly property int spaceXs: 4
    readonly property int spaceS: 8
    readonly property int spaceM: 12
    readonly property int spaceL: 16
    readonly property int spaceXl: 24

    // Touch geometry, in physical terms.
    readonly property int touchMin: Math.max(56, Device.mm(9))   // hard minimum, 9 mm
    readonly property int touch: Math.max(60, Device.mm(9.4))    // preferred target
    readonly property int edgeTouch: touchMin
    readonly property int swipeThreshold: Device.mm(2.5)
    // Travel that turns a swipe up on the home bar into "overview": about 45%
    // of the panel height, so that an ordinary swipe opens the launcher
    // (28 mm turned most natural swipes into "overview" on the tablet).
    readonly property int longSwipeThreshold: Device.mm(28)
    // Travel after which a card dragged up in the overview is closed.
    readonly property int dismissThreshold: Device.mm(14)

    // Fixed chrome.
    readonly property int barHeight: 30      // visible status bar
    readonly property int homeBarHeight: touch + 8
    readonly property int sideSheetWidth: Math.round(400 * textScale)
    readonly property int launcherColumns: Device.landscape ? 6 : 4

    // On-screen keyboard (wvkbd bridge): height it reserves, logical px.
    readonly property int keyboardHeight: 280
    readonly property int keyboardHeightLandscape: 220
    readonly property string keyboardFont: "sans-serif 16"

    // Overview. Thumbnails are window captures (hyprland-toplevel-export);
    // off, the cards show the application icon only. Off by default until
    // the capture path has been proven on the tablet's GPU driver;
    // FLO_THUMBNAILS=1 turns them on without editing this file.
    readonly property bool overviewThumbnails: (Quickshell.env("FLO_THUMBNAILS") || "") === "1"
    // Longest side of a captured thumbnail, in logical px.
    readonly property int thumbnailSize: 320

    // Lock screen / greeter pad.
    readonly property int padKeyHeight: 64
    readonly property int padMaxWidth: 340

    // Typography (body >= 2.2 mm tall glyph box).
    readonly property string fontFamily: "sans-serif"
    readonly property int fontBar: Math.round(15 * textScale)
    readonly property int fontSmall: Math.round(15 * textScale)
    readonly property int fontBody: Math.round(Math.max(16, Device.mm(2.5)) * textScale)
    readonly property int fontTitle: Math.round(20 * textScale)
    readonly property int fontDisplay: Math.round(34 * textScale)
    readonly property int fontClock: 64

    readonly property int radius: 14
    readonly property int iconSize: 24
    readonly property int appIconSize: 56

    // Animation (transforms and opacity only).
    readonly property int animFast: reducedMotion ? 0 : 110
    readonly property int animNormal: reducedMotion ? 0 : 180
    readonly property int animSlow: reducedMotion ? 0 : 260
    readonly property int easing: Easing.OutCubic

    // Timeouts (one-shot, armed by events).
    readonly property int osdTimeout: 1500
    readonly property int popupTimeout: 5000
    readonly property int maxPopups: 3
}
