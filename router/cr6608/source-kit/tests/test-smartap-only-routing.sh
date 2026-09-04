#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SYSAUTH="$ROOT/files/usr/share/ucode/luci/template/themes/argon/sysauth.ut"
MIGRATION="$ROOT/files/etc/uci-defaults/99-cr6608-smartap-only"
UHTTPD="$ROOT/files/etc/config/uhttpd"
INDEX="$ROOT/files/www/index.html"
DASHBOARD="$ROOT/files/www/dashboard.js"
DASHLUCI="$ROOT/files/www/cgi-bin/dashluci"
QUICKSETTINGS="$ROOT/files/www/luci-static/resources/view/cr6608/quicksettings.js"
UHTTPD_PATCH="$ROOT/patches/992-uhttpd-normalize-dispatch-and-close-unread-body.patch"
SECURITY_HEADERS="$ROOT/files/etc/uhttpd/security-headers.json"
PACKAGE_CGI="$ROOT/files/www/cgi-bin/luci"
CANONICAL='/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc'

fail() {
	printf 'smartap_luci_handoff=fail: %s\n' "$*" >&2
	exit 1
}

for file in "$SYSAUTH" "$MIGRATION" "$UHTTPD" "$INDEX" "$DASHBOARD" "$DASHLUCI" "$QUICKSETTINGS" "$UHTTPD_PATCH" "$SECURITY_HEADERS"; do
	[ -s "$file" ] || fail "missing $file"
done
[ ! -e "$PACKAGE_CGI" ] || fail 'overlay replaces the luci-base package CGI'
sh -n "$MIGRATION" || fail 'preserved-config migration syntax failed'

[ "$(grep -Fc "list ucode_prefix '$CANONICAL'" "$UHTTPD")" = 1 ] ||
	fail 'clean uhttpd config lacks one canonical LuCI ucode handler'
[ "$(grep -Ec "^[[:space:]]*option json_script '/etc/uhttpd/security-headers.json'$" "$UHTTPD")" = 1 ] ||
	fail 'clean uhttpd config does not load exactly one supported JSON header handler'
python3 - "$SECURITY_HEADERS" <<'PY' || fail 'uhttpd security-header JSON contract failed'
import json
import pathlib
import sys

expected = {
    "request": [
        [
            ["add-header", "X-Content-Type-Options", "nosniff"],
            ["add-header", "X-Frame-Options", "SAMEORIGIN"],
            ["add-header", "Referrer-Policy", "no-referrer"],
            ["add-header", "Permissions-Policy", "camera=(), microphone=(), geolocation=()"],
            ["add-header", "Cross-Origin-Resource-Policy", "same-origin"],
            ["add-header", "Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self'; frame-ancestors 'self'; object-src 'none'; base-uri 'self'; form-action 'self'"],
        ],
    ]
}
with pathlib.Path(sys.argv[1]).open("r", encoding="utf-8") as stream:
    actual = json.load(stream)
if actual != expected:
    raise SystemExit("unexpected uhttpd security-header policy")
PY
grep -Fq 'if (cl->tls &&' "$UHTTPD_PATCH" || fail 'uhttpd patch does not gate HSTS on the live TLS transport'
grep -Fq 'Strict-Transport-Security: max-age=31536000' "$UHTTPD_PATCH" || fail 'uhttpd patch lacks HSTS'
command -v git >/dev/null 2>&1 || fail 'git is required to validate the uhttpd patch structure'
uhttpd_patch_numstat="$(git apply --numstat -- "$UHTTPD_PATCH" 2>/dev/null)" ||
	fail 'uhttpd patch is syntactically malformed'
[ "$uhttpd_patch_numstat" = "$(printf '23\t11\tclient.c\n68\t6\tfile.c\n18\t0\tproc.c\n1\t0\tuhttpd.h')" ] ||
	fail 'uhttpd patch inventory or line counts changed unexpectedly'
python3 - "$UHTTPD_PATCH" <<'PY' || fail 'uhttpd patch hunk line count validation failed'
import pathlib
import re
import sys

