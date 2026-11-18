#!/bin/sh
# Unit tests for scripts/flo-agent-config: argv-safe save, field errors,
# onboarding vs configured vs absent launcher entries. A fake flo-agents
# on PATH stands in for the companion CLI; no hosts, IPs or real keys.
set -u

root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/flo-agent-config"
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

check_file_contains() {
	checks=$((checks + 1))
	if grep -F -q -- "$2" "$1" 2>/dev/null; then
		return 0
	fi
	fail "$3 (missing '$2' in $1)"
}

mkdir -p "$work/bin"
PATH="$work/bin:$PATH"
export PATH
export FAKE_SET_LOG="$work/set.log"
export FAKE_ARGV_LOG="$work/argv.log"
export FAKE_CMD_LOG="$work/cmd.log"
export FAKE_CONFIG_JSON="$work/config.json"
export FAKE_LIST="$work/list.txt"
export FAKE_CHECK_JSON="$work/check.json"
export FAKE_PUBKEY="ssh-ed25519 TESTKEY flo-agents-test"
export FAKE_SET_FAIL_KEY=""
export FAKE_SET_FAIL_REASON=""
export FAKE_QR_EXIT=0
export FAKE_LOCAL_STATUS="$work/local-status.json"
export FAKE_SECRET_STDIN="$work/secret.stdin"
export FAKE_SECRET_STATE="$work/secret.state"
: > "$FAKE_SET_LOG"
: > "$FAKE_ARGV_LOG"
: > "$FAKE_CMD_LOG"
: > "$FAKE_LIST"

cat > "$work/bin/flo-agents" <<'EOF'
#!/bin/sh
set -u
printf '%s\n' "$*" >> "${FAKE_CMD_LOG:-/dev/null}"
cmd=${1:-}
case "$cmd" in
config)
	sub=${2:-}
	case "$sub" in
	get)
		if [ -f "${FAKE_CONFIG_JSON:-}" ]; then
			cat "$FAKE_CONFIG_JSON"
		else
			printf '%s\n' '{"configured":false}'
		fi
		exit 0
		;;
	set)
		key=${3:-}
		value=${4:-}
		{
			printf 'argc=%s\n' "$#"
			printf 'key=%s\n' "$key"
			printf 'value=%s\n' "$value"
			if [ "$#" -ge 5 ]; then
				printf 'extra=%s\n' "$5"
			else
				printf 'extra=UNSET\n'
			fi
		} >> "${FAKE_ARGV_LOG:-/dev/null}"
		printf '%s\t%s\n' "$key" "$value" >> "${FAKE_SET_LOG:-/dev/null}"
		if [ -n "${FAKE_SET_FAIL_KEY:-}" ] && [ "$key" = "$FAKE_SET_FAIL_KEY" ]; then
			printf '%s\n' "${FAKE_SET_FAIL_REASON:-invalid}" >&2
			exit 2
		fi
		exit 0
		;;
	*)
		exit 2
		;;
	esac
	;;
check)
	if [ -f "${FAKE_CHECK_JSON:-}" ]; then
		cat "$FAKE_CHECK_JSON"
	fi
	exit "${FAKE_CHECK_EXIT:-0}"
	;;
key)
	sub=${2:-}
	case "$sub" in
	ensure|show)
		printf '%s\n' "${FAKE_PUBKEY:-ssh-ed25519 TESTKEY flo-agents-test}"
		exit 0
		;;
	qr)
		out=${3:-}
		st=${FAKE_QR_EXIT:-0}
		if [ "$st" -eq 0 ] && [ -n "$out" ]; then
			printf 'qr\n' > "$out"
		fi
		exit "$st"
		;;
	*)
		exit 2
		;;
	esac
	;;
list)
	if [ -f "${FAKE_LIST:-}" ]; then
		cat "$FAKE_LIST"
	fi
	exit 0
	;;
