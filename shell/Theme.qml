pragma Singleton

import QtQuick
import Quickshell

// Single source of visual tokens. Omarchy themes will be mapped onto the
// colour block later; sizes are derived from physical units in Device.
Singleton {
    id: root

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
    readonly property int edgeTouch: 48      // height of the invisible edge strips
    readonly property int swipeThreshold: Device.mm(2.5)
    // Travel that turns a swipe up on the home bar into "overview": about 45%
    // of the panel height, so that an ordinary swipe opens the launcher
    // (28 mm turned most natural swipes into "overview" on the tablet).
    readonly property int longSwipeThreshold: Device.mm(65)
    // Travel after which a card dragged up in the overview is closed.
    readonly property int dismissThreshold: Device.mm(14)

    // Fixed chrome.
    readonly property int barHeight: 30      // visible status bar
    readonly property int homeBarHeight: 20  // visible home bar
    readonly property int sideSheetWidth: 360 // landscape quick settings
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
    readonly property int fontBar: 15
    readonly property int fontSmall: 15
    readonly property int fontBody: Math.max(16, Device.mm(2.5))
    readonly property int fontTitle: 20
    readonly property int fontDisplay: 34
    readonly property int fontClock: 64

    readonly property int radius: 14
    readonly property int iconSize: 24
    readonly property int appIconSize: 56

    // Animation (transforms and opacity only).
    readonly property int animFast: 110
    readonly property int animNormal: 180
    readonly property int animSlow: 260
    readonly property int easing: Easing.OutCubic

    // Timeouts (one-shot, armed by events).
    readonly property int osdTimeout: 1500
    readonly property int popupTimeout: 5000
    readonly property int maxPopups: 3
}
