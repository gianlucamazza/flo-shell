#!/bin/sh
# Run flo-shell for development inside a nested Hyprland with one headless
# output the size of the tablet, on a private D-Bus session bus (so the
# notification server does not clash with the desktop's; the bus has no
# activatable services, so no portal or keyring daemon is started on it).
#
#   dev/run-nested.sh [portrait|landscape] [shell|greeter]
#
# Nothing here touches the real machine:
#   - power actions and display power are only logged (FLO_DRY_RUN=1);
#   - the backlight is a fake file (FLO_BACKLIGHT_DIR);
#   - the lock screen and the greeter authenticate against a fake backend
#     (FLO_AUTH=dry, secret FLO_AUTH_DRY_SECRET, default 1234). Set
#     FLO_AUTH=pam to exercise the real PamContext code path against a
#     throw-away PAM service that only knows the same test secret
#     (dev/pam-check.sh), never the real credentials. For the greeter,
#     FLO_AUTH=greetd talks to dev/fake-greetd.py over a private socket;
#   - idle locking is off (FLO_IDLE_LOCK=0);
#   - the session lock applies to the nested compositor only.
# Nothing is drawn on the host desktop: look at the result with the grim
# command printed below.
#
# FLO_NESTED_ROOT=/some/prefix/share/flo-shell runs an installed tree
# (make install DESTDIR=...) instead of the working copy.
# FLO_NESTED_CONF=classic (default) uses dev/hyprland-nested.conf, the same
# syntax as the tablet; FLO_NESTED_CONF=lua uses dev/hyprland-nested.lua.
# Requires: Hyprland, quickshell, dbus-run-session.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
mode=600x960
[ "${1:-portrait}" = landscape ] && mode=960x600
entry=shell
[ "${2:-shell}" = greeter ] && entry=greeter
conf=${FLO_NESTED_CONF:-classic}
root=${FLO_NESTED_ROOT:-$here}

run="$XDG_RUNTIME_DIR/flo-shell-dev"
mkdir -p "$run/backlight" "$run/pam" "$run/bin"
[ -f "$run/backlight/brightness" ] || echo 120 > "$run/backlight/brightness"
echo 255 > "$run/backlight/max_brightness"

secret=${FLO_AUTH_DRY_SECRET:-1234}
auth=${FLO_AUTH:-dry}

# Throw-away PAM service: asks for a password and hands it to pam-check.sh.
printf 'auth required pam_exec.so expose_authtok quiet %s/dev/pam-check.sh %s\naccount required pam_permit.so\n' \
    "$here" "$secret" > "$run/pam/flo-shell"

# Stand-in for wvkbd when it is not installed: records the signals it gets.
if ! command -v wvkbd-mobintl > /dev/null 2>&1; then
    cp "$here/dev/fake-wvkbd.sh" "$run/bin/wvkbd-mobintl"
    chmod +x "$run/bin/wvkbd-mobintl"
    PATH="$run/bin:$PATH"
fi

before=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null || true)

if [ "$conf" = lua ]; then
    hyprconf="$here/dev/hyprland-nested.lua"
else
    hyprconf="$here/dev/hyprland-nested.conf"
fi

# NO_SD_VARS keeps the nested instance from exporting its own
# WAYLAND_DISPLAY into the host's systemd/D-Bus environment.
env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD \
    HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_RT=1 \
    Hyprland -c "$hyprconf" > "$run/hyprland.log" 2>&1 &
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
if [ "$conf" = lua ]; then
    hyprctl -i "$sig" eval "hl.monitor({ output = \"FLO\", mode = \"$mode@60\", position = \"0x0\", scale = 1 })" > /dev/null
    hyprctl -i "$sig" eval 'hl.monitor({ output = "WAYLAND-1", disabled = true })' > /dev/null
else
    hyprctl -i "$sig" keyword monitor "FLO,$mode@60,0x0,1" > /dev/null
    hyprctl -i "$sig" keyword monitor "WAYLAND-1,disable" > /dev/null
fi

greetd=""
if [ "$entry" = greeter ] && [ "$auth" = greetd ]; then
    rm -f "$run/greetd.sock"
    python3 "$here/dev/fake-greetd.py" "$run/greetd.sock" "$secret" > "$run/greetd.log" 2>&1 &
    greetd=$!
    GREETD_SOCK="$run/greetd.sock"
    export GREETD_SOCK
fi

cat <<MSG
flo-shell ($entry) running nested on $sock ($mode, $conf config, auth=$auth, test secret $secret).
In another terminal:
  screenshot:  WAYLAND_DISPLAY=$sock grim /tmp/flo.png
  ipc:         WAYLAND_DISPLAY=$sock quickshell ipc -p $root/$entry call flo state
  lock:        WAYLAND_DISPLAY=$sock quickshell ipc -p $root/shell call flo lock
  type PIN:    WAYLAND_DISPLAY=$sock quickshell ipc -p $root/$entry call flo authInput $secret
  submit:      WAYLAND_DISPLAY=$sock quickshell ipc -p $root/$entry call flo authInput ENTER
  overview:    WAYLAND_DISPLAY=$sock quickshell ipc -p $root/shell call flo overview
  rotate:      WAYLAND_DISPLAY=$sock quickshell ipc -p $root/shell call flo rotate 90
  a window:    WAYLAND_DISPLAY=$sock foot
  notify:      DBUS_SESSION_BUS_ADDRESS=\$(cat $run/bus) notify-send Titolo Testo
  hyprctl:     hyprctl -i $sig monitors
Ctrl-C stops the shell and the nested compositor.
MSG

WAYLAND_DISPLAY=$sock HYPRLAND_INSTANCE_SIGNATURE=$sig QT_QPA_PLATFORM=wayland \
FLO_DRY_RUN=1 FLO_BACKLIGHT_DIR="$run/backlight" FLO_DEV_RUN="$run" \
FLO_AUTH="$auth" FLO_AUTH_DRY_SECRET="$secret" FLO_IDLE_LOCK="${FLO_IDLE_LOCK:-0}" \
FLO_PAM_CONFIG_DIR="$run/pam" FLO_STATE_DIR="$run" FLO_DEV_INPUT=1 PATH="$PATH" \
    dbus-run-session --config-file="$here/dev/dbus-session.conf" -- \
    sh -c 'echo "$DBUS_SESSION_BUS_ADDRESS" > "$FLO_DEV_RUN/bus"; echo $$ > "$FLO_DEV_RUN/shell.pid"; exec quickshell -p "$0"' "$root/$entry" &
session=$!

# Stop the shell first: dbus-run-session then takes its bus down with it.
cleanup() {
    trap - EXIT INT TERM
    [ -f "$run/shell.pid" ] && kill "$(cat "$run/shell.pid")" 2>/dev/null || true
    wait "$session" 2>/dev/null || true
    [ -n "$greetd" ] && kill "$greetd" 2>/dev/null || true
    # The stand-in keyboard does not notice that its compositor is gone.
    pkill -f "$run/bin/wvkbd-mobintl" 2>/dev/null || true
    kill "$hypr" 2>/dev/null || true
    rm -f "$run/shell.pid" "$run/bus" "$run/flo-shell.locked" "$run/greetd.sock"
}
trap cleanup EXIT INT TERM
wait "$session" || true
