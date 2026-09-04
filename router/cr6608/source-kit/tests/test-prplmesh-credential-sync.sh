#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
SYNC="${ROOT}/packages/prplmesh/files/usr/sbin/cr6608-prplmesh-sync"
PACKAGE="${ROOT}/packages/prplmesh/Makefile"
QUICK="${ROOT}/files/usr/sbin/cr6608-quicksettings-apply"
QUICK_CGI="${ROOT}/files/www/cgi-bin/cr6608-quick-apply"
ACL="${ROOT}/files/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json"
SAFE_APPLY="${ROOT}/files/usr/sbin/cr6608-safe-apply"
DASHCTL="${ROOT}/files/www/cgi-bin/dashctl"
RETAIL="${ROOT}/files/usr/sbin/cr6608-retail-provision"
PYTHON_BIN="${PYTHON_BIN:-python3}"

fail() {
	printf 'prplmesh credential sync contract failed: %s\n' "$*" >&2
	exit 1
}

word_list_has() {
	_wlh_words="$1"
	_wlh_wanted="$2"
	for _wlh_word in $_wlh_words; do
		[ "$_wlh_word" != "$_wlh_wanted" ] || return 0
	done
	return 1
}

assignment_words() {
	_aw_file="$1"
	_aw_name="$2"
	_aw_value="$(sed -n "s/^${_aw_name}=//p" "$_aw_file" | sed -n '1p')"
	case "$_aw_value" in
		\'*\') _aw_value="${_aw_value#\'}"; _aw_value="${_aw_value%\'}" ;;
		\"*\") _aw_value="${_aw_value#\"}"; _aw_value="${_aw_value%\"}" ;;
		*) return 1 ;;
	esac
	[ -n "$_aw_value" ] || return 1
	printf '%s\n' "$_aw_value"
}

assert_assignment_member() {
	_aam_file="$1"
	_aam_name="$2"
	_aam_member="$3"
	_aam_words="$(assignment_words "$_aam_file" "$_aam_name")" ||
		fail "missing quoted $_aam_name assignment in $_aam_file"
	word_list_has "$_aam_words" "$_aam_member" ||
		fail "$_aam_name omits $_aam_member in $_aam_file"
}

block_line() {
	printf '%s\n' "$1" | grep -nF -- "$2" | sed -n '1s/:.*//p'
}

assert_block_order() {
	_abo_label="$1"
	_abo_block="$2"
	shift 2
	_abo_previous=0
	for _abo_pattern in "$@"; do
		_abo_line="$(block_line "$_abo_block" "$_abo_pattern")"
		[ -n "$_abo_line" ] || fail "$_abo_label lacks ordered step: $_abo_pattern"
		[ "$_abo_line" -gt "$_abo_previous" ] ||
			fail "$_abo_label has an out-of-order step: $_abo_pattern"
		_abo_previous="$_abo_line"
	done
}

command_member_line() {
	printf '%s\n' "$1" | awk -v command="$2" -v member="$3" '
		index($0, command) {
			rest = substr($0, index($0, command) + length(command))
			count = split(rest, words, /[[:space:]]+/)
			for (i = 1; i <= count; i++) {
				if (words[i] == "||" || words[i] == ";") break
				if (words[i] == member) { print NR; exit }
			}
		}
	'
}

assert_royal_sync_order() {
	_arso_label="$1"
	_arso_block="$2"
	_arso_stage="$(block_line "$_arso_block" 'dashctl_prplmesh_stage "$ifc24" "$ifc5"')"
	_arso_commit="$(command_member_line "$_arso_block" royal_commit_packages prplmesh)"
	_arso_runtime="$(block_line "$_arso_block" 'royal_apply_services')"
	_arso_verify="$(block_line "$_arso_block" 'dashctl_prplmesh_verify')"
	[ -n "$_arso_stage" ] && [ -n "$_arso_commit" ] &&
		[ -n "$_arso_runtime" ] && [ -n "$_arso_verify" ] ||
		fail "$_arso_label lacks a stage/commit/runtime/verify step"
	[ "$_arso_stage" -lt "$_arso_commit" ] &&
		[ "$_arso_commit" -lt "$_arso_runtime" ] &&
		[ "$_arso_runtime" -lt "$_arso_verify" ] ||
		fail "$_arso_label sync is outside stage/commit/runtime/verify order"
}