local)
	sub=${2:-}
	case "$sub" in
	install)
		printf '%s\n' '{"installed":true,"version":"0.0-test","path":"/tmp/crush"}' > "${FAKE_LOCAL_STATUS:-/dev/null}"
		printf '%s\n' "installed crush 0.0-test"
		exit 0
		;;
	uninstall)
		printf '%s\n' '{"installed":false,"version":"","path":""}' > "${FAKE_LOCAL_STATUS:-/dev/null}"
		printf '%s\n' "uninstalled crush"
		exit 0
		;;
	status)
		if [ -f "${FAKE_LOCAL_STATUS:-}" ]; then
			cat "${FAKE_LOCAL_STATUS}"
		else
			printf '%s\n' '{"installed":false,"version":"","path":""}'
		fi
		exit 0
		;;
	*)
		exit 2
		;;
	esac
	;;
secret)
	sub=${2:-}
	case "$sub" in
	set)
		{
			printf 'secret_argc=%s\n' "$#"
			printf 'secret_argv=%s\n' "$*"
			i=1
			while [ "$i" -le $# ]; do
				eval "a=\$$i"
				printf 'secret_arg_%s=%s\n' "$i" "$a"
				i=$((i + 1))
			done
		} >> "${FAKE_ARGV_LOG:-/dev/null}"
		key=$(cat)
		printf '%s' "$key" > "${FAKE_SECRET_STDIN:-/dev/null}"
		leaked=0
		i=1
		while [ "$i" -le $# ]; do
			eval "a=\$$i"
			if [ -n "$key" ] && [ "$a" = "$key" ]; then
				leaked=1
			fi
			i=$((i + 1))
		done
		if [ "$leaked" -ne 0 ]; then
			printf '%s\n' "api key must not appear in argv" >&2
			exit 2
		fi
		last4=$(printf '%s' "$key" | tr -d '\n\r' | tail -c 4)
		printf 'set\n%s\n' "$last4" > "${FAKE_SECRET_STATE:-/dev/null}"
		printf 'set ••••%s\n' "$last4"
		exit 0
		;;
	status)
		if [ -f "${FAKE_SECRET_STATE:-}" ]; then
			st=$(sed -n '1p' "${FAKE_SECRET_STATE}")
			last=$(sed -n '2p' "${FAKE_SECRET_STATE}")
			if [ "$st" = "set" ]; then
				printf 'set ••••%s\n' "$last"
			else
				printf 'unset\n'
			fi
		else
			printf 'unset\n'
		fi
		exit 0
		;;
	unset)
		rm -f "${FAKE_SECRET_STATE:-}"
		printf 'unset\n'
		exit 0
		;;
	*)
		exit 2
		;;
	esac
	;;
*)
	exit 2
	;;
esac
EOF
chmod +x "$work/bin/flo-agents"

if [ ! -x "$script" ]; then
	fail "scripts/flo-agent-config is missing or not executable"
	printf '%d checks, %d failed\n' "$checks" "$failures"
	exit 1
fi

# ---- absent / unconfigured / configured launcher entries ------------------

# Missing flo-agents: empty stdout, exit 0, no stderr.
mv "$work/bin/flo-agents" "$work/bin/flo-agents.off"
out=$("$script" entries 2>"$work/err")
st=$?
check "$st" "0" "entries without flo-agents exits 0"
check "$out" "" "entries without flo-agents prints nothing"
check "$(cat "$work/err")" "" "entries without flo-agents is silent on stderr"
mv "$work/bin/flo-agents.off" "$work/bin/flo-agents"

# Present, configured=false: a single Configure agents row, nothing else.
printf '%s\n' '{"configured":false,"host":"","user":"","port":22,"transport":"mosh","agents":[],"default":"","cmd":{"claude":"claude","codex":"codex","grok":"grok"},"tmux":true,"tmux_prefix":"flo","key":{"present":false,"public":""}}' > "$FAKE_CONFIG_JSON"
: > "$FAKE_LIST"
out=$("$script" entries 2>"$work/err")
st=$?
check "$st" "0" "unconfigured entries exits 0"
check "$out" "$(printf 'settings\tConfigure agents\tsettings')" \
	"unconfigured entries is a single Configure agents row"
