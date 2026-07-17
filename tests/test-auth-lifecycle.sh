#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FILES="$ROOT/files"
AUTH="$FILES/usr/libexec/cr6608-session-auth"
LOGIN="$FILES/www/cgi-bin/dashlogin"
LUCI="$FILES/www/cgi-bin/dashluci"
LOGOUT="$FILES/www/cgi-bin/dashlogout"
DASHBOARD="$FILES/www/dashboard.js"
LOGOUT_CONTROLLER="$FILES/usr/share/ucode/luci/controller/cr6608/logout.uc"
LOGOUT_MENU="$FILES/usr/share/luci/menu.d/zz-cr6608-logout.json"
REAPER="$FILES/usr/sbin/cr6608-session-reaper"
ROOT_CRONTAB="$FILES/etc/crontabs/root"
ROOT_PASSWORD_DEFAULT="$FILES/etc/uci-defaults/99-cr6608-root-pass"
SHADOW="$FILES/etc/shadow"

fail() {
	printf 'auth_lifecycle_test=fail: %s\n' "$*" >&2
	exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"

for file in \
	"$AUTH" \
	"$LOGIN" \
	"$LUCI" \
	"$LOGOUT" \
	"$DASHBOARD" \
	"$LOGOUT_CONTROLLER" \
	"$LOGOUT_MENU" \
	"$REAPER" \
	"$ROOT_CRONTAB" \
	"$ROOT_PASSWORD_DEFAULT" \
	"$SHADOW"
do
	[ -f "$file" ] && [ ! -L "$file" ] && [ -s "$file" ] ||
		fail "missing, empty, or symlinked source: $file"
done

pinned_hash="$(sed -n "s/^pinned_hash='\(.*\)'$/\1/p" "$ROOT_PASSWORD_DEFAULT")"
shadow_hash="$(awk -F: '$1 == "root" { print $2; exit }' "$SHADOW")"
[ -n "$pinned_hash" ] || fail "first-boot root hash is missing"
[ "$pinned_hash" = "$shadow_hash" ] || fail "first-boot and clean-image root hashes differ"
case "$pinned_hash" in
	\$6\$cr66sshd911cc74\$*) ;;
	*) fail "root hash is not the pinned SHA-512 credential" ;;
esac

for script in "$AUTH" "$LOGIN" "$LUCI" "$LOGOUT" "$REAPER"; do
	sh -n "$script" || fail "shell syntax rejected: $script"
done

python3 - \
	"$AUTH" "$LOGIN" "$LUCI" "$LOGOUT" "$DASHBOARD" \
	"$LOGOUT_CONTROLLER" "$LOGOUT_MENU" "$REAPER" "$ROOT_CRONTAB" <<'PY'
import json
import pathlib
import re
import sys


