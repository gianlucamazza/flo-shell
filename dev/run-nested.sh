#!/bin/sh
# Run flo-shell for development inside a nested Hyprland with one headless
# output the size of the tablet, on a private D-Bus session bus (so the
# notification server does not clash with the desktop's; the bus has no
# activatable services, so no portal or keyring daemon is started on it).
#
#   dev/run-nested.sh [portrait|landscape]
#
# Power actions are logged instead of executed (FLO_DRY_RUN=1) and the
# backlight is a fake file (FLO_BACKLIGHT_DIR). Nothing is drawn on the
# host desktop: look at the result with the grim command printed below.
# Requires: Hyprland (Lua configuration), quickshell, dbus-run-session.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
mode=600x960
[ "${1:-portrait}" = landscape ] && mode=960x600

run="$XDG_RUNTIME_DIR/flo-shell-dev"
mkdir -p "$run/backlight"
[ -f "$run/backlight/brightness" ] || echo 120 > "$run/backlight/brightness"
echo 255 > "$run/backlight/max_brightness"

before=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null || true)

# NO_SD_VARS keeps the nested instance from exporting its own
# WAYLAND_DISPLAY into the host's systemd/D-Bus environment.
env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD \
    HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_RT=1 \
    Hyprland -c "$here/dev/hyprland-nested.lua" > "$run/hyprland.log" 2>&1 &
hypr=$!
trap 'kill "$hypr" 2>/dev/null || true' EXIT INT TERM

sig=""
i=0
while [ -z "$sig" ] && [ "$i" -lt 100 ]; do
    for dir in "$XDG_RUNTIME_DIR"/hypr/*; do
        name=$(basename "$dir")
        case "$before" in *"$name"*) continue ;; esac
        [ -S "$dir/.socket.sock" ] && sig=$name
    done
    i=$((i + 1))
    sleep 0.1
done
[ -n "$sig" ] || { echo "nested Hyprland did not start, see $run/hyprland.log" >&2; exit 1; }

sock=""
i=0
while [ -z "$sock" ] && [ "$i" -lt 50 ]; do
    sock=$(hyprctl instances | awk -v sig="$sig" '$1 == "instance" { cur = $2 } cur == sig ":" && /wl socket/ { print $3 }')
    i=$((i + 1))
    [ -n "$sock" ] || sleep 0.1
done
[ -n "$sock" ] || { echo "cannot find the nested Wayland socket" >&2; exit 1; }

# Replace the nested window by a headless output of the tablet's size.
hyprctl -i "$sig" output create headless FLO > /dev/null
sleep 0.5
hyprctl -i "$sig" eval "hl.monitor({ output = \"FLO\", mode = \"$mode@60\", position = \"0x0\", scale = 1 })" > /dev/null
hyprctl -i "$sig" eval 'hl.monitor({ output = "WAYLAND-1", disabled = true })' > /dev/null

cat <<MSG
flo-shell running nested on $sock ($mode). In another terminal:
  screenshot:  WAYLAND_DISPLAY=$sock grim /tmp/flo.png
  ipc:         WAYLAND_DISPLAY=$sock quickshell ipc -p $here/shell call flo launcher
  notify:      DBUS_SESSION_BUS_ADDRESS=\$(cat $run/bus) notify-send Titolo Testo
  rotate:      hyprctl -i $sig eval 'hl.monitor({ output = "FLO", mode = "960x600@60", position = "0x0", scale = 1 })'
Ctrl-C stops the shell and the nested compositor.
MSG

WAYLAND_DISPLAY=$sock HYPRLAND_INSTANCE_SIGNATURE=$sig QT_QPA_PLATFORM=wayland \
FLO_DRY_RUN=1 FLO_BACKLIGHT_DIR="$run/backlight" FLO_DEV_RUN="$run" \
    dbus-run-session --config-file="$here/dev/dbus-session.conf" -- \
    sh -c 'echo "$DBUS_SESSION_BUS_ADDRESS" > "$FLO_DEV_RUN/bus"; echo $$ > "$FLO_DEV_RUN/shell.pid"; exec quickshell -p "$0/shell"' "$here" &
session=$!

# Stop the shell first: dbus-run-session then takes its bus down with it.
cleanup() {
    trap - EXIT INT TERM
    [ -f "$run/shell.pid" ] && kill "$(cat "$run/shell.pid")" 2>/dev/null || true
    wait "$session" 2>/dev/null || true
    kill "$hypr" 2>/dev/null || true
    rm -f "$run/shell.pid" "$run/bus"
}
trap cleanup EXIT INT TERM
wait "$session" || true