for path in "$SYNC" "$PACKAGE" "$QUICK" "$QUICK_CGI" "$ACL" \
	"$SAFE_APPLY" "$DASHCTL" "$RETAIL"; do
	[ -s "$path" ] || fail "missing $path"
done
[ -x "$(command -v "$PYTHON_BIN" 2>/dev/null)" ] || fail "missing $PYTHON_BIN"

# The helper is packaged as an executable, stages only credential mirrors and
# neither commits nor changes prplMesh/EasyMesh service state by itself.
grep -Fq './files/usr/sbin/cr6608-prplmesh-sync $(1)/usr/sbin/cr6608-prplmesh-sync' \
	"$PACKAGE" || fail 'sync helper is not installed by the prplmesh package'
! grep -Fq 'commit prplmesh' "$SYNC" || fail 'helper commits outside its caller transaction'
! grep -Fq '/etc/init.d/prplmesh' "$SYNC" || fail 'helper controls the prplmesh service'
grep -Fq 'gates_closed || fail easymesh_gate_open' "$SYNC" || \
	fail 'helper does not require closed EasyMesh gates before staging'
grep -Fq 'gates_closed || fail easymesh_gate_changed' "$SYNC" || \
	fail 'helper does not verify closed EasyMesh gates after staging'
grep -Fq "case \"\$value\" in *'#'*|*\"\$CR_CHAR\"*|*\"\$NL_CHAR\"*) return 1 ;; esac" \
	"$SYNC" || fail 'batch fields do not reject comment/CR/LF injection bytes explicitly'

# All front ends and rollback guards treat prplmesh as a member of the same UCI
# transaction. Parse membership rather than depending on package ordering.
assert_assignment_member "$QUICK" UCI_PACKAGES prplmesh
assert_assignment_member "$QUICK_CGI" WRITE_PACKAGES prplmesh
assert_assignment_member "$DASHCTL" DASHCTL_TRANSACTION_UCI_PACKAGES prplmesh
grep -A16 -F 'ubus_root_with_write_acl() {' "$QUICK_CGI" |
	grep -Fq 'for package in $WRITE_PACKAGES; do' ||
	fail 'Quick CGI authentication does not check every transactional package'
[ "$(grep -Fc 'for package in $WRITE_PACKAGES; do' "$QUICK_CGI")" -ge 2 ] ||
	fail 'Quick CGI does not revert every authenticated LuCI package before apply'
"$PYTHON_BIN" -I -B - "$ACL" <<'PY' || fail 'LuCI ACL omits prplmesh read/write access'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
grant = document.get("luci-app-cr6608-quicksettings", {})
for mode in ("read", "write"):
    packages = grant.get(mode, {}).get("uci")
    if not isinstance(packages, list) or "prplmesh" not in packages:
        raise SystemExit(1)
PY
safe_restore_block="$(sed -n '/^restore_loaded() {/,/^}/p' "$SAFE_APPLY")"
safe_revert_words="$(printf '%s\n' "$safe_restore_block" |
	sed -n 's/^[[:space:]]*for pkg in \(.*\); do$/\1/p' | sed -n '1p')"
word_list_has "$safe_revert_words" prplmesh ||
	fail 'persistent Safe Apply rollback does not revert prplmesh staging'

# Callers pass AP section names only; the helper reads secrets directly from
# UCI and never receives SSIDs or keys in argv.
grep -Fq '"$PRPLMESH_SYNC_BIN" "$action" "$radio0_ap" "$radio1_ap"' "$QUICK" || \
	fail 'Quick Settings does not pass section-only sync arguments'
