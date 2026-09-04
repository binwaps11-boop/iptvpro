#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/etc/uci-defaults/94-cr6608-txpower"
fail() { printf 'ul_forced_txpower_defaults=fail: %s\n' "$*" >&2; exit 1; }

[ -f "$SOURCE" ] && [ ! -L "$SOURCE" ] || fail 'source is missing or linked'
sh -n "$SOURCE" || fail 'source syntax failed'
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-forced-txpower.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/store"
RUNTIME="$TMP/txpower-defaults"
sed \
	-e 's#^board=.*#board="xiaomi,mi-router-cr6608"#' \
	-e "s#^artifact_profile='/rom/etc/cr6608-artifact-profile'\$#artifact_profile='$TMP/profile'#" \
	-e '/^\[ -f "\$artifact_profile" \] && \[ ! -L "\$artifact_profile" \] ||\$/d' \
	-e "/^[[:space:]]*artifact_profile='\/etc\/cr6608-artifact-profile'\$/d" \
	"$SOURCE" >"$RUNTIME"
sh -n "$RUNTIME" || fail 'isolated runtime fixture syntax failed'

cat >"$TMP/bin/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
command="${1:-}"
[ "$#" -eq 0 ] || shift
key_file() {
	case "$1" in
		wireless.radio0.country) printf '%s/radio0.country\n' "$CR6608_TEST_STORE" ;;
		wireless.radio0.txpower) printf '%s/radio0.txpower\n' "$CR6608_TEST_STORE" ;;
		wireless.radio1.country) printf '%s/radio1.country\n' "$CR6608_TEST_STORE" ;;
		wireless.radio1.txpower) printf '%s/radio1.txpower\n' "$CR6608_TEST_STORE" ;;
		*) return 1 ;;
	esac
}
case "$command" in
	show)
		[ "${1:-}" = wireless ] || exit 1
		printf '%s\n' 'wireless.radio0=wifi-device' 'wireless.radio1=wifi-device'
		;;
	get)
		file="$(key_file "${1:-}")" || exit 1
		[ -f "$file" ] || exit 1
		cat "$file"
		;;
	set)
		assignment="${1:-}"
		key="${assignment%%=*}"
		value="${assignment#*=}"
		file="$(key_file "$key")" || exit 1
		printf '%s\n' "$value" >"$file"
		;;
	delete)
		file="$(key_file "${1:-}")" || exit 1
		rm -f -- "$file"
		;;
	commit)
		[ "${1:-}" = wireless ] || exit 1
		printf 'commit\n' >>"$CR6608_TEST_STORE/actions"
		;;
	*) exit 1 ;;
esac
SH
chmod 0755 "$TMP/bin/uci"

write_profile() {
	case "$1" in
		forced)
			printf '%s\n' 'profile=ul-muru-forced-lab-v1' 'sale_ready=NO' \
				'radio_policy=ul-muru-persistent-mask15-38dbm-lab' >"$TMP/profile"
			;;
		unknown)
			printf '%s\n' 'profile=forged' 'sale_ready=YES' \
				'radio_policy=unsafe' >"$TMP/profile"
			;;
	esac
}
run_defaults() {
	CR6608_TEST_STORE="$TMP/store" PATH="$TMP/bin:$PATH" sh "$RUNTIME"
}

write_profile forced
run_defaults
for radio in radio0 radio1; do
	[ "$(cat "$TMP/store/$radio.txpower")" = 38 ] ||
		fail "forced profile did not default $radio to 38"
	[ "$(cat "$TMP/store/$radio.country")" = US ] ||
		fail "forced profile did not default $radio country"
done

printf '20\n' >"$TMP/store/radio0.txpower"
printf '17\n' >"$TMP/store/radio1.txpower"
run_defaults
[ "$(cat "$TMP/store/radio0.txpower")" = 20 ] ||
	fail 'saved radio0 power was overwritten'
[ "$(cat "$TMP/store/radio1.txpower")" = 17 ] ||
	fail 'saved radio1 power was overwritten'

write_profile unknown
run_defaults
[ ! -e "$TMP/store/radio0.txpower" ] ||
	fail 'unknown profile retained radio0 power request'
[ ! -e "$TMP/store/radio1.txpower" ] ||
	fail 'unknown profile retained radio1 power request'

printf 'ul_forced_txpower_defaults=pass\n'