def die(message):
    print(f"auth_lifecycle_test=fail: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition, message):
    if not condition:
        die(message)


def require_text(source, needle, label):
    require(needle in source, f"{label}: missing {needle!r}")


def forbid_text(source, needle, label):
    require(needle not in source, f"{label}: forbidden {needle!r}")


def ordered(source, needles, label):
    position = -1
    for needle in needles:
        next_position = source.find(needle, position + 1)
        require(next_position >= 0, f"{label}: missing ordered token {needle!r}")
        require(next_position > position, f"{label}: invalid order at {needle!r}")
        position = next_position


def shell_function(source, name, label):
    match = re.search(
        rf"(?ms)^{re.escape(name)}\(\) \{{\n(.*?)(?=^[A-Za-z_][A-Za-z0-9_]*\(\) \{{|\Z)",
        source,
    )
    require(match is not None, f"{label}: function {name}() is missing")
    return match.group(0)


def js_function(source, name, label):
    match = re.search(
        rf"(?ms)^\s*(?:async\s+)?function\s+{re.escape(name)}\([^)]*\)\s*\{{.*?"
        rf"(?=^\s*(?:async\s+)?function\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\(|\Z)",
        source,
    )
    require(match is not None, f"{label}: function {name}() is missing")
    return match.group(0)


paths = [pathlib.Path(value) for value in sys.argv[1:]]
(
    auth_path,
    login_path,
    luci_path,
    logout_path,
    dashboard_path,
    controller_path,
    menu_path,
    reaper_path,
    crontab_path,
) = paths
auth, login, luci, logout, dashboard, controller, menu_source, reaper, crontab = [
    path.read_text(encoding="utf-8") for path in paths
]

# The bearer is generated from exactly 16 bytes and is accepted only from the
# HttpOnly cookie. No request argument, header, body, or query fallback exists.
entropy = shell_function(auth, "cr6608_random_hex32", "session helper")
require_text(entropy, "cr6608_session_storage_prepare || return 1", "entropy path")
require_text(entropy, 'random_file="/tmp/dashsess/.random.$$"', "entropy path")
require_text(entropy, '[ ! -e "$random_file" ] && [ ! -L "$random_file" ] || return 1', "entropy path")
ordered(
    entropy,
    [
        'dd if=/dev/urandom of="$random_file" bs=16 count=1',
        'wc -c <"$random_file"',
        'hexdump -v -n 16 -e \'1/1 "%02x"\' "$random_file"',
        'cr6608_valid_hex32 "$token" || return 1',
        "printf '%s' \"$token\"",
    ],
    "entropy path",
)
require(
    re.search(r'\[ "\$\(wc -c <"\$random_file" 2>/dev/null\)" = 16 \]', entropy) is not None,
    "entropy path: exact 16-byte length check is missing",
)
for weak_source in ("date ", "md5sum", "sha1sum", "sha256sum", "/dev/random", "od -"):
    forbid_text(entropy, weak_source, "entropy path")

cookie_reader = shell_function(auth, "cr6608_session_from_request", "session helper")
require_text(cookie_reader, '${HTTP_COOKIE:-}', "cookie reader")
require_text(cookie_reader, 'cr6608_sid=', "cookie reader")
require_text(cookie_reader, 'cr6608_valid_hex32 "$sid" || sid=', "cookie reader")
for forbidden_input in (
    "HTTP_X_CR6608_SESSION",
    "HTTP_AUTHORIZATION",
    "QUERY_STRING",
    "REQUEST_URI",
    "POST_DATA",
    "BODY",
    '"$1"',
    "${1",
):
    forbid_text(cookie_reader, forbidden_input, "cookie reader")

destroy_child = shell_function(auth, "cr6608_destroy_luci_session", "session helper")
ordered(
    destroy_child,
    [
        'local luci_sid="$1"',
        'local destroy_rc=0',
        'ubus call session destroy',
        'destroy_rc=$?',
        'case "$destroy_rc" in 0|4|252)',
        'return "$destroy_rc"',
    ],
    "idempotent LuCI child revocation",
)
require(
    re.search(r'(?m)^\s*rc=\$\?\s*$', destroy_child) is None,
    "idempotent LuCI child revocation: caller status variable is reused",
)

auth_surfaces = {
    "session helper": auth,
    "login CGI": login,
    "LuCI bridge CGI": luci,
    "logout CGI": logout,
    "dashboard": dashboard,
}
for label, source in auth_surfaces.items():
    forbid_text(source, "HTTP_X_CR6608_SESSION", label)
    forbid_text(source, "X-CR6608-Session", label)
    forbid_text(source, "Authorization: Bearer", label)

for label, source in (("login CGI", login), ("LuCI bridge CGI", luci), ("logout CGI", logout)):
    for line in source.splitlines():
        if "cr6608_session_from_request" in line:
            require(
                re.search(r"cr6608_session_from_request\s*\)", line) is not None,
                f"{label}: session helper is called with request-supplied arguments",
            )
    for pattern in (
        r"@\.(?:sid|session|token)\b",
        r"form_value\s+(?:sid|session|token)\b",
        r"(?:POST_DATA|BODY|QUERY_STRING).*cr6608_sid",
        r"cr6608_sid.*(?:POST_DATA|BODY|QUERY_STRING)",
        r"sed\s+[^\n]*(?:\^|/)sid=",
    ):
        require(
            re.search(pattern, source, re.IGNORECASE) is None,
            f"{label}: SID can be parsed from a body or query path ({pattern})",
        )

# Successful JSON replies are status-only. The bearer is set as an HttpOnly,
# SameSite cookie and never appears in a JSON key or browser-readable value.
for label, source in (("login CGI", login), ("LuCI bridge CGI", luci), ("logout CGI", logout)):
    for line in source.splitlines():
        if "{" in line and "}" in line and ("reply" in line or "printf" in line):
            require(
                re.search(r'["\'](?:sid|session|token|ubus_rpc_session)["\']\s*:', line) is None,
                f"{label}: a bearer-like value is returned in JSON",
            )
require_text(login, "reply \"\" '{\"ok\":true}'", "login CGI")
require_text(luci, "reply \"\" '{\"ok\":true}'", "LuCI bridge CGI")
require_text(logout, "printf '{\"ok\":true}\\n'", "logout CGI")
require_text(login, "Set-Cookie: %s", "login CGI")
require_text(login, "HttpOnly; SameSite=Strict", "login CGI")
require_text(luci, "HttpOnly; SameSite=Strict", "LuCI bridge CGI")

for forbidden_js in (
    "data.sid",
    "data.session",
    "data.token",
    "response.sid",
    "response.session",
    "response.token",
    "localStorage.setItem(LS + \"session\"",
):
    forbid_text(dashboard, forbidden_js, "dashboard")
storage_writes = re.findall(
    r"sessionStorage\.setItem\(\s*LS\s*\+\s*['\"]session['\"]\s*,\s*([^\)]+)\)",
    dashboard,
)
require(storage_writes == ['"cookie"'], "dashboard: session storage must contain only the literal cookie marker")
require(
    re.search(r'function\s+sidQuery\(\)\s*\{\s*return\s+["\']session_cookie=1["\'];\s*\}', dashboard)
    is not None,
    "dashboard: request bodies must carry only the harmless cookie marker",
)
login_js = js_function(dashboard, "login", "dashboard")
ordered(
    login_js,
    [
        'state.session = "cookie"',
        "showDashboard()",
        "await ensureLuciSession()",
    ],
    "dashboard login must not depend on the LuCI bridge",
)

# The failed-login counter is read, tested, changed, and cleared only after an
# exclusive, fail-closed flock has been acquired for that client.
ordered(
    login,
    [
        'rate_file="$RATE_DIR/$rate_id"',
        'rate_lock="$rate_file.lock"',
        'exec 8>>"$rate_lock"',
        'cr6608_path_owned_by_root "$rate_lock"',
        'flock -x 8 || reply "503 Service Unavailable"',
        'if [ -r "$rate_file" ]; then',
        'read -r fails window < "$rate_file"',
        'if [ "$fails" -ge 5 ]',
        "login_failed()",
        '>"$rate_file"',
        'rm -f "$rate_file"',
    ],
    "login rate limiter",
)
flock_line = next((line for line in login.splitlines() if "flock -x 8" in line), "")
require("|| reply \"503 Service Unavailable\"" in flock_line, "login rate limiter: flock is not fail closed")
for line_number, line in enumerate(login.splitlines(), 1):
    if "$rate_file" not in line:
        continue
    if line.strip() in ('rate_file="$RATE_DIR/$rate_id"', 'rate_lock="$rate_file.lock"'):
        continue
    flock_number = login[: login.find('flock -x 8 || reply "503 Service Unavailable"')].count("\n") + 1
    require(line_number > flock_number, f"login rate limiter: rate state is accessed before flock on line {line_number}")
require(
    re.search(r'>"\$rate_file"\s*\|\|\s*\n?\s*reply "503 Service Unavailable"', login) is not None,
    "login rate limiter: failed counter writes are not fail closed",
)
require(
    re.search(r'rm -f "\$rate_file"[^\n]*\|\|\s*reply "503 Service Unavailable"', login) is not None,
    "login rate limiter: successful-login reset is not fail closed",
)

# One revocation path removes the Smart session and its mapped LuCI child. The
# browser and LuCI menu both converge on dashlogout, which clears every cookie.
revoke = shell_function(auth, "cr6608_revoke_session_unlocked", "session helper")
ordered(
    revoke,
    [
        'rm -f "/tmp/dashsess/$sid"',
        'map_file="/tmp/dashluci/$sid"',
        'cr6608_destroy_luci_session "$luci_sid"',
        'rm -f "$map_file"',
    ],
    "unified server revocation",
)
session_valid = shell_function(auth, "cr6608_session_valid", "session helper")
expiry_guard = 'if [ "$age" -lt 0 ] 2>/dev/null || [ "$age" -gt 43200 ] 2>/dev/null; then'
ordered(
    session_valid,
    [
        expiry_guard,
        'cr6608_revoke_session_unlocked "$sid" >/dev/null 2>&1 || true',
        "return 1",
    ],
    "expired parent revocation",
)
expiry_tail = session_valid[session_valid.find(expiry_guard):]
require(
    expiry_tail.find('cr6608_revoke_session_unlocked "$sid"') < expiry_tail.find("return 1"),
    "expired parent revocation: child revocation does not precede rejection",
)
require_text(logout, '[ "${REQUEST_METHOD:-GET}" = POST ]', "logout CGI")
ordered(
    logout,
    [
        'sid="$(cr6608_session_from_request)"',
        "cr6608_luci_session_lock",
        'cr6608_revoke_session_unlocked "$sid"',
        "Status: 503 Service Unavailable",
        "Set-Cookie: cr6608_sid=;",
        "Set-Cookie: sysauth_http=;",
        "Set-Cookie: sysauth_https=;",
    ],
    "logout CGI",
)
require_text(logout, '"revocation_failed"', "logout CGI")
for cookie_line in (
    "Set-Cookie: cr6608_sid=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict",
    "Set-Cookie: sysauth_http=; Path=/cgi-bin/luci/; Max-Age=0; HttpOnly; SameSite=Strict",
    "Set-Cookie: sysauth_https=; Path=/cgi-bin/luci/; Max-Age=0; Secure; HttpOnly; SameSite=Strict",
):
    require_text(logout, cookie_line, "logout CGI")

revoke_js = js_function(dashboard, "revokeServerSessions", "dashboard")
require_text(revoke_js, 'fetch("/cgi-bin/dashlogout"', "dashboard logout request")
require_text(revoke_js, 'method: "POST"', "dashboard logout request")
require_text(revoke_js, 'credentials: "same-origin"', "dashboard logout request")
require_text(revoke_js, "if (!res.ok || !data.ok) throw", "dashboard logout request")
logout_js = js_function(dashboard, "logout", "dashboard")
ordered(
    logout_js,
    [
        "await revokeServerSessions()",
        'state.session = ""',
        'sessionStorage.removeItem(LS + "session")',
    ],
    "dashboard logout",
)

require_text(luci, 'map_file="$map_dir/$request_sid"', "LuCI bridge CGI")
require_text(luci, 'printf \'%s\\n\' "$NEW_LUCI_SID" > "$tmp_map"', "LuCI bridge CGI")
require_text(controller, "ubus.call('session', 'destroy', { ubus_rpc_session: ctx.authsession })", "LuCI logout controller")
require_text(controller, '<form id="cr6608-logout" method="post" action="/cgi-bin/dashlogout">', "LuCI logout controller")
require_text(controller, '<input type="hidden" name="redirect" value="1">', "LuCI logout controller")
require_text(controller, "document.getElementById('cr6608-logout').submit()", "LuCI logout controller")

ordered(
    reaper,
    [
        ". /usr/libexec/cr6608-session-auth || exit 1",
        "cr6608_session_storage_prepare || exit 1",
        "cr6608_map_storage_prepare || exit 1",
        "cr6608_luci_session_lock || exit 1",
        "for session_file in /tmp/dashsess/*; do",
        'cr6608_session_valid "$sid" >/dev/null 2>&1 || true',
        "for map_file in /tmp/dashluci/*; do",
        'if ! { [ -f "/tmp/dashsess/$sid" ] && [ ! -L "/tmp/dashsess/$sid" ]; }; then',
        'cr6608_revoke_session_unlocked "$sid" || exit 1',
    ],
    "session reaper",
)
require(
    reaper.count('cr6608_revoke_session_unlocked "$sid" || exit 1') == 1,
    "session reaper: orphan child revoke path is missing or ambiguous",
)

cron_line = "* * * * * /usr/sbin/cr6608-session-reaper >/dev/null 2>&1"
require(crontab.splitlines().count(cron_line) == 1, "root crontab: exact one-minute reaper line is missing or duplicated")
for line in crontab.splitlines():
    if "cr6608-session-reaper" in line:
        require(line == cron_line, "root crontab: non-canonical reaper invocation is present")

try:
    menu = json.loads(menu_source)
except json.JSONDecodeError as exc:
    die(f"LuCI logout menu: invalid JSON: {exc}")
require(set(menu) == {"admin/logout"}, "LuCI logout menu: unexpected or missing menu entries")
entry = menu["admin/logout"]
require(entry.get("action") == {
    "type": "function",
    "module": "luci.controller.cr6608.logout",
    "function": "action_logout",
}, "LuCI logout menu: action does not target the unified controller")
require(entry.get("depends", {}).get("acl") == ["luci-base"], "LuCI logout menu: ACL dependency is wrong")
require(entry.get("firstchild_ineligible") is True, "LuCI logout menu: logout may be selected as a first child")
PY

# Exercise the entropy function on an unprivileged Ubuntu host as a final
# contract check. Only its root-owned router storage path is relocated into a
# private host-test directory; the Python checks above bind the production path
# and exact 16-byte source before this harness runs.
entropy_tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-auth-entropy.XXXXXX")" ||
	fail "cannot create entropy harness directory"
trap 'rm -rf "$entropy_tmp"' 0 HUP INT TERM
entropy_helper="$entropy_tmp/session-auth"
sed 's|random_file="/tmp/dashsess/\.random\.\$\$"|random_file="${AUTH_TEST_TMP}/.random.$$"|' \
	"$AUTH" >"$entropy_helper" || fail "cannot prepare entropy harness"
grep -Fq 'random_file="${AUTH_TEST_TMP}/.random.$$"' "$entropy_helper" ||
	fail "entropy harness did not relocate the production scratch path"

samples="$({
	AUTH_TEST_TMP="$entropy_tmp"
	export AUTH_TEST_TMP
	. "$entropy_helper"
	cr6608_session_storage_prepare() { return 0; }
	i=0
	while [ "$i" -lt 8 ]; do
		cr6608_random_hex32 || exit 1
		printf '\n'
		i=$((i + 1))
	done
})" || fail "production entropy helper failed on the host"