! grep -Fq '/etc/init.d/prplmesh' "$DASHCTL" || \
	fail 'Smart dashboard controls the gated prplmesh service during credential sync'
quick_stage_line="$(grep -nF '! sync_prplmesh_credentials --stage "$ap24" "$ap5"; then' "$QUICK" | head -n1 | cut -d: -f1)"
quick_commit_line="$(grep -nF 'if ! uci commit "$pkg"; then' "$QUICK" | tail -n1 | cut -d: -f1)"
quick_runtime_line="$(grep -nF '"$CR6608_SBIN_DIR/cr6608-safe-wifi-reload" 8 "$wireless_backup"' "$QUICK" | tail -n1 | cut -d: -f1)"
quick_verify_line="$(grep -nF '! sync_prplmesh_credentials --verify "$ap24" "$ap5"; then' "$QUICK" | head -n1 | cut -d: -f1)"
[ -n "$quick_stage_line" ] && [ -n "$quick_commit_line" ] &&
	[ -n "$quick_runtime_line" ] && [ -n "$quick_verify_line" ] &&
	[ "$quick_stage_line" -lt "$quick_commit_line" ] &&
	[ "$quick_commit_line" -lt "$quick_runtime_line" ] &&
	[ "$quick_runtime_line" -lt "$quick_verify_line" ] ||
	fail 'Quick Settings sync is outside stage/commit/runtime verification order'

grep -Fq 'cp -p "$PRPLMESH_CONFIG" "$backup/prplmesh" || fail prplmesh_backup' "$RETAIL" &&
	grep -Fq 'cp -pf "$backup/prplmesh" "$PRPLMESH_CONFIG" || restore_rc=1' "$RETAIL" &&
	grep -Fq 'for package in wireless cr6608quick smartap uhttpd rpcd system prplmesh dropbear; do' "$RETAIL" ||
	fail 'Retail rollback does not restore and revert prplmesh'
retail_stage_line="$(grep -nF '"$PRPLMESH_SYNC_BIN" --stage "$ap24" "$ap5"' "$RETAIL" | head -n1 | cut -d: -f1)"
retail_commit_line="$(grep -nF '"$UCI_BIN" commit system && "$UCI_BIN" commit prplmesh' "$RETAIL" | head -n1 | cut -d: -f1)"
retail_runtime_line="$(grep -nF 'run_without_mutation_fds "$WIFI_BIN" reload' "$RETAIL" | tail -n1 | cut -d: -f1)"
retail_verify_line="$(grep -nF '"$PRPLMESH_SYNC_BIN" --verify "$ap24" "$ap5"' "$RETAIL" | head -n1 | cut -d: -f1)"
[ -n "$retail_stage_line" ] && [ -n "$retail_commit_line" ] &&
	[ -n "$retail_runtime_line" ] && [ -n "$retail_verify_line" ] &&
	[ "$retail_stage_line" -lt "$retail_commit_line" ] &&
	[ "$retail_commit_line" -lt "$retail_runtime_line" ] &&
	[ "$retail_runtime_line" -lt "$retail_verify_line" ] ||
	fail 'Retail sync is outside stage/commit/runtime verification order'

# Dashboard backups and both rollback paths cover the shared transaction set.
backup_block="$(sed -n '/^backup_cfg() {/,/^}/p' "$DASHCTL")"
printf '%s\n' "$backup_block" | grep -Eq '(^|[[:space:]])/etc/config/prplmesh([[:space:]\\]|$)' ||
	fail 'dashboard backup omits /etc/config/prplmesh'
action_rollback_block="$(sed -n '/^action_arm_rollback() {/,/^}/p' "$DASHCTL")"
printf '%s\n' "$action_rollback_block" |
	grep -Fq 'for _action_pkg in $DASHCTL_TRANSACTION_UCI_PACKAGES; do' ||
	fail 'dashboard action rollback does not revert the shared package set'
