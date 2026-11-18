#!/bin/sh
# Unit tests for scripts/flo-agent-session: list parsing and the
# dropped-session notification. A fake flo-agents on PATH stands in for
# the companion CLI; no hosts or secrets are used.
set -u

root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/flo-agent-session"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

checks=0
failures=0

fail() {
	failures=$((failures + 1))
	printf 'FAIL %s\n' "$1" >&2
}

check() {
	checks=$((checks + 1))
	if [ "$1" = "$2" ]; then
		return 0
	fi
	fail "$3 (got $(printf '%s' "$1" | od -An -tx1 | tr -s ' \n' ' '); want $(printf '%s' "$2" | od -An -tx1 | tr -s ' \n' ' '))"
}

check_contains() {
	checks=$((checks + 1))
	case "$1" in
	*"$2"*) return 0 ;;
	esac
	fail "$3 (missing '$2' in: $1)"
}

check_not_contains() {
	checks=$((checks + 1))
	case "$1" in
	*"$2"*) fail "$3 (unexpected '$2' in: $1)" ;;
	esac
}

# Fake PATH: flo-agents and notify-send write to files under $work.
mkdir -p "$work/bin"
PATH="$work/bin:$PATH"
export PATH
export FLO_AGENT_IN_TERM=1
export FLO_AGENT_NOTIFY="$work/bin/notify-send"

cat > "$work/bin/flo-agents" <<'EOF'
#!/bin/sh
set -u
cmd=${1:-}
case "$cmd" in
list)
	if [ -f "${FAKE_AGENTS_LIST:-}" ]; then
		cat "$FAKE_AGENTS_LIST"
	fi
	exit "${FAKE_AGENTS_LIST_EXIT:-0}"
	;;
launch)
	printf 'launch %s\n' "${2:-}" >> "${FAKE_AGENTS_LOG:-/dev/null}"
	exit "${FAKE_AGENTS_LAUNCH_EXIT:-0}"
	;;
*)
	exit 2
	;;
esac
EOF
chmod +x "$work/bin/flo-agents"

cat > "$work/bin/notify-send" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "${FAKE_NOTIFY_OUT:-/tmp/flo-agent-notify}"
EOF
chmod +x "$work/bin/notify-send"

export FAKE_AGENTS_LOG="$work/launch.log"
export FAKE_NOTIFY_OUT="$work/notify.out"
: > "$FAKE_AGENTS_LOG"

if [ ! -x "$script" ]; then
	fail "scripts/flo-agent-session is missing or not executable"
	printf '%d checks, %d failed\n' "$checks" "$failures"
	exit 1
fi

# ---- list parsing ---------------------------------------------------------

# Missing flo-agents: empty stdout, exit 0, no stderr.
mv "$work/bin/flo-agents" "$work/bin/flo-agents.off"
out=$("$script" list 2>"$work/err")
st=$?
check "$st" "0" "list without flo-agents exits 0"
check "$out" "" "list without flo-agents prints nothing"
check "$(cat "$work/err")" "" "list without flo-agents is silent on stderr"
mv "$work/bin/flo-agents.off" "$work/bin/flo-agents"

# Empty list (configured CLI, nothing enabled).
FAKE_AGENTS_LIST="$work/empty.list"
: > "$FAKE_AGENTS_LIST"
export FAKE_AGENTS_LIST
out=$("$script" list 2>"$work/err")
st=$?
check "$st" "0" "empty list exits 0"
check "$out" "" "empty list prints nothing"
check "$(cat "$work/err")" "" "empty list is silent on stderr"

# The three known tool ids, with a blank line and trailing spaces.
printf 'claude\n\ncodex  \n grok\n' > "$work/tools.list"
FAKE_AGENTS_LIST="$work/tools.list"
export FAKE_AGENTS_LIST
out=$("$script" list 2>"$work/err")
st=$?
check "$st" "0" "configured list exits 0"
check "$out" "$(printf 'claude\tClaude Code (remote)\ncodex\tCodex (remote)\ngrok\tGrok Build (remote)')" \
	"list maps claude/codex/grok to launcher labels"
check "$(cat "$work/err")" "" "configured list is silent on stderr"

# Unsafe ids (spaces, paths) are dropped; known ids remain.
printf 'claude\nnot valid\n../x\ncodex\n' > "$work/tools.list"
out=$("$script" list 2>"$work/err")
check "$out" "$(printf 'claude\tClaude Code (remote)\ncodex\tCodex (remote)')" \
	"list drops ids that are not simple tool names"
check "$(cat "$work/err")" "" "unsafe ids are silent on stderr"

# Unknown but well-formed ids are skipped (flo-agents knows claude,
# codex, grok and crush).
printf 'claude\ngemini\ncodex\n' > "$work/tools.list"
out=$("$script" list 2>"$work/err")
check "$out" "$(printf 'claude\tClaude Code (remote)\ncodex\tCodex (remote)')" \
	"list skips unknown tool ids"
