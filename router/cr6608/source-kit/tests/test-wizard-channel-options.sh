#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"

fail() {
	printf 'wizard_channel_options=fail: %s\n' "$*" >&2
	exit 1
}

[ -s "$DASHCTL" ] || fail 'dashctl source is missing'
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-wizard-channels.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
mkdir -p "$BIN"

sed -n '/^wireless_frequency_mhz_from_pairs() {/,/^valid_text_field() {/p' "$DASHCTL" |
	sed '$d' >"$TMP/functions.sh"
sh -n "$TMP/functions.sh" || fail 'extracted channel helper syntax failed'
. "$TMP/functions.sh"

grep -Fq 'ubus() { cr6608_ubus "$@"' "$DASHCTL" ||
	fail 'fast native-timeout ubus wrapper is absent'
! grep -Fq 'ubus() { run_limit' "$DASHCTL" ||
	fail 'ubus reads still use the one-second polling path'

cat >"$BIN/jsonfilter" <<'EOF'
#!/bin/sh
payload="$(sed -n '1p')"
printf 'call\n' >>"$CR6608_JSONFILTER_CALLS"
case "$*:$payload" in
	*restricted=false*:*radio0*)
		printf '%s\n' 11 2462 1 2412 6 2437 14 2484
		;;
	*disabled=true*:*radio0*)
		printf '%s\n' 6
		;;
	*restricted=false*:*radio1*)
		printf '%s\n' 149 5745 52 5260 36 5180 40 5200 200 6000
		;;
	*disabled=true*:*radio1*)
		printf '%s\n' 40
		;;
	*) exit 1 ;;
esac
EOF
chmod 0700 "$BIN/jsonfilter"
: >"$TMP/calls"

PATH="$BIN:$PATH"
export PATH
CR6608_JSONFILTER_CALLS="$TMP/calls"
export CR6608_JSONFILTER_CALLS

wireless_frequency_options 2g 'radio0 fixture'
expected24='auto:Automatic,1:1 · 2412 MHz · Enabled,11:11 · 2462 MHz · Enabled'
[ "$WIRELESS_CHANNEL_OPTIONS" = "$expected24" ] ||
	fail "2.4G output/order mismatch: $WIRELESS_CHANNEL_OPTIONS"

wireless_frequency_options 5g 'radio1 fixture'
expected5='auto:Automatic,36:36 · 5180 MHz · non-DFS · Enabled,52:52 · 5260 MHz · DFS · Enabled,149:149 · 5745 MHz · non-DFS · Enabled'
[ "$WIRELESS_CHANNEL_OPTIONS" = "$expected5" ] ||
	fail "5G output/order/DFS mismatch: $WIRELESS_CHANNEL_OPTIONS"

[ "$(wc -l <"$TMP/calls" | tr -d ' ')" = 4 ] ||
	fail 'channel tables were parsed more than twice per radio'
case "$WIRELESS_CHANNEL_OPTIONS" in
	*40:*|*200:*) fail 'disabled or out-of-whitelist channel survived' ;;
esac

printf 'wizard_channel_options=pass\n'