[ "$(printf '%s\n' "$samples" | wc -l | tr -d '[:space:]')" = 8 ] ||
	fail "production entropy helper emitted the wrong sample count"
if printf '%s\n' "$samples" | LC_ALL=C grep -Ev '^[0-9a-f]{32}$' >/dev/null; then
	fail "production entropy helper emitted a malformed token"
fi
[ "$(printf '%s\n' "$samples" | LC_ALL=C sort -u | wc -l | tr -d '[:space:]')" = 8 ] ||
	fail "production entropy helper repeated a token in the host check"

rm -rf "$entropy_tmp"
trap - 0 HUP INT TERM

known_sid=0123456789abcdef0123456789abcdef
(
	. "$AUTH"
	ubus() { return 0; }
	cr6608_destroy_luci_session "$known_sid"
) || fail "successful LuCI child revocation was rejected"
(
	. "$AUTH"
	ubus() { return 252; }
	rc=77
	cr6608_destroy_luci_session "$known_sid"
	[ "$rc" -eq 77 ]
) || fail "already-revoked LuCI child was not idempotent"
set +e
(
	. "$AUTH"
	ubus() { return 6; }
	cr6608_destroy_luci_session "$known_sid"
)
destroy_failure_rc=$?
set -e
[ "$destroy_failure_rc" -eq 6 ] ||
	fail "non-NOT_FOUND LuCI revocation error was not fail closed"