check "$(cat "$work/err")" "" "unconfigured entries is silent on stderr"
check_not_contains "$out" "claude" "unconfigured entries has no agent tools"
check_not_contains "$out" "Agent settings" "unconfigured entries is not Agent settings"

# Present, configured=true: M1 tool rows plus Agent settings.
printf '%s\n' '{"configured":true,"host":"host.example","user":"lab","port":22,"transport":"mosh","agents":["claude","codex"],"default":"claude","cmd":{"claude":"claude","codex":"codex","grok":"grok"},"tmux":true,"tmux_prefix":"flo","key":{"present":true,"public":"ssh-ed25519 TESTKEY flo-agents-test"}}' > "$FAKE_CONFIG_JSON"
printf 'claude\ncodex\n' > "$FAKE_LIST"
out=$("$script" entries 2>"$work/err")
st=$?
check "$st" "0" "configured entries exits 0"
check "$out" "$(printf 'claude\tClaude Code (remote)\tlaunch\ncodex\tCodex (remote)\tlaunch\nsettings\tAgent settings\tsettings')" \
	"configured entries keeps M1 tools plus Agent settings"
check "$(cat "$work/err")" "" "configured entries is silent on stderr"
check_not_contains "$out" "Configure agents" "configured entries is not onboarding"

# crush in list: labeled Crush (local), generic launcher row, not a logo name.
printf 'claude\ncrush\n' > "$FAKE_LIST"
out=$("$script" entries 2>"$work/err")
st=$?
check "$st" "0" "entries with crush exits 0"
check_contains "$out" "$(printf 'crush\tCrush (local)\tlaunch')" "crush is labeled Crush (local)"
check_not_contains "$out" "Charm" "crush label has no Charm branding"
check_not_contains "$out" "logo" "crush label has no logo wording"
printf 'claude\ncodex\n' > "$FAKE_LIST"

# ---- save sequence and argv safety ----------------------------------------

: > "$FAKE_SET_LOG"
: > "$FAKE_ARGV_LOG"
: > "$FAKE_CMD_LOG"
# Values with spaces and a semicolon must stay a single argument; later
# keys must not run if an earlier set fails.
out=$("$script" apply host "host.example" user "lab user" 2>"$work/err")
st=$?
check "$st" "0" "apply of valid fields exits 0"
check_file_contains "$FAKE_SET_LOG" "$(printf 'host\thost.example')" "apply sets host first"
check_file_contains "$FAKE_SET_LOG" "$(printf 'user\tlab user')" "apply sets user second"
# config get --json is invoked after saving (state is re-read).
check_contains "$(cat "$FAKE_CMD_LOG")" "config get --json" "apply re-reads config get --json"
# argc=4 means: config, set, key, value — no word-splitting.
# The value with a space is one argument (value=lab user, extra=UNSET).
check_contains "$(cat "$FAKE_ARGV_LOG")" "key=user" "apply recorded user key"
check_contains "$(cat "$FAKE_ARGV_LOG")" "value=lab user" "value with space stays one argument"
check_contains "$(cat "$FAKE_ARGV_LOG")" "argc=4" "config set is four argv entries"
check_contains "$(cat "$FAKE_ARGV_LOG")" "extra=UNSET" "no extra argv after the value"

: > "$FAKE_SET_LOG"
: > "$FAKE_ARGV_LOG"
: > "$FAKE_CMD_LOG"
semi='host.example; rm -rf /tmp/flo-agents-test'
out=$("$script" apply host "$semi" 2>"$work/err")
st=$?
check "$st" "0" "apply with semicolon in value exits 0"
check_contains "$(cat "$FAKE_ARGV_LOG")" "value=$semi" "semicolon stays inside one argument"
check_contains "$(cat "$FAKE_ARGV_LOG")" "extra=UNSET" "semicolon does not create extra argv"
check_contains "$(cat "$FAKE_ARGV_LOG")" "argc=4" "semicolon does not split argv"
if [ -e /tmp/flo-agents-test ]; then
	fail "semicolon in a value must not be executed (created /tmp/flo-agents-test)"
