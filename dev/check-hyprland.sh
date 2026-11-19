#!/bin/sh
# Validate all formats understood by the installed Hyprland, preserving errors.
set -eu
command -v Hyprland >/dev/null 2>&1 || exit 0
version=$(Hyprland --version | sed -n 's/^Hyprland \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
case "$version" in
    *.*) major=${version%%.*}; minor=${version#*.} ;;
    *) echo 'Cannot determine Hyprland version for config checks' >&2; exit 1 ;;
esac
formats=conf
if [ "$major" -gt 0 ] || [ "$minor" -ge 57 ]; then
    formats=lua
elif [ "$minor" -ge 55 ]; then
    formats='conf lua'
fi
for ext in $formats; do
    for config in session/hyprland session/greeter-hyprland; do
        Hyprland --verify-config -c "$config.$ext"
    done
done