patch = pathlib.Path(sys.argv[1])
lines = patch.read_text(encoding="utf-8").splitlines()
hunk_header = re.compile(
    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: .*)?$"
)
hunks = 0
index = 0
while index < len(lines):
    line = lines[index]
    if not line.startswith("@@ "):
        index += 1
        continue
    match = hunk_header.fullmatch(line)
    if not match:
        raise SystemExit(f"malformed hunk header at line {index + 1}")
    old_expected = int(match.group(2) or "1")
    new_expected = int(match.group(4) or "1")
    old_actual = 0
    new_actual = 0
    index += 1
    while index < len(lines):
        current = lines[index]
        if current.startswith("@@ "):
            break
        if current.startswith("--- ") and index + 1 < len(lines) and lines[index + 1].startswith("+++ "):
            break
        if not current:
            raise SystemExit(f"unprefixed empty hunk line at line {index + 1}")
        prefix = current[0]
        if prefix == " ":
            old_actual += 1
            new_actual += 1
        elif prefix == "-":
            old_actual += 1
        elif prefix == "+":
            new_actual += 1
        elif current != r"\ No newline at end of file":
            raise SystemExit(f"invalid hunk line prefix at line {index + 1}")
        index += 1
    if (old_actual, new_actual) != (old_expected, new_expected):
        raise SystemExit(
            f"hunk line count mismatch: expected {old_expected}/{new_expected}, "
            f"found {old_actual}/{new_actual}"
        )
    hunks += 1
if hunks != 13:
    raise SystemExit(f"unexpected hunk count: {hunks}")
PY
for centralized_header in \
	'X-Content-Type-Options:' \
	'X-Frame-Options:' \
	'Referrer-Policy:' \
	'Permissions-Policy:' \
	'Cross-Origin-Resource-Policy:' \
	'Content-Security-Policy:'; do
	! grep -Fq "$centralized_header" "$UHTTPD_PATCH" ||
		fail "uhttpd patch duplicates JSON-managed header: $centralized_header"
done
grep -Fq "http.redirect('/');" "$SYSAUTH" ||
	fail 'unauthenticated or expired LuCI requests do not return to Smart AP'

# Prefix dispatch must use the decoded, canonical path.  Otherwise encoded
# letters, encoded slashes, repeated slashes and dot segments can fall through
# to luci-base's package CGI.  The unread-body guard closes POST/PUT/PATCH
# connections after the redirect handler returns without consuming the body.
for marker in \
	'normalize_dispatch_url' \
	'uh_urldecode(decoded' \
	'canonpath_lexical(decoded, normalized)' \
	'dispatch_find(dispatch_url, NULL)' \
	'uh_invoke_handler(cl, d, dispatch_url, NULL)' \
	'uh_proc_header_exists(cl, blobmsg_name(cur))' \
	'cl->dispatch.free != proc_free' \
	'p->r.header_cb || !p->hdr.head' \
	'!strcasecmp(blobmsg_name(cur), name)' \
	'cl->dispatch.no_cache = true;' \
	'Cache-Control: no-store, no-cache, must-revalidate' \
	'r->transfer_chunked || r->content_length > 0'; do
	grep -Fq "$marker" "$UHTTPD_PATCH" || fail "uhttpd hardening lacks: $marker"
done
for marker in \
	'[ "${REQUEST_METHOD:-GET}" = POST ]' \
	'cr6608_session_from_request' \
	'cr6608_session_valid "$request_sid"' \
	'cr6608_luci_session_lock' \
	'map_file="$map_dir/$request_sid"' \
	'cr6608_valid_hex32 "$mapped_luci_sid"' \
	'luci_session_reauthentication_required' \
	'HttpOnly; SameSite=Strict' \
	'"target":"/cgi-bin/luci/admin/network/wireless"'; do
	grep -Fq "$marker" "$DASHLUCI" || fail "secure LuCI handoff lacks: $marker"
done
for forbidden_marker in 'session create' 'session grant' 'grant_access_groups' 'ACL_HELPER'; do
	! grep -Fq "$forbidden_marker" "$DASHLUCI" ||
		fail "LuCI handoff retains unbounded fallback: $forbidden_marker"
done
grep -Fq 'id="openWrtBtn"' "$INDEX" || fail 'Smart AP lacks the OpenWrt settings button'
grep -Fq 'async function ensureLuciSession()' "$DASHBOARD" || fail 'dashboard lacks the secure LuCI session exchange'
grep -Fq '/cgi-bin/dashluci' "$DASHBOARD" || fail 'OpenWrt button does not call the session bridge'
grep -Fq 'window.location.assign("/cgi-bin/luci/admin/network/wireless")' "$DASHBOARD" ||
	fail 'OpenWrt button does not use the fixed wireless settings target'
! grep -Fq "window.location.href = '/cgi-bin/luci" "$QUICKSETTINGS" ||
	fail 'legacy quick-settings error path can still navigate to LuCI'
grep -Fq 'Smart AP dashboard. Live data' "$INDEX" || fail 'Smart AP is not the sole dashboard identity'

# Exercise an upgrade with two preserved uhttpd instances, legacy ucode and
# Lua LuCI handlers, broad ancestor handlers, a more-specific LuCI bypass, and
# unrelated handlers.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-smartap-route.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
STATE="$TMP/state"
BACKUP="$TMP/backup"
mkdir -p "$BIN" "$STATE" "$BACKUP"