# Mutation children run the complete positive contract above, then stop before
# recursively creating their own mutation trees. The parent binds this mode to
# the canonical copied source root so an accidental environment variable cannot
# silently disable the negative gates in a normal build.
if [ "${CR6608_AUTH_MUTATION_CHILD:-0}" = 1 ]; then
	[ -n "${CR6608_AUTH_MUTATION_ROOT:-}" ] ||
		fail "mutation child root is missing"
	mutation_root="$(CDPATH= cd -- "$CR6608_AUTH_MUTATION_ROOT" 2>/dev/null && pwd)" ||
		fail "mutation child root is invalid"
	[ "$ROOT" = "$mutation_root" ] ||
		fail "mutation child root does not match the tested source"
	exit 0
fi

mutation_tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-auth-mutations.XXXXXX")" ||
	fail "cannot create authentication mutation directory"
trap 'rm -rf "$mutation_tmp"' 0 HUP INT TERM

run_mutation() {
	mutation_name="$1"
	mutation_target="$2"
	mutation_old="$3"
	mutation_new="$4"
	mutation_expected="$5"
	mutation_root="$mutation_tmp/$mutation_name"
	mutation_output="$mutation_tmp/$mutation_name.out"

	mkdir -p "$mutation_root" ||
		fail "cannot create mutation root: $mutation_name"
	cp -a "$ROOT/." "$mutation_root/" ||
		fail "cannot copy source for mutation: $mutation_name"

	python3 - "$mutation_root/$mutation_target" "$mutation_old" "$mutation_new" <<'PY_MUTATE'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
data = path.read_text(encoding="utf-8")
count = data.count(old)
if count != 1:
    print(
        f"auth_lifecycle_test=fail: mutation token count for {path}: expected 1, got {count}",
        file=sys.stderr,
    )
    raise SystemExit(1)
path.write_text(data.replace(old, new, 1), encoding="utf-8")
PY_MUTATE

	if CR6608_AUTH_MUTATION_CHILD=1 \
		CR6608_AUTH_MUTATION_ROOT="$mutation_root" \
		sh "$mutation_root/tests/test-auth-lifecycle.sh" \
		>"$mutation_output" 2>&1
	then
		fail "mutation was accepted: $mutation_name"
	fi
	grep -Fq 'auth_lifecycle_test=fail:' "$mutation_output" ||
		fail "mutation did not fail through the contract gate: $mutation_name"
	grep -Fq "$mutation_expected" "$mutation_output" || {
		printf 'unexpected mutation output (%s):\n' "$mutation_name" >&2
		sed 's/^/  /' "$mutation_output" >&2
		fail "mutation failed for the wrong reason: $mutation_name"
	}
}