check "$(cat "$work/err")" "" "unknown ids are silent on stderr"

printf 'crush\n' > "$work/tools.list"
out=$("$script" list 2>"$work/err")
st=$?
check "$st" "0" "crush list exits 0"
check "$out" "$(printf 'crush\tCrush (local)')" "list maps crush to Crush (local)"
check_not_contains "$out" "Charm" "crush label has no Charm branding"

# list that fails (CLI present but misconfigured): still empty, no stderr.
FAKE_AGENTS_LIST_EXIT=1
export FAKE_AGENTS_LIST_EXIT
out=$("$script" list 2>"$work/err")
st=$?
check "$st" "0" "failed list exits 0"
check "$out" "" "failed list prints nothing"
check "$(cat "$work/err")" "" "failed list is silent on stderr"
unset FAKE_AGENTS_LIST_EXIT
FAKE_AGENTS_LIST_EXIT=0
export FAKE_AGENTS_LIST_EXIT

# No host/IP leaked even if the CLI printed one on stderr.
printf 'claude\n' > "$work/tools.list"
FAKE_AGENTS_LIST="$work/tools.list"
# Recreate flo-agents to echo junk on stderr for list.
cat > "$work/bin/flo-agents" <<'EOF'
#!/bin/sh
set -u
cmd=${1:-}
case "$cmd" in
list)
	printf 'debug connecting\n' >&2
	if [ -f "${FAKE_AGENTS_LIST:-}" ]; then
		cat "$FAKE_AGENTS_LIST"
	fi
	exit "${FAKE_AGENTS_LIST_EXIT:-0}"
	;;
launch)
	printf 'launch %s\n' "${2:-}" >> "${FAKE_AGENTS_LOG:-/dev/null}"
	exit "${FAKE_AGENTS_LAUNCH_EXIT:-0}"
	;;
*)
	exit 2
	;;
esac
EOF
chmod +x "$work/bin/flo-agents"
out=$("$script" list 2>"$work/err")
check "$out" "$(printf 'claude\tClaude Code (remote)')" "list still maps claude with stderr junk"
check "$(cat "$work/err")" "" "CLI stderr is not forwarded"

# ---- notification on launch ----------------------------------------------

rm -f "$FAKE_NOTIFY_OUT"
FAKE_AGENTS_LAUNCH_EXIT=0
export FAKE_AGENTS_LAUNCH_EXIT
"$script" launch claude >/dev/null 2>"$work/err"
st=$?
check "$st" "0" "launch exit 0 is preserved"
check "$(cat "$FAKE_AGENTS_LOG")" "$(printf 'launch claude\n')" "launch calls flo-agents launch claude"
if [ -f "$FAKE_NOTIFY_OUT" ]; then
	fail "exit 0 must not send a notification (got $(cat "$FAKE_NOTIFY_OUT"))"
else
	checks=$((checks + 1))
fi
check "$(cat "$work/err")" "" "successful launch is silent on stderr"

rm -f "$FAKE_NOTIFY_OUT"
: > "$FAKE_AGENTS_LOG"
FAKE_AGENTS_LAUNCH_EXIT=7
export FAKE_AGENTS_LAUNCH_EXIT
"$script" launch grok >/dev/null 2>"$work/err"
st=$?
check "$st" "7" "nonzero launch exit is preserved"
check "$(cat "$FAKE_AGENTS_LOG")" "$(printf 'launch grok\n')" "failed launch still calls flo-agents"
if [ ! -f "$FAKE_NOTIFY_OUT" ]; then
	fail "nonzero exit must send a notification"
else
	n=$(cat "$FAKE_NOTIFY_OUT")
	check_contains "$n" "Agent session dropped" "notification title"
	check_contains "$n" "Grok Build" "notification names the tool"
	check_contains "$n" "status 7" "notification names the exit code"
	check_not_contains "$n" "@" "notification has no host"
	check_not_contains "$n" "ssh" "notification has no ssh wording"
fi

rm -f "$FAKE_NOTIFY_OUT"
: > "$FAKE_AGENTS_LOG"
FAKE_AGENTS_LAUNCH_EXIT=7
export FAKE_AGENTS_LAUNCH_EXIT
"$script" launch crush >/dev/null 2>"$work/err"
st=$?
check "$st" "7" "nonzero crush launch exit is preserved"
check "$(cat "$FAKE_AGENTS_LOG")" "$(printf 'launch crush\n')" "failed crush launch still calls flo-agents"
if [ ! -f "$FAKE_NOTIFY_OUT" ]; then
	fail "nonzero crush exit must send a notification"
else
	n=$(cat "$FAKE_NOTIFY_OUT")
	check_contains "$n" "Agent session ended with error" "local crush notification title"
	check_not_contains "$n" "Agent session dropped" "crush does not use the remote drop title"
	check_contains "$n" "Crush (local)" "crush notification names Crush (local)"
	check_contains "$n" "status 7" "crush notification names the exit code"
fi

printf '%d checks, %d failed\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