royal_restore_block="$(sed -n '/^royal_restore_backup() {/,/^}/p' "$DASHCTL")"
printf '%s\n' "$royal_restore_block" |
	grep -Fq 'for _royal_pkg in $DASHCTL_TRANSACTION_UCI_PACKAGES; do' ||
	fail 'dashboard Royal rollback does not revert the shared package set'

# Every dashboard path that can change or remove primary Wi-Fi credentials must
# stage the closed EasyMesh mirror before either commit, verify Wi-Fi runtime,
# and only then compare the committed mirror.
save_block="$(sed -n '/^  save_wifi)/,/^  delete_wifi)/p' "$DASHCTL")"
assert_block_order save_wifi "$save_block" \
	'dashctl_prplmesh_stage' \
	'action_commit wireless' \
	'action_commit prplmesh' \
	'action_wifi_reload "Wireless"' \
	'dashctl_prplmesh_verify'

delete_block="$(sed -n '/^  delete_wifi)/,/^  save_dhcp_static|delete_dhcp_static)/p' "$DASHCTL")"
assert_block_order delete_wifi "$delete_block" \
	'dashctl_prplmesh_stage' \
	'action_commit wireless' \
	'action_commit prplmesh' \
	'action_wifi_reload "Wireless"' \
	'dashctl_prplmesh_verify'

raw_block="$(sed -n '/^  raw_uci_set|raw_uci_delete|raw_uci_add_section|raw_uci_delete_section|raw_uci_commit_reload)/,/^  save_dsa_vlan|delete_dsa_vlan)/p' "$DASHCTL")"
assert_block_order raw_wireless "$raw_block" \
	'dashctl_prplmesh_stage' \
	'uci commit "$cfg"' \
	'action_commit prplmesh' \
	'action_wifi_reload "Raw OpenWrt UCI"' \
	'dashctl_prplmesh_verify'

reset_block="$(sed -n '/^  reset_royal)/,/^  apply_royal)/p' "$DASHCTL")"
assert_royal_sync_order reset_royal "$reset_block"
apply_block="$(sed -n '/^  apply_royal)/,/^  save_quick)/p' "$DASHCTL")"
assert_royal_sync_order apply_royal "$apply_block"

# The routed guest BSS is deliberately outside the EasyMesh fronthaul mirror.
# Its credentials must remain attached to network=guest and must never stage,
# commit, or verify the primary-radio prplmesh credential transaction.
guest_block="$(sed -n '/^  save_guest)/,/^  save_iptv)/p' "$DASHCTL")"
printf '%s\n' "$guest_block" | grep -Fq "wireless.smartap_guest.network='guest'" ||
	fail 'guest Wi-Fi is not explicitly kept outside the primary LAN fronthaul'
if printf '%s\n' "$guest_block" | grep -Eq \
	'dashctl_prplmesh_(stage|verify|run)|action_commit[[:space:]]+prplmesh|royal_commit_packages[^[:cntrl:]]*prplmesh'; then
	fail 'guest Wi-Fi credentials participate in the primary prplmesh mirror'
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
STATE="$TMP/state"
MOCK_UCI="$TMP/uci"
ARGV_LOG="$TMP/argv.log"
mkdir -p "$STATE"
: > "$ARGV_LOG"

