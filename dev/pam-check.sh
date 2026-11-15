#!/bin/sh
# Test-only PAM helper for dev/run-nested.sh (pam_exec, expose_authtok):
# succeeds when the password read from stdin equals the first argument.
# It never sees or checks real credentials.
IFS= read -r given || true
# pam_exec passes the token NUL-terminated; the shell drops the NUL.
[ "$given" = "$1" ]