write_initial_state() {
	printf '%s\n' \
		'/=/tmp/root-shadow.uc' \
		'/cgi-bin=/tmp/cgi-shadow.uc' \
		'/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc' \
		'/cgi-bin/luci/admin=/tmp/bypass.uc' \
		'/rpc-test=/usr/libexec/rpc-test.uc' >"$STATE/main.ucode_prefix"
	printf '%s\n' \
		'/cgi-bin=/usr/lib/lua/cgi-shadow.lua' \
		'/cgi-bin/luci=/usr/lib/lua/luci/sgi/uhttpd.lua' \
		'/lua-test=/usr/lib/lua/test.lua' >"$STATE/main.lua_prefix"
	printf '%s\n' \
		'/cgi-bin/luci=/old/secondary.uc' \
		'/rpc-alt=/usr/libexec/rpc-alt.uc' >"$STATE/alt.ucode_prefix"
	: >"$STATE/alt.lua_prefix"
	# Model a malformed preserved scalar with the mandatory handler duplicated;
	# migration must retain the custom path while normalizing ours to one copy.
	printf '%s\n' "/etc/uhttpd/custom.json $SECURITY_HEADERS $SECURITY_HEADERS" >"$STATE/main.json_script"
	: >"$STATE/alt.json_script"
}