else
	checks=$((checks + 1))
fi

# Order: host, user, port, transport, agents, default, then cmds, tmux.
: > "$FAKE_SET_LOG"
: > "$FAKE_CMD_LOG"
"$script" apply host host.example user lab port 22 transport mosh agents "claude,codex" default claude \
	cmd.claude "claude --bar" cmd.codex codex cmd.grok grok tmux on tmux_prefix flo >/dev/null 2>"$work/err"
st=$?
check "$st" "0" "full apply exits 0"
order=$(cut -f1 "$FAKE_SET_LOG" | tr '\n' ' ')
check "$order" "host user port transport agents default cmd.claude cmd.codex cmd.grok tmux tmux_prefix " \
	"apply sets fields in the given order"
check_contains "$(cat "$FAKE_ARGV_LOG")" "value=claude --bar" "cmd with spaces stays one argument"

: > "$FAKE_SET_LOG"
: > "$FAKE_ARGV_LOG"
"$script" apply local.provider ollama local.base_url "http://127.0.0.1:11434" local.model llama >/dev/null 2>"$work/err"
st=$?
check "$st" "0" "apply of local.* keys exits 0"
order=$(cut -f1 "$FAKE_SET_LOG" | tr '\n' ' ')
check "$order" "local.provider local.base_url local.model " "apply sets local keys in order"
check_file_contains "$FAKE_SET_LOG" "$(printf 'local.provider\tollama')" "apply sets local.provider"
check_file_contains "$FAKE_SET_LOG" "$(printf 'local.base_url\thttp://127.0.0.1:11434')" "apply sets local.base_url"

# ---- error display data ---------------------------------------------------

: > "$FAKE_SET_LOG"
: > "$FAKE_CMD_LOG"
FAKE_SET_FAIL_KEY=port
FAKE_SET_FAIL_REASON="port must be a number"
export FAKE_SET_FAIL_KEY FAKE_SET_FAIL_REASON
out=$("$script" apply host host.example port nope user lab 2>"$work/err")
st=$?
check "$st" "2" "invalid set exits 2"
err_line=$(printf '%s\n' "$out" | head -n 1)
check "$err_line" "$(printf 'ERR\tport\tport must be a number')" \
	"stderr reason is on stdout as ERR<TAB>field<TAB>reason"
# host was applied; user must not run after the failed port.
set_keys=$(cut -f1 "$FAKE_SET_LOG" | tr '\n' ' ')
check "$set_keys" "host port " "apply stops at the failing field"
check_not_contains "$set_keys" "user" "later fields are not set after an error"
check_contains "$(cat "$FAKE_CMD_LOG")" "config get --json" "failed apply still re-reads config"
# JSON body follows the ERR line so the panel can refresh.
check_contains "$out" '"configured"' "failed apply still prints config JSON"
unset FAKE_SET_FAIL_KEY FAKE_SET_FAIL_REASON
FAKE_SET_FAIL_KEY=""
FAKE_SET_FAIL_REASON=""
export FAKE_SET_FAIL_KEY FAKE_SET_FAIL_REASON

# ---- check JSON (reachable / agents / host_key) ---------------------------

printf '%s\n' '{"reachable":true,"error":"","agents":{"claude":"present","codex":"missing"},"host_key":"new"}' > "$FAKE_CHECK_JSON"
FAKE_CHECK_EXIT=0
export FAKE_CHECK_EXIT
out=$("$script" check 2>"$work/err")
st=$?
check "$st" "0" "check exits 0 when the CLI does"
check_contains "$out" '"reachable":true' "check passes reachable"
check_contains "$out" '"claude":"present"' "check passes per-agent present"
check_contains "$out" '"codex":"missing"' "check passes per-agent missing"
check_contains "$out" '"host_key":"new"' "check passes host_key=new"