cat > "$MOCK_UCI" <<'EOF'
#!/bin/sh
set -eu
: "${MOCK_UCI_STATE:?}"
: "${MOCK_UCI_ARGV_LOG:?}"
printf 'argv:' >> "$MOCK_UCI_ARGV_LOG"
for arg in "$@"; do printf '<%s>' "$arg" >> "$MOCK_UCI_ARGV_LOG"; done
printf '\n' >> "$MOCK_UCI_ARGV_LOG"
[ "${1:-}" != -q ] || shift
action="${1:-}"
[ "$#" -eq 0 ] || shift
case "$action" in
	get)
		[ "$#" -eq 1 ] || exit 64
		case "$1" in ''|*[!A-Za-z0-9_.@\[\]-]*) exit 64 ;; esac
		[ -f "$MOCK_UCI_STATE/$1" ] || exit 1
		cat "$MOCK_UCI_STATE/$1"
		;;
	batch)
		[ "$#" -eq 0 ] || exit 64
		while IFS= read -r command || [ -n "$command" ]; do
			case "$command" in set\ *=*) ;; *) exit 65 ;; esac
			assignment="${command#set }"
			key="${assignment%%=*}"
			encoded="${assignment#*=}"
			case "$key" in
				prplmesh.radio0.ssid|prplmesh.radio0.security_mode|prplmesh.radio0.psk|\
				prplmesh.radio1.ssid|prplmesh.radio1.security_mode|prplmesh.radio1.psk|\
				prplmesh.config.ssid|prplmesh.config.mode_enabled|prplmesh.config.key_passphrase) ;;
				*) exit 66 ;;
			esac
			case "$encoded" in \'*\') ;; *) exit 67 ;; esac
			value=''
			# The production UCI batch parser uses shell-style quoted words. This
			# controlled test double evaluates only fixed fixture values and an
			# allowlisted destination key so quote escaping is exercised exactly.
			eval "value=$encoded"
			printf '%s' "$value" > "$MOCK_UCI_STATE/$key"
		done
		;;
	*) exit 64 ;;
esac
EOF
chmod 0755 "$MOCK_UCI"

setv() {
	printf '%s' "$2" > "$STATE/$1"
}

getv() {
	cat "$STATE/$1"
}

assert_value() {
	actual="$(getv "$1")"
	[ "$actual" = "$2" ] || fail "$1 mismatch"
}

run_sync() {
	MOCK_UCI_STATE="$STATE" MOCK_UCI_ARGV_LOG="$ARGV_LOG" \
		PRPLMESH_UCI_BIN="$MOCK_UCI" sh "$SYNC" "$@"
}

expect_sync_failure() {
	case_name="$1"
	shift
	if run_sync "$@" > "$TMP/$case_name.out" 2>&1; then
		fail "$case_name unexpectedly succeeded"
	fi
}

batch_count() {
	grep -Fc 'argv:<-q><batch>' "$ARGV_LOG" || true
}

setv wireless.ap24 wifi-iface
setv wireless.ap24.device radio0
setv wireless.ap24.mode ap
setv wireless.ap24.ssid 'Main'\''$(false)'
setv wireless.ap24.encryption psk2
setv wireless.ap24.key 'Secret'\''$(false)123'
setv wireless.ap5 wifi-iface
setv wireless.ap5.device radio1
setv wireless.ap5.mode ap
setv wireless.ap5.ssid 'Office 5G'
setv wireless.ap5.encryption sae-mixed
setv wireless.ap5.key 'SecondSecurePass456'
setv prplmesh.config prplmesh
setv prplmesh.radio0 wifi-device
setv prplmesh.radio1 wifi-device
setv prplmesh.config.enable 0
setv prplmesh.config.operational 0
setv prplmesh.config.active_control_confirmed 0
for key in \
	prplmesh.radio0.ssid prplmesh.radio0.security_mode prplmesh.radio0.psk \
	prplmesh.radio1.ssid prplmesh.radio1.security_mode prplmesh.radio1.psk \
	prplmesh.config.ssid prplmesh.config.mode_enabled prplmesh.config.key_passphrase; do
	setv "$key" old
done

