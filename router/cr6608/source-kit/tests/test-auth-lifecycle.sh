#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FILES="$ROOT/files"
AUTH="$FILES/usr/libexec/cr6608-session-auth"
LOGIN="$FILES/www/cgi-bin/dashlogin"
LUCI="$FILES/www/cgi-bin/dashluci"
LOGOUT="$FILES/www/cgi-bin/dashlogout"
DASHCTL="$FILES/www/cgi-bin/dashctl"
DASHAPI="$FILES/www/cgi-bin/dashapi"
DASHACTION="$FILES/www/cgi-bin/dashaction"
QUICK_APPLY="$FILES/www/cgi-bin/cr6608-quick-apply"
QUICK_CONFIRM="$FILES/www/cgi-bin/cr6608-quick-confirm"
DASHBOARD="$FILES/www/dashboard.js"
LOGOUT_CONTROLLER="$FILES/usr/share/ucode/luci/controller/cr6608/logout.uc"
LOGOUT_MENU="$FILES/usr/share/luci/menu.d/zz-cr6608-logout.json"
REAPER="$FILES/usr/sbin/cr6608-session-reaper"
ROOT_CRONTAB="$FILES/etc/crontabs/root"
SYSTEM_CONFIG="$FILES/etc/config/system"
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
	"$DASHCTL" \
	"$DASHAPI" \
	"$DASHACTION" \
	"$QUICK_APPLY" \
	"$QUICK_CONFIRM" \
	"$DASHBOARD" \
	"$LOGOUT_CONTROLLER" \
	"$LOGOUT_MENU" \
	"$REAPER" \
	"$ROOT_CRONTAB" \
	"$SYSTEM_CONFIG" \
	"$ROOT_PASSWORD_DEFAULT" \
	"$SHADOW"
do
	[ -f "$file" ] && [ ! -L "$file" ] && [ -s "$file" ] ||
		fail "missing, empty, or symlinked source: $file"
done

grep -Fq "option cronloglevel '9'" "$SYSTEM_CONFIG" ||
	fail "successful one-minute session reaping would flood the in-memory error log"
grep -Fq 'logger -t cr6608-session-reaper' "$REAPER" ||
	fail "quiet cron policy would hide a real session reaper failure"

shadow_hash="$(awk -F: '$1 == "root" { print $2; exit }' "$SHADOW")"
case "$shadow_hash" in
	'$6$CR6608v74op$'*) : ;;
	*) fail "operator-image root account does not use SHA-512 crypt" ;;
esac
[ "$(printf %s "$shadow_hash" | sha256sum | awk '{print $1}')" = \
	'b6139c45d43bc9a0262c02a42d8784da248e498eda9434e3cb673dbd4cf40ebe' ] || \
	fail "operator-image root credential hash changed unexpectedly"
grep -Fq "option ttylogin '1'" "$SYSTEM_CONFIG" ||
	fail "operator-image serial console is not password-gated"
! grep -Eq "^[[:space:]]*(pinned_hash|legacy_hash)=" "$ROOT_PASSWORD_DEFAULT" || \
	fail "first-boot migration still embeds a shared root credential"
grep -Fq 'shadow_file="${CR6608_SHADOW_FILE:-/etc/shadow}"' "$ROOT_PASSWORD_DEFAULT" || \
	fail "root migration lacks the testable/preserved shadow path"
grep -Fq 'classifies that shared credential as non-retail' "$ROOT_PASSWORD_DEFAULT" || \
	fail "keep-settings operator-password preservation is undocumented"

for script in "$AUTH" "$LOGIN" "$LUCI" "$LOGOUT" "$DASHCTL" "$DASHAPI" "$DASHACTION" "$QUICK_APPLY" "$QUICK_CONFIRM" "$REAPER"; do
	sh -n "$script" || fail "shell syntax rejected: $script"
done