printf '%s\n' '{"reachable":false,"error":"connection timed out","agents":{},"host_key":"changed"}' > "$FAKE_CHECK_JSON"
FAKE_CHECK_EXIT=1
export FAKE_CHECK_EXIT
out=$("$script" check 2>"$work/err")
st=$?
check "$st" "1" "check preserves nonzero exit"
check_contains "$out" '"error":"connection timed out"' "check passes the error string"
check_contains "$out" '"host_key":"changed"' "check passes host_key=changed"
check_not_contains "$out" "override" "check output has no override control"

# Display strings the panel uses (no override affordance).
new_txt=$("$script" host-key-text new)
changed_txt=$("$script" host-key-text changed)
check_contains "$new_txt" "trusted on first use" "new host key text"
check_contains "$changed_txt" "changed" "changed host key text"
check_not_contains "$changed_txt" "override" "changed host key text has no override"

# ---- device key: public only, QR optional ---------------------------------

export XDG_RUNTIME_DIR="$work/run"
mkdir -p "$XDG_RUNTIME_DIR"
out=$("$script" key-ensure 2>"$work/err")
st=$?
check "$st" "0" "key-ensure exits 0"
check "$out" "ssh-ed25519 TESTKEY flo-agents-test" "key-ensure prints the public line"
check_not_contains "$out" "PRIVATE" "key-ensure never prints PRIVATE"
check_not_contains "$out" "-----" "key-ensure never prints a PEM block"

out=$("$script" key-show 2>"$work/err")
check "$out" "ssh-ed25519 TESTKEY flo-agents-test" "key-show prints the public line"

FAKE_QR_EXIT=0
export FAKE_QR_EXIT
out=$("$script" key-qr 2>"$work/err")
st=$?
check "$st" "0" "key-qr exits 0 when the CLI does"
check_contains "$out" "$XDG_RUNTIME_DIR/" "key-qr writes under XDG_RUNTIME_DIR"
[ -f "$out" ] && checks=$((checks + 1)) || fail "key-qr created the image file"

FAKE_QR_EXIT=3
export FAKE_QR_EXIT
out=$("$script" key-qr 2>"$work/err")
st=$?
check "$st" "3" "key-qr preserves exit 3 when qrencode is missing"
check "$out" "" "key-qr prints no path when qrencode is missing"

# Helper source must never copy or mention the private key path.
src=$(cat "$script")
check_not_contains "$src" "id_ed25519" "helper does not name the private key file"
check_not_contains "$src" "private_key" "helper does not mention private_key"
check_not_contains "$src" "BEGIN OPENSSH" "helper has no private key material"

# QML panel must not contain a password field; the Crush API key uses
# FormField.masked (echoMode lives in components/FormField.qml).
if grep -R -n -i -E 'PasswordField' "$root/shell/agents" "$root/shell/launcher/Agents.qml" "$root/shell/launcher/Launcher.qml" >/dev/null 2>&1; then
	fail "QML agent UI must not contain PasswordField"
else
	checks=$((checks + 1))
fi
if grep -R -n -i -E 'echoMode|password' "$root/shell/agents" "$root/shell/launcher/Agents.qml" "$root/shell/launcher/Launcher.qml" >/dev/null 2>&1; then
	fail "QML agent UI must not use echoMode or password (masked API key is FormField.masked)"
else
	checks=$((checks + 1))
fi

# ---- local crush install / secret stdin -----------------------------------

printf '%s\n' '{"installed":false,"version":"","path":""}' > "$FAKE_LOCAL_STATUS"
out=$("$script" local-status 2>"$work/err")
st=$?
check "$st" "0" "local-status exits 0"
check_contains "$out" '"installed":false' "local-status reports not installed"

out=$("$script" local-install 2>"$work/err")
st=$?
check "$st" "0" "local-install exits 0"
check_contains "$out" "installed crush" "local-install prints a result"
out=$("$script" local-status)
check_contains "$out" '"installed":true' "local-status after install is installed"
check_contains "$out" '"version":"0.0-test"' "local-status after install has version"