run_mutation \
	json_sid_leak \
	files/www/cgi-bin/dashlogin \
	'reply "" '\''{"ok":true}'\''' \
	'reply "" '\''{"ok":true,"sid":"deadbeef"}'\''' \
	'bearer-like value is returned in JSON'

run_mutation \
	js_sid_storage \
	files/www/dashboard.js \
	'sessionStorage.setItem(LS + "session", "cookie")' \
	'sessionStorage.setItem(LS + "session", data.sid)' \
	"dashboard: forbidden 'data.sid'"

run_mutation \
	header_sid \
	files/usr/libexec/cr6608-session-auth \
	'${HTTP_COOKIE:-}' \
	'${HTTP_X_CR6608_SESSION:-}' \
	'cookie reader'

run_mutation \
	short_entropy \
	files/usr/libexec/cr6608-session-auth \
	'bs=16 count=1' \
	'bs=8 count=1' \
	'entropy path'

run_mutation \
	unlocked_rate_limit \
	files/www/cgi-bin/dashlogin \
	'flock -x 8 || reply "503 Service Unavailable"' \
	'flock -x 8 || true' \
	'login rate limiter'

run_mutation \
	missing_logout_revoke \
	files/www/cgi-bin/dashlogout \
	'cr6608_revoke_session_unlocked "$sid" || revoke_failed=1' \
	'revoke_failed=0' \
	'logout CGI'

run_mutation \
	missing_reaper_revoke \
	files/usr/sbin/cr6608-session-reaper \
	'cr6608_revoke_session_unlocked "$sid" || exit 1' \
	'true' \
	'session reaper'

run_mutation \
	wrong_cron \
	files/etc/crontabs/root \
	'* * * * * /usr/sbin/cr6608-session-reaper >/dev/null 2>&1' \
	'*/2 * * * * /usr/sbin/cr6608-session-reaper >/dev/null 2>&1' \
	'root crontab'

run_mutation \
	wrong_menu_module \
	files/usr/share/luci/menu.d/zz-cr6608-logout.json \
	'luci.controller.cr6608.logout' \
	'cr6608.logout' \
	'LuCI logout menu'

rm -rf "$mutation_tmp"
trap - 0 HUP INT TERM

printf 'auth_lifecycle_test=pass\n'
printf 'auth_lifecycle_negative_tests=pass\n'