python3 - \
	"$AUTH" "$LOGIN" "$LUCI" "$LOGOUT" "$DASHCTL" "$DASHAPI" "$DASHACTION" "$QUICK_APPLY" "$QUICK_CONFIRM" "$DASHBOARD" \
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
    dashctl_path,
    dashapi_path,
    dashaction_path,
    quick_apply_path,
    quick_confirm_path,
    dashboard_path,
    controller_path,
    menu_path,
    reaper_path,
    crontab_path,
) = paths
auth, login, luci, logout, dashctl, dashapi, dashaction, quick_apply, quick_confirm, dashboard, controller, menu_source, reaper, crontab = [
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

cookie_name = shell_function(auth, "cr6608_session_cookie_name", "session helper")
luci_cookie_name = shell_function(auth, "cr6608_luci_session_cookie_name", "session helper")
cookie_lookup = shell_function(auth, "cr6608_cookie_value_unique", "session helper")
cookie_reader = shell_function(auth, "cr6608_session_from_request", "session helper")
require_text(cookie_name, '[ "${HTTPS:-off}" = on ]', "protocol cookie selector")
require_text(cookie_name, "cr6608_sid_https", "protocol cookie selector")
require_text(cookie_name, "cr6608_sid_http", "protocol cookie selector")
require_text(luci_cookie_name, "sysauth_https", "LuCI protocol cookie selector")
require_text(luci_cookie_name, "sysauth_http", "LuCI protocol cookie selector")
require_text(cookie_lookup, '${HTTP_COOKIE:-}', "cookie lookup")
require_text(cookie_lookup, '[ "$count" = 1 ]', "cookie lookup")
require_text(cookie_lookup, 'cr6608_valid_hex32 "$value" || return 1', "cookie lookup")
ordered(
    cookie_reader,
    [
        'cookie_name="$(cr6608_session_cookie_name)"',
        'cr6608_cookie_value_unique "$cookie_name"',
        'case "$cookie_rc" in',
        '1) printf \'%s\' \'\'; return 0',
        'cr6608_cookie_value_unique cr6608_sid',
    ],
    "protocol cookie migration",
)
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
for forbidden_input in ("HTTP_X_CR6608_SESSION", "HTTP_AUTHORIZATION", "QUERY_STRING", "REQUEST_URI", "POST_DATA", "BODY"):
    forbid_text(auth, forbidden_input, "cookie lookup")
for label, source in (("quick apply CGI", quick_apply), ("quick confirm CGI", quick_confirm)):
    forbid_text(source, "${HTTP_COOKIE:-}", label)
    require_text(source, "cr6608_luci_session_cookie_name", label)
    require_text(source, "cr6608_cookie_value_unique", label)

destroy_child = shell_function(auth, "cr6608_destroy_luci_session", "session helper")
ordered(
    destroy_child,
    [
        'local luci_sid="$1"',
        'local destroy_rc=0',
        'cr6608_ubus call session destroy',
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

luci_state = shell_function(auth, "cr6608_luci_session_state", "session helper")
ordered(
    luci_state,
    [
        'cr6608_valid_hex32 "$luci_sid" || return 1',
        'cr6608_ubus -S call session access',
        '\\"scope\\":\\"access-group\\"',
        '\\"object\\":\\"luci-base\\"',
        '\\"function\\":\\"read\\"',
        'access_rc=$?',
        '4|252) return 1',
        'CR6608_JSONFILTER_BIN:-/usr/bin/jsonfilter',
        "-e '@.access'",
        'true|1) return 0',
        'false|0) return 1',
        'return 2',
    ],
    "bounded LuCI rpcd session validation",
)
for forbidden in ('/bin/ubus call session access', 'rm -f', 'session destroy'):
    forbid_text(luci_state, forbidden, "bounded LuCI rpcd session validation")

auth_surfaces = {
    "session helper": auth,
    "login CGI": login,
    "LuCI bridge CGI": luci,
    "logout CGI": logout,
    "dashboard control CGI": dashctl,
    "dashboard API CGI": dashapi,
    "dashboard action CGI": dashaction,
    "quick apply CGI": quick_apply,
    "quick confirm CGI": quick_confirm,
    "dashboard": dashboard,
}
for label, source in auth_surfaces.items():
    forbid_text(source, "HTTP_X_CR6608_SESSION", label)
    forbid_text(source, "X-CR6608-Session", label)
    forbid_text(source, "Authorization: Bearer", label)

for label, source in (
    ("login CGI", login),
    ("LuCI bridge CGI", luci),
    ("logout CGI", logout),
    ("dashboard control CGI", dashctl),
    ("dashboard API CGI", dashapi),
    ("dashboard action CGI", dashaction),
    ("quick apply CGI", quick_apply),
    ("quick confirm CGI", quick_confirm),
):
    for line in source.splitlines():
        if "cr6608_session_from_request" in line:
            require(
                re.search(r"cr6608_session_from_request\s*\)", line) is not None,
                f"{label}: session helper is called with request-supplied arguments",
            )
for label, source in (("login CGI", login), ("LuCI bridge CGI", luci), ("logout CGI", logout)):
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

# Successful JSON replies are status-only. Both bearers are set as HttpOnly,
# SameSite cookies and never appear in a JSON key or browser-readable value.
for label, source in (("login CGI", login), ("LuCI bridge CGI", luci), ("logout CGI", logout)):
    for line in source.splitlines():
        if "{" in line and "}" in line and ("reply" in line or "printf" in line):
            require(
                re.search(r'["\'](?:sid|session|token|ubus_rpc_session)["\']\s*:', line) is None,
                f"{label}: a bearer-like value is returned in JSON",
            )
require_text(login, "reply \"\" '{\"ok\":true}'", "login CGI")
require_text(login, 'now="$(cr6608_uptime_seconds)"', "login monotonic rate limiter")
forbid_text(login, 'now="$(date +%s', "login monotonic rate limiter")
require_text(login, '[ "$now" -ge "$window" ]', "login clock-rollback recovery")
require_text(logout, "printf '{\"ok\":true}\\n'", "logout CGI")
require_text(login, "Set-Cookie: %s", "login CGI")
require_text(login, "HttpOnly; SameSite=Strict", "login CGI")
require_text(login, 'cookie_name="$(cr6608_session_cookie_name)"', "login CGI")
require_text(
    login,
    'SET_COOKIE="$cookie_name=$tok; Path=/;${secure_cookie} HttpOnly; SameSite=Strict"',
    "session-only successful login cookie",
)
forbid_text(
    login,
    'SET_COOKIE="$cookie_name=$tok; Path=/; Max-Age=',
    "persistent successful login cookie",
)
require_text(login, 'CLEAR_LEGACY_COOKIE="cr6608_sid=; Path=/; Max-Age=0;', "login CGI")
require_text(luci, "HttpOnly; SameSite=Strict", "LuCI bridge CGI")

# Every Smart AP JSON surface emits clickjacking policy as real HTTP headers.
# Counts cover each independent early-error header path, not only success.
for label, source, minimum in (
    ("login CGI", login, 1),
    ("LuCI bridge CGI", luci, 1),
    ("logout CGI", logout, 2),
    ("dashboard control CGI", dashctl, 5),
    ("dashboard API CGI", dashapi, 2),
    ("dashboard action CGI", dashaction, 4),
    ("quick apply CGI", quick_apply, 1),
    ("quick confirm CGI", quick_confirm, 1),
):
    require(source.count("X-Frame-Options:") >= minimum, f"{label}: X-Frame-Options is missing from a response path")
    require(source.count("frame-ancestors") >= minimum, f"{label}: CSP frame-ancestors is missing from a response path")

require_text(controller, "http.header('X-Frame-Options', 'DENY')", "LuCI logout controller")
require_text(controller, "frame-ancestors 'none'", "LuCI logout controller")
require_text(controller, "script-src 'sha256-", "LuCI logout controller")

# Smart AP must not expose or implement a path that changes the developer's
# SSH/serial-console credential.
require_text(dashctl, 'set_admin_password)', "locked admin password action")
require_text(dashctl, 'The SSH/console root password cannot be changed from Smart AP.', "locked admin password action")
forbid_text(dashctl, 'passwd root', "locked admin password action")
forbid_text(dashctl, 'root_password_param()', "locked admin password action")
forbid_text(dashctl, 'valid_root_password()', "locked admin password action")
for required_bridge_token in (
    '[ "${REQUEST_METHOD:-GET}" = POST ]',
    "cr6608_session_from_request",
    "cr6608_luci_session_lock",
    'map_file="$map_dir/$request_sid"',
    'cr6608_valid_hex32 "$mapped_luci_sid"',
    "set_luci_cookie",
    "luci_session_reauthentication_required",
    '"target":"/cgi-bin/luci/admin/network/wireless"',
):
    require_text(luci, required_bridge_token, "LuCI bridge CGI")
for forbidden_bridge_token in (
    "session create",
    "session grant",
    "grant_access_groups",
    "grant_pairs",
    "ACL_HELPER",
):
    forbid_text(luci, forbidden_bridge_token, "bounded LuCI bridge CGI")

for forbidden_js in (
    "data.sid",
    "data.session",
    "data.token",
    "response.sid",
    "response.session",
    "response.token",
    "localStorage.setItem(LS + \"session\"",
    "localStorage",
    "sessionStorage",
):
    forbid_text(dashboard, forbidden_js, "dashboard")
require(
    re.search(r'function\s+sidQuery\(\)\s*\{\s*return\s+["\']session_cookie=1["\'];\s*\}', dashboard)
    is not None,
    "dashboard: request bodies must carry only the harmless cookie marker",
)
login_js = js_function(dashboard, "login", "dashboard")
require_text(login_js, 'credentials: "same-origin"', "dashboard login request")
ordered(
    login_js,
    [
        'state.session = "cookie"',
        "showDashboard()",
    ],
    "dashboard login must open Smart AP after authentication",
)
forbid_text(login_js, "ensureLuciSession", "dashboard login request")
luci_js = js_function(dashboard, "ensureLuciSession", "dashboard")
require_text(luci_js, 'credentials: "same-origin"', "dashboard LuCI session request")
require_text(luci_js, 'method: "POST"', "dashboard LuCI session request")
require_text(luci_js, 'fetchWithTimeout("/cgi-bin/dashluci"', "dashboard LuCI session request")
require_text(dashboard, "e.status === 409", "dashboard LuCI reauthentication path")
require_text(
    dashboard,
    'window.location.assign("/cgi-bin/luci/admin/network/wireless")',
    "dashboard OpenWrt settings navigation",
)
require_text(dashboard, "if (transientAttempts >= 2)", "bounded startup session recovery")
require_text(dashboard, 'showLogin(tr("loginUnavailable"), false)', "bounded startup session recovery")
ordered(
    luci,
    [
        'cr6608_luci_session_lock',
        'read -r mapped_luci_sid extra < "$map_file"',
        'cr6608_luci_session_state "$mapped_luci_sid"',
        'mapped_rc=$?',
        '1)',
        'rm -f "$map_file"',
        'luci_session_reauthentication_required',
        'luci_session_service_unavailable',
    ],
    "Smart-to-LuCI live rpcd validation",
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
        'flock -xn 8 || reply "503 Service Unavailable"',
        'if [ -r "$rate_file" ]; then',
        'read -r fails window < "$rate_file"',
        'if [ "$fails" -ge 5 ]',
        "login_failed()",
        '>"$rate_file"',
        'rm -f "$rate_file"',
    ],
    "login rate limiter",
)
flock_line = next((line for line in login.splitlines() if "flock -xn 8" in line), "")
require("|| reply \"503 Service Unavailable\"" in flock_line, "login rate limiter: flock is not fail closed")
require("flock -xn 8" in flock_line, "login rate limiter: flock can block a CGI worker")
for line_number, line in enumerate(login.splitlines(), 1):
    if "$rate_file" not in line:
        continue
    if line.strip() in ('rate_file="$RATE_DIR/$rate_id"', 'rate_lock="$rate_file.lock"'):
        continue
    flock_number = login[: login.find('flock -xn 8 || reply "503 Service Unavailable"')].count("\n") + 1
    require(line_number > flock_number, f"login rate limiter: rate state is accessed before flock on line {line_number}")
require(
    re.search(r'>"\$rate_file"\s*\|\|\s*\n?\s*reply "503 Service Unavailable"', login) is not None,
    "login rate limiter: failed counter writes are not fail closed",
)
require(
    re.search(r'rm -f "\$rate_file"[^\n]*\|\|\s*reply "503 Service Unavailable"', login) is not None,
    "login rate limiter: successful-login reset is not fail closed",
)

# Smart AP authenticates rpcd's standard root-password indirection through
# ubus.  The authenticated, fully authorized rpcd session is retained and
# privately mapped to Smart AP instead of creating/granting a second session.
for needle in (
    "/usr/share/libubox/jshn.sh",
    'json_add_string username "$user"',
    'json_add_string password "$pass"',
    'cr6608_ubus -S call session login "$login_request"',
    "@.ubus_rpc_session",
    'json_add_int timeout 3600',
    'PENDING_LUCI_SID="$login_sid"',
    'json_add_string ubus_rpc_session "$login_sid"',
    'json_add_string token "$luci_csrf_token"',
    'cr6608_ubus call session set "$(json_dump)"',
    'cr6608_write_luci_map_unlocked "$tok" "$login_sid"',
    'PENDING_LUCI_SID=""',
    "unset pass login_request login_reply",
):
    require_text(login, needle, "rpcd web credential authentication")
for stale_auth in ("web_salt=", "web_hash="):
    forbid_text(login, stale_auth, "rpcd web credential authentication")
ordered(
    login,
    [
        'json_add_string password "$pass"',
        'cr6608_ubus -S call session login "$login_request"',
        'cr6608_valid_hex32 "$login_sid"',
        'PENDING_LUCI_SID="$login_sid"',
        "unset pass login_request login_reply",
        'rm -f "$rate_file"',
        'cr6608_luci_session_lock',
        'cr6608_ubus call session set "$(json_dump)"',
        'cr6608_write_luci_map_unlocked "$tok" "$login_sid"',
        'PENDING_LUCI_SID=""',
        "unset login_sid",
    ],
    "rpcd web credential authentication",
)
require(
    login.find('session destroy "$(json_dump)"') < 0,
    "rpcd web credential authentication: authenticated LuCI session is destroyed before use",
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
require_text(
    revoke,
    'if cr6608_destroy_luci_session "$luci_sid"; then',
    "failed LuCI destroy map preservation",
)
destroy_failure_tail = revoke[revoke.find('if cr6608_destroy_luci_session "$luci_sid"; then'):]
require(
    re.search(
        r'if cr6608_destroy_luci_session "\$luci_sid"; then\s*'
        r'rm -f "\$map_file" \|\| rc=1\s*else\s*.*?\s+rc=1\s*fi',
        destroy_failure_tail,
        re.S,
    ) is not None,
    "failed LuCI destroy can discard the only retryable map",
)
pending_mark = shell_function(auth, "cr6608_mark_revoke_pending", "session helper")
ordered(
    pending_mark,
    [
        'cr6608_session_reference_exists "$smart_sid"',
        "cr6608_pending_revoke_storage_prepare",
        'pending_file="/tmp/dashrevoke/$smart_sid"',
        'mv -f "$pending_tmp" "$pending_file"',
    ],
    "pending logout marker",
)
require_text(pending_mark, 'chmod 0600 "$pending_tmp"', "pending logout marker mode")
session_unlock = shell_function(auth, "cr6608_luci_session_unlock", "session helper")
ordered(
    session_unlock,
    [
        '[ "${CR6608_LUCI_SESSION_LOCK_OWNER:-0}" = 1 ] || return 0',
        "flock -u 9",
        "exec 9>&-",
        "CR6608_LUCI_SESSION_LOCK_OWNER=0",
    ],
    "session lock unlock",
)
session_lock = shell_function(auth, "cr6608_luci_session_lock", "session helper")
require_text(session_lock, '[ "${CR6608_LUCI_SESSION_LOCK_OWNER:-0}" = 1 ] && return 0', "session lock ownership")
require_text(session_lock, "CR6608_LUCI_SESSION_LOCK_OWNER=1", "session lock ownership")
require(session_lock.count("flock -xn 9") == 2, "session lock: expected one bounded acquisition retry")
require_text(session_lock, "sleep 1", "session lock bounded acquisition retry")
require(session_lock.count("exec 9>&-") >= 3, "session lock: failed acquisition paths do not close fd 9")
for forbidden in ("rm ", "unlink"):
    forbid_text(session_lock, forbidden, "session lock inode stability")
    forbid_text(session_unlock, forbidden, "session unlock inode stability")
forbid_text(auth, 'rm -f "/tmp/dashsess/.luci-session.lock"', "session lock inode stability")

login_reply = shell_function(login, "reply", "login CGI")
ordered(
    login_reply,
    ["cleanup_pending_luci_session", "cr6608_luci_session_unlock", "printf 'Status: %s"],
    "login reply lock release",
)
luci_reply = shell_function(luci, "reply", "LuCI bridge CGI")
ordered(
    luci_reply,
    ["cr6608_luci_session_unlock", "printf 'Status: %s"],
    "LuCI bridge reply lock release",
)
reaper_exit = shell_function(reaper, "session_reaper_exit", "session reaper")
ordered(
    reaper_exit,
    ["trap - EXIT", "cr6608_luci_session_unlock", 'exit "$rc"'],
    "session reaper lock release",
)
session_valid = shell_function(auth, "cr6608_session_valid", "session helper")
expiry_guard = 'if [ "$age" -lt 0 ] 2>/dev/null || [ "$age" -gt 3600 ] 2>/dev/null; then'
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
        'cr6608_mark_revoke_pending "$sid"',
        "cr6608_luci_session_unlock",
        "Status: 503 Service Unavailable",
        "Retry-After: 1",
        "Set-Cookie: cr6608_sid_http=;",
        "Set-Cookie: cr6608_sid_https=;",
        "Set-Cookie: cr6608_sid=;",
        "Set-Cookie: sysauth_http=;",
        "Set-Cookie: sysauth_https=;",
    ],
    "logout CGI",
)
require_text(logout, '"revocation_failed"', "logout CGI")
require_text(
    logout,
    'if cr6608_session_reference_exists "$sid"; then',
    "lock-busy logout reference preservation",
)
require_text(logout, "Location: /?logged_out=1", "logout CGI")
for cookie_line in (
    "Set-Cookie: cr6608_sid_http=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict",
    "Set-Cookie: cr6608_sid_https=; Path=/; Max-Age=0; Secure; HttpOnly; SameSite=Strict",
    "Set-Cookie: cr6608_sid=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict",
    "Set-Cookie: sysauth_http=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict",
    "Set-Cookie: sysauth_https=; Path=/; Max-Age=0; Secure; HttpOnly; SameSite=Strict",
    "Set-Cookie: sysauth_http=; Path=/cgi-bin/luci/; Max-Age=0; HttpOnly; SameSite=Strict",
    "Set-Cookie: sysauth_https=; Path=/cgi-bin/luci/; Max-Age=0; Secure; HttpOnly; SameSite=Strict",
):
    require_text(logout, cookie_line, "logout CGI")

revoke_js = js_function(dashboard, "revokeServerSessions", "dashboard")
require_text(revoke_js, 'fetchWithTimeout("/cgi-bin/dashlogout"', "dashboard logout request")
require_text(revoke_js, 'method: "POST"', "dashboard logout request")
require_text(revoke_js, 'credentials: "same-origin"', "dashboard logout request")
require_text(revoke_js, "}, 8000)", "dashboard logout request timeout")
require_text(revoke_js, "if (!res.ok || !data.ok)", "dashboard logout request")
require_text(revoke_js, "revokeError.serverResponded = true", "dashboard logout response convergence")
logout_js = js_function(dashboard, "logout", "dashboard")
ordered(
    logout_js,
    [
        "await revokeServerSessions()",
        'state.session = ""',
        'showLogin(tr("loggedOut"), false)',
    ],
    "dashboard logout",
)
require_text(logout_js, "e.serverResponded === true", "dashboard logout response convergence")
forbid_text(revoke_js, "Retry-After", "cookie-less logout retry")

ordered(
    reaper,
    [
        "cr6608_pending_revoke_storage_prepare",
        "cr6608_luci_session_lock",
        "for pending_file in /tmp/dashrevoke/*",
        'cr6608_revoke_session_unlocked "$sid"',
        'cr6608_clear_revoke_pending "$sid"',
        "for session_file in /tmp/dashsess/*",
    ],
    "pending logout reaper",
)

require_text(controller, "ubus.call('session', 'destroy', { ubus_rpc_session: ctx.authsession })", "LuCI logout controller")
require_text(controller, '<form id="cr6608-logout" method="post" action="/cgi-bin/dashlogout">', "LuCI logout controller")
require_text(controller, '<input type="hidden" name="redirect" value="1">', "LuCI logout controller")
require_text(controller, "document.getElementById('cr6608-logout').submit()", "LuCI logout controller")
require_text(dashboard, 'new URLSearchParams(window.location.search).get("logged_out") === "1"', "LuCI logout landing state")
require_text(dashboard, 'showLogin(tr("loggedOut"), false)', "LuCI logout landing state")

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
        'continue',
        'cr6608_path_owned_by_root "$map_file"',
        'read -r mapped_luci_sid extra <"$map_file"',
        'cr6608_luci_session_state "$mapped_luci_sid"',
        'mapped_state=$?',
        'cr6608_destroy_luci_session "$mapped_luci_sid" || exit 1',
        'rm -f "$map_file" || exit 1',
        'exit 1',
    ],
    "session reaper",
)
require(
    reaper.count('cr6608_revoke_session_unlocked "$sid" || exit 1') == 2,
    "session reaper: pending and orphan child revoke paths are missing or ambiguous",
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

# Exercise the production fd-9 lock functions from an unprivileged host-safe
# relocation. An inherited child must not extend the critical section after an
# explicit unlock, and every failed acquisition must close its fd.
lock_tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-auth-lock.XXXXXX")" ||
	fail "cannot create session lock harness directory"
trap 'rm -rf "$lock_tmp"' 0 HUP INT TERM
lock_helper="$lock_tmp/session-auth"
sed "s|/tmp/dashsess|$lock_tmp/dashsess|g" "$AUTH" >"$lock_helper" ||
	fail "cannot prepare session lock harness"
(
	. "$lock_helper"
	cr6608_session_storage_prepare() {
		mkdir -p "$lock_tmp/dashsess" && chmod 0700 "$lock_tmp/dashsess"
	}
	cr6608_path_owned_by_root() { [ -e "$1" ] && [ ! -L "$1" ]; }

	cr6608_luci_session_lock || exit 1
	[ "$CR6608_LUCI_SESSION_LOCK_OWNER" = 1 ] || exit 1
	[ -e /proc/self/fd/9 ] || exit 1
	sleep 10 & inherited_child=$!
	cr6608_luci_session_unlock || exit 1
	[ "$CR6608_LUCI_SESSION_LOCK_OWNER" = 0 ] || exit 1
	[ ! -e /proc/self/fd/9 ] || exit 1
	kill -0 "$inherited_child" 2>/dev/null || exit 1
	exec 7>>"$lock_tmp/dashsess/.luci-session.lock" || exit 1
	flock -xn 7 || exit 1
	flock -u 7 || exit 1
	exec 7>&-
	kill "$inherited_child" 2>/dev/null || true
	wait "$inherited_child" 2>/dev/null || true
	cr6608_luci_session_unlock || exit 1

	exec 7>>"$lock_tmp/dashsess/.luci-session.lock" || exit 1
	flock -xn 7 || exit 1
	if cr6608_luci_session_lock; then exit 1; fi
	[ "$CR6608_LUCI_SESSION_LOCK_OWNER" = 0 ] || exit 1
	[ ! -e /proc/self/fd/9 ] || exit 1
	flock -u 7 || exit 1
	exec 7>&-

	rm -f "$lock_tmp/dashsess/.luci-session.lock" || exit 1
	cr6608_path_owned_by_root() { return 1; }
	if cr6608_luci_session_lock; then exit 1; fi
	[ ! -e /proc/self/fd/9 ] || exit 1
) || fail "production session lock release harness failed"
rm -rf "$lock_tmp"
trap - 0 HUP INT TERM

known_sid=0123456789abcdef0123456789abcdef
(
	. "$AUTH"
	cr6608_ubus() { return 0; }
	cr6608_destroy_luci_session "$known_sid"
) || fail "successful LuCI child revocation was rejected"
(
	. "$AUTH"
	cr6608_ubus() { return 252; }
	rc=77
	cr6608_destroy_luci_session "$known_sid"
	[ "$rc" -eq 77 ]
) || fail "already-revoked LuCI child was not idempotent"
set +e
(
	. "$AUTH"
	cr6608_ubus() { return 6; }
	cr6608_destroy_luci_session "$known_sid"
)
destroy_failure_rc=$?
set -e
[ "$destroy_failure_rc" -eq 6 ] ||
	fail "non-NOT_FOUND LuCI revocation error was not fail closed"

# Exercise the production cookie selector. Preferred protocol cookies are
# isolated, legacy migration is accepted only when preferred is absent, and
# duplicate/malformed preferred cookies fail closed instead of falling back.
http_sid=11111111111111111111111111111111
https_sid=22222222222222222222222222222222
legacy_sid=33333333333333333333333333333333
read_smart_cookie() (
	HTTPS="$1"
	HTTP_COOKIE="$2"
	export HTTPS HTTP_COOKIE
	. "$AUTH"
	cr6608_session_from_request
)
expect_smart_cookie() {
	_cookie_label="$1"; _cookie_expected="$2"; _cookie_https="$3"; _cookie_header="$4"
	_cookie_actual="$(read_smart_cookie "$_cookie_https" "$_cookie_header")" ||
		fail "cookie selector execution failed: $_cookie_label"
	[ "$_cookie_actual" = "$_cookie_expected" ] ||
		fail "cookie selector mismatch ($_cookie_label): expected '$_cookie_expected', got '$_cookie_actual'"
}
expect_smart_cookie http_preferred "$http_sid" off "cr6608_sid_https=$https_sid; cr6608_sid_http=$http_sid"
expect_smart_cookie https_preferred "$https_sid" on "cr6608_sid_http=$http_sid; cr6608_sid_https=$https_sid"
expect_smart_cookie http_rejects_https "" off "cr6608_sid_https=$https_sid"
expect_smart_cookie https_rejects_http "" on "cr6608_sid_http=$http_sid"
expect_smart_cookie http_legacy_migration "$legacy_sid" off "cr6608_sid=$legacy_sid"
expect_smart_cookie https_legacy_migration "$legacy_sid" on "cr6608_sid=$legacy_sid"
expect_smart_cookie malformed_preferred_no_fallback "" off "cr6608_sid_http=bad; cr6608_sid=$legacy_sid"
expect_smart_cookie empty_preferred_no_fallback "" on "cr6608_sid_https=; cr6608_sid=$legacy_sid"
expect_smart_cookie duplicate_preferred_no_fallback "" off "cr6608_sid_http=$http_sid; cr6608_sid_http=$http_sid; cr6608_sid=$legacy_sid"
expect_smart_cookie duplicate_legacy_rejected "" off "cr6608_sid=$legacy_sid; cr6608_sid=$legacy_sid"
[ "$(HTTPS=off; export HTTPS; . "$AUTH"; cr6608_luci_session_cookie_name)" = sysauth_http ] ||
	fail "HTTP LuCI cookie selector mismatch"
[ "$(HTTPS=on; export HTTPS; . "$AUTH"; cr6608_luci_session_cookie_name)" = sysauth_https ] ||
	fail "HTTPS LuCI cookie selector mismatch"

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

	CR6608_MUTATION_OLD="$mutation_old" CR6608_MUTATION_NEW="$mutation_new" \
		python3 - "$mutation_root/$mutation_target" <<'PY_MUTATE'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old = os.environ["CR6608_MUTATION_OLD"]
new = os.environ["CR6608_MUTATION_NEW"]
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
	'toast(tr("loginOk"));' \
	'state.session = data.sid; toast(tr("loginOk"));' \
	"dashboard: forbidden 'data.sid'"

run_mutation \
	header_sid \
	files/usr/libexec/cr6608-session-auth \
	'${HTTP_COOKIE:-}' \
	'${HTTP_X_CR6608_SESSION:-}' \
	'cookie lookup'

run_mutation \
	https_cookie_alias \
	files/usr/libexec/cr6608-session-auth \
	'printf '\''%s'\'' cr6608_sid_https' \
	'printf '\''%s'\'' cr6608_sid_http' \
	'protocol cookie selector'

run_mutation \
	duplicate_cookie_acceptance \
	files/usr/libexec/cr6608-session-auth \
	'[ "$count" = 1 ]' \
	'[ "$count" -ge 1 ]' \
	'cookie lookup'

run_mutation \
	missing_login_frame_header \
	files/www/cgi-bin/dashlogin \
	'X-Frame-Options: DENY' \
	'Frame-Guard: DENY' \
	'login CGI: X-Frame-Options'

run_mutation \
	short_entropy \
	files/usr/libexec/cr6608-session-auth \
	'bs=16 count=1' \
	'bs=8 count=1' \
	'entropy path'

run_mutation \
	unlocked_rate_limit \
	files/www/cgi-bin/dashlogin \
	'flock -xn 8 || reply "503 Service Unavailable"' \
	'flock -xn 8 || true' \
	'login rate limiter'

run_mutation \
	missing_session_unlock \
	files/usr/libexec/cr6608-session-auth \
	'flock -u 9 >/dev/null 2>&1 || true' \
	'true' \
	'session lock unlock'

run_mutation \
	missing_logout_revoke \
	files/www/cgi-bin/dashlogout \
	'if cr6608_revoke_session_unlocked "$sid"; then' \
	'if true; then' \
	'logout CGI'

run_mutation \
	missing_pending_reaper_clear \
	files/usr/sbin/cr6608-session-reaper \
	'cr6608_clear_revoke_pending "$sid" || exit 1' \
	'true' \
	'pending logout reaper'

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
printf 'auth_protocol_cookie_tests=pass\n'