out=$("$script" local-uninstall 2>"$work/err")
st=$?
check "$st" "0" "local-uninstall exits 0"
out=$("$script" local-status)
check_contains "$out" '"installed":false' "local-status after uninstall is not installed"

# API key: STDIN only. Distinctive payload must appear in the stdin
# capture and never in argv / the command log.
: > "$FAKE_ARGV_LOG"
: > "$FAKE_CMD_LOG"
rm -f "$FAKE_SECRET_STDIN" "$FAKE_SECRET_STATE"
secret_val='sk-TEST-SECRET-wxyz'
printf '%s' "$secret_val" | "$script" secret-set >"$work/secret-set.out" 2>"$work/err"
st=$?
check "$st" "0" "secret-set exits 0"
check "$(cat "$FAKE_SECRET_STDIN")" "$secret_val" "secret-set delivers the key on stdin"
check_contains "$(cat "$FAKE_ARGV_LOG")" "secret_argc=3" "secret set is three argv entries (secret set api_key)"
check_contains "$(cat "$FAKE_ARGV_LOG")" "secret_argv=secret set api_key" "secret-set argv is secret set api_key"
check_contains "$(cat "$FAKE_ARGV_LOG")" "secret_arg_3=api_key" "third argv is the name api_key, not the secret"
check_not_contains "$(cat "$FAKE_ARGV_LOG")" "$secret_val" "secret value is not in argv"
check_not_contains "$(cat "$FAKE_CMD_LOG")" "$secret_val" "secret value is not in the command log"
check_contains "$(cat "$work/secret-set.out")" "wxyz" "secret-set status includes last 4"

out=$("$script" secret-status 2>"$work/err")
st=$?
check "$st" "0" "secret-status exits 0"
check_contains "$out" "set" "secret-status prints set"
check_contains "$out" "wxyz" "secret-status prints last 4"

out=$("$script" secret-unset 2>"$work/err")
st=$?
check "$st" "0" "secret-unset exits 0"
out=$("$script" secret-status)
check "$out" "unset" "secret-status after unset is unset"

src=$(cat "$script")
check_contains "$src" "exec flo-agents secret set api_key" "helper execs secret set without interpolating the key"
check_not_contains "$src" "secret set api_key \"" "helper does not pass the key as an argv string"

qml_settings="$root/shell/agents/AgentSettings.qml"
if [ -f "$qml_settings" ]; then
	qml=$(cat "$qml_settings")
	check_contains "$qml" "secret-set" "panel calls flo-agent-config secret-set"
	check_contains "$qml" "stdinEnabled" "panel sends the key on Process stdin"
	check_contains "$qml" "agents.localCrush" "panel has a Local agent (Crush) section"
	check_contains "$qml" "masked: true" "API key field is masked"
	check_contains "$qml" "apiKeyField.clear()" "API key field is cleared after save"
	check_not_contains "$qml" "property string apiKey" "key is not kept in a QML string property"
	check_not_contains "$qml" "Timer" "no polling Timer on the settings panel"
	if grep -F 'command: ["flo-agent-config", "secret-set"]' "$qml_settings" >/dev/null 2>&1; then
		checks=$((checks + 1))
	else
		fail "secret Process command must be flo-agent-config secret-set with no key argv"
	fi
else
	fail "shell/agents/AgentSettings.qml is missing"
fi
# I18n label for the section and the 28 MB install hint.
i18n=$(cat "$root/shell/I18n.qml")
check_contains "$i18n" "Local agent (Crush)" "English section title is Local agent (Crush)"
check_contains "$i18n" "28 MB" "install hint names the ~28 MB download"

# get is silent and always exits 0, even without the CLI.
mv "$work/bin/flo-agents" "$work/bin/flo-agents.off"
out=$("$script" get 2>"$work/err")
st=$?
check "$st" "0" "get without flo-agents exits 0"
check_contains "$out" '"configured":false' "get without flo-agents reports unconfigured"
check "$(cat "$work/err")" "" "get without flo-agents is silent on stderr"
mv "$work/bin/flo-agents.off" "$work/bin/flo-agents"

printf '%d checks, %d failed\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
