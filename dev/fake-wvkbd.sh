#!/bin/sh
# Stand-in for wvkbd-mobintl on machines where it is not installed. It draws
# nothing: it only logs its arguments and the show/hide signals it receives
# (SIGUSR1 = hide, SIGUSR2 = show, as in wvkbd 0.21), so that the bridge in
# shell/services/Keyboard.qml can be exercised.
log="${FLO_DEV_RUN:-/tmp}/wvkbd.log"
echo "start $*" >> "$log"
child=""
trap 'echo hide >> "$log"' USR1
trap 'echo show >> "$log"' USR2
trap 'echo stop >> "$log"; [ -n "$child" ] && kill "$child" 2>/dev/null; exit 0' TERM INT
while :; do
    sleep 3600 &
    child=$!
    wait "$child"
    kill "$child" 2>/dev/null
done