snapshot_state() {
	rm -f "$BACKUP"/*
	cp "$STATE"/* "$BACKUP"/
}

write_initial_state
snapshot_state

cat >"$BIN/ubus" <<'EOF'
#!/bin/sh
printf '%s\n' '{"board_name":"xiaomi,mi-router-cr6608"}'
EOF
cat >"$BIN/jsonfilter" <<'EOF'
#!/bin/sh
[ "${CR6608_TEST_JSONFILTER_FAIL:-0}" != 1 ] || exit 1
printf '%s\n' "${CR6608_TEST_BOARD_NAME-xiaomi,mi-router-cr6608}"
EOF
cat >"$BIN/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" != -q ] || shift

state_file() {
	case "$1" in
		uhttpd.main.ucode_prefix) printf '%s/main.ucode_prefix\n' "$CR6608_TEST_STATE_DIR" ;;
		uhttpd.main.lua_prefix) printf '%s/main.lua_prefix\n' "$CR6608_TEST_STATE_DIR" ;;
		uhttpd.alt.ucode_prefix) printf '%s/alt.ucode_prefix\n' "$CR6608_TEST_STATE_DIR" ;;
		uhttpd.alt.lua_prefix) printf '%s/alt.lua_prefix\n' "$CR6608_TEST_STATE_DIR" ;;
		uhttpd.main.json_script) printf '%s/main.json_script\n' "$CR6608_TEST_STATE_DIR" ;;
		uhttpd.alt.json_script) printf '%s/alt.json_script\n' "$CR6608_TEST_STATE_DIR" ;;
		*) return 1 ;;
	esac
}

case "${1:-}:${2:-}" in
	show:uhttpd)
		printf '%s\n' 'uhttpd.main=uhttpd' 'uhttpd.alt=uhttpd'
		;;
	get:*)
		file="$(state_file "$2")" || exit 1
		tr '\n' ' ' <"$file"
		;;
	delete:*)
		file="$(state_file "$2")" || exit 1
		: >"$file"
		;;
	add_list:*)
		key="${2%%=*}"
		value="${2#*=}"
		[ "${CR6608_TEST_FAIL_VALUE:-}" != "$value" ] || exit 1
		file="$(state_file "$key")" || exit 1
		printf '%s\n' "$value" >>"$file"
		;;
	set:*)
		key="${2%%=*}"
		value="${2#*=}"
		file="$(state_file "$key")" || exit 1
		printf '%s\n' "$value" >"$file"
		;;
	commit:uhttpd)
		: >"$CR6608_TEST_COMMIT_MARKER"
		;;
	revert:uhttpd)
		cp "$CR6608_TEST_BACKUP_DIR"/* "$CR6608_TEST_STATE_DIR"/
		: >"$CR6608_TEST_REVERT_MARKER"
		;;
	*) exit 1 ;;
esac
EOF
chmod 0700 "$BIN/ubus" "$BIN/jsonfilter" "$BIN/uci"

run_migration() {
	CR6608_TEST_STATE_DIR="$STATE" \
	CR6608_TEST_BACKUP_DIR="$BACKUP" \
	CR6608_TEST_COMMIT_MARKER="$TMP/committed" \
	CR6608_TEST_REVERT_MARKER="$TMP/reverted" \
	CR6608_LUCI_HANDLER="$SYSAUTH" \
	CR6608_SECURITY_HEADERS="$SECURITY_HEADERS" \
	PATH="$BIN:$PATH" sh "$MIGRATION"
}

run_migration || fail 'preserved multi-instance uhttpd migration failed'
expected_mapping="/cgi-bin/luci=$SYSAUTH"
[ "$(sed '/^$/d' "$STATE/main.ucode_prefix")" = "$(printf '%s\n%s' "$expected_mapping" '/rpc-test=/usr/libexec/rpc-test.uc')" ] ||
	fail 'main migration changed an unrelated ucode prefix or canonical order'
[ "$(sed '/^$/d' "$STATE/main.lua_prefix")" = '/lua-test=/usr/lib/lua/test.lua' ] ||
	fail 'main migration changed an unrelated Lua prefix'
[ "$(sed '/^$/d' "$STATE/alt.ucode_prefix")" = "$(printf '%s\n%s' "$expected_mapping" '/rpc-alt=/usr/libexec/rpc-alt.uc')" ] ||
	fail 'secondary uhttpd instance was not protected'
[ ! -s "$STATE/alt.lua_prefix" ] || fail 'empty secondary Lua list changed'
[ "$(cat "$STATE/main.json_script")" = "/etc/uhttpd/custom.json $SECURITY_HEADERS" ] ||
	fail 'migration did not retain the existing main JSON handler before the security policy'
[ "$(cat "$STATE/alt.json_script")" = "$SECURITY_HEADERS" ] ||
	fail 'migration did not install the security policy on the secondary uhttpd instance'
[ -e "$TMP/committed" ] || fail 'migration did not commit uhttpd config'
! grep -R -Fq '/cgi-bin/luci/admin=' "$STATE" || fail 'specific LuCI bypass survived migration'
! grep -R -Eq '^/=|^/cgi-bin=' "$STATE" || fail 'ancestor handler can shadow the Smart AP route'

# A transient board-service/filter failure or an empty board response must
# retain the uci-defaults script for a later boot instead of silently leaving
# preserved LuCI mappings exposed.  A known non-CR6608 board is a safe no-op.
for board_case in filter_fail empty_board; do
	write_initial_state
	snapshot_state
	rm -f "$TMP/committed" "$TMP/reverted"
	set +e
	case "$board_case" in
		filter_fail) CR6608_TEST_JSONFILTER_FAIL=1 run_migration >/dev/null 2>&1 ;;
		empty_board) CR6608_TEST_BOARD_NAME='' run_migration >/dev/null 2>&1 ;;
	esac
	board_rc=$?
	set -e
	[ "$board_rc" -ne 0 ] || fail "$board_case incorrectly completed the migration"
	[ ! -e "$TMP/committed" ] || fail "$board_case committed uhttpd state"
	[ ! -e "$TMP/reverted" ] || fail "$board_case entered a UCI transaction"
	for file in main.ucode_prefix main.lua_prefix alt.ucode_prefix alt.lua_prefix main.json_script alt.json_script; do
		cmp -s "$STATE/$file" "$BACKUP/$file" || fail "$board_case changed $file"
	done
done

write_initial_state
snapshot_state
rm -f "$TMP/committed" "$TMP/reverted"
CR6608_TEST_BOARD_NAME='example,other-router' run_migration ||
	fail 'known non-CR6608 board did not exit cleanly'
[ ! -e "$TMP/committed" ] || fail 'non-CR6608 board committed uhttpd state'
for file in main.ucode_prefix main.lua_prefix alt.ucode_prefix alt.lua_prefix main.json_script alt.json_script; do
	cmp -s "$STATE/$file" "$BACKUP/$file" || fail "non-CR6608 board changed $file"
done

# A failed list restoration must revert the whole UCI transaction rather than
# leaving a partially deleted server configuration.
write_initial_state
snapshot_state
rm -f "$TMP/committed" "$TMP/reverted"
set +e
CR6608_TEST_FAIL_VALUE='/rpc-alt=/usr/libexec/rpc-alt.uc' run_migration >/dev/null 2>&1
failure_rc=$?
set -e
[ "$failure_rc" -ne 0 ] || fail 'injected UCI failure unexpectedly succeeded'
[ -e "$TMP/reverted" ] || fail 'failed migration did not call uci revert'
for file in main.ucode_prefix main.lua_prefix alt.ucode_prefix alt.lua_prefix main.json_script alt.json_script; do
	cmp -s "$STATE/$file" "$BACKUP/$file" || fail "failed migration left partial state in $file"
done
[ ! -e "$TMP/committed" ] || fail 'failed migration committed partial state'

printf 'smartap_luci_handoff=pass\n'