stage_output="$(run_sync --stage ap24 ap5)" || fail 'valid encrypted staging failed'
[ "$stage_output" = 'prplmesh_credential_sync=staged' ] || fail 'staging output is not generic'
assert_value prplmesh.radio0.ssid 'Main'\''$(false)'
assert_value prplmesh.radio0.security_mode wpa2-psk
assert_value prplmesh.radio0.psk 'Secret'\''$(false)123'
assert_value prplmesh.radio1.ssid 'Office 5G'
assert_value prplmesh.radio1.security_mode wpa2-psk
assert_value prplmesh.radio1.psk 'SecondSecurePass456'
assert_value prplmesh.config.ssid 'Main'\''$(false)'
assert_value prplmesh.config.mode_enabled WPA2-Personal
assert_value prplmesh.config.key_passphrase 'Secret'\''$(false)123'
assert_value prplmesh.config.enable 0
assert_value prplmesh.config.operational 0
assert_value prplmesh.config.active_control_confirmed 0
! grep -Fq 'Secret' "$ARGV_LOG" || fail 'a Wi-Fi secret leaked into UCI argv'
[ "$(run_sync --verify ap24 ap5)" = 'prplmesh_credential_sync=verified' ] || \
	fail 'credential verification failed'

# A 64-hex raw PSK cannot be represented by the local prplMesh start contract.
# Preserve the mirror but mark it unsupported so service start remains closed.
raw_psk='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
setv wireless.ap24.key "$raw_psk"
run_sync --stage ap24 ap5 >/dev/null || fail 'raw PSK fail-closed staging failed'
assert_value prplmesh.radio0.security_mode unsupported
assert_value prplmesh.config.mode_enabled Unsupported
assert_value prplmesh.radio0.psk "$raw_psk"
assert_value prplmesh.config.enable 0

# Open APs clear stale secrets in all mirrors without opening an EasyMesh gate.
setv wireless.ap24.encryption none
setv wireless.ap24.key stale-secret
setv wireless.ap5.encryption none
setv wireless.ap5.key another-stale-secret
run_sync --stage ap24 ap5 >/dev/null || fail 'open credential staging failed'
assert_value prplmesh.radio0.security_mode none
assert_value prplmesh.radio0.psk ''
assert_value prplmesh.radio1.security_mode none
assert_value prplmesh.radio1.psk ''
assert_value prplmesh.config.key_passphrase ''
assert_value prplmesh.config.enable 0

# Verification detects any post-commit divergence without mutating it.
setv wireless.ap24.encryption psk2
setv wireless.ap24.key 'ValidPassphrase123'
setv wireless.ap5.encryption psk2
setv wireless.ap5.key 'OtherPassphrase456'
run_sync --stage ap24 ap5 >/dev/null || fail 'baseline restaging failed'
setv prplmesh.radio1.ssid tampered
before_batches="$(batch_count)"
expect_sync_failure verify_tamper --verify ap24 ap5
[ "$(batch_count)" = "$before_batches" ] || fail 'verify mode wrote a UCI batch'

# Any open gate refuses staging before the first mutation.
setv prplmesh.radio1.ssid old-before-gate-test
setv prplmesh.config.enable 1
before_batches="$(batch_count)"
expect_sync_failure gate_open --stage ap24 ap5
[ "$(batch_count)" = "$before_batches" ] || fail 'open EasyMesh gate allowed staging'
assert_value prplmesh.radio1.ssid old-before-gate-test
setv prplmesh.config.enable 0

# UCI output is read with a non-newline sentinel. Therefore even trailing LF,
# which ordinary command substitution would silently remove, fails before batch.
for unsafe_case in trailing_lf embedded_lf trailing_cr comment_byte; do
	setv wireless.ap24.ssid 'Valid Main'
	case "$unsafe_case" in
		trailing_lf) printf 'BadSSID\n' > "$STATE/wireless.ap24.ssid" ;;
		embedded_lf) printf 'Bad\nSSID' > "$STATE/wireless.ap24.ssid" ;;
		trailing_cr) printf 'BadSSID\r' > "$STATE/wireless.ap24.ssid" ;;
		comment_byte) printf 'Bad#SSID' > "$STATE/wireless.ap24.ssid" ;;
	esac
	before_batches="$(batch_count)"
	expect_sync_failure "$unsafe_case" --stage ap24 ap5
	[ "$(batch_count)" = "$before_batches" ] || fail "$unsafe_case reached UCI batch"
done

printf 'prplmesh_credential_sync_contract=pass\n'
