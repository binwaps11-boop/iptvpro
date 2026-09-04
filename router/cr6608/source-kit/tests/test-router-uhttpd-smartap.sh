#!/bin/sh

set -eu

SERVER="${CR6608_TEST_UHTTPD_BIN:-/tmp/uhttpd-v55-test}"
MODULE="${CR6608_TEST_UHTTPD_UCODE:-/tmp/uhttpd_ucode.so}"
HANDLER="${CR6608_TEST_LUCI_HANDLER:-/usr/share/ucode/luci/uhttpd.uc}"
PORT="${CR6608_TEST_UHTTPD_PORT:-18080}"
TLS_PORT="${CR6608_TEST_UHTTPD_TLS_PORT:-18443}"
INCOMPLETE_PORT="${CR6608_TEST_UHTTPD_INCOMPLETE_PORT:-18082}"
HEADERS="${CR6608_TEST_UHTTPD_HEADERS:-/etc/uhttpd/security-headers.json}"
CERT="${CR6608_TEST_UHTTPD_CERT:-/etc/uhttpd.crt}"
KEY="${CR6608_TEST_UHTTPD_KEY:-/etc/uhttpd.key}"
LOG="/tmp/cr6608-uhttpd-smartap-test.$$.log"
PIPELINE="/tmp/cr6608-uhttpd-smartap-pipeline.$$.out"
PIPELINE_CHUNKED="/tmp/cr6608-uhttpd-smartap-pipeline-chunked.$$.out"
PIPELINE_CONSUMED="/tmp/cr6608-uhttpd-smartap-pipeline-consumed.$$.out"
INCOMPLETE_LOG="/tmp/cr6608-uhttpd-incomplete.$$.log"
INCOMPLETE_ROOT="/tmp/cr6608-uhttpd-incomplete-root.$$"
INCOMPLETE_CGI="${INCOMPLETE_ROOT}/cgi-bin/incomplete"

fail() {
	printf 'uhttpd_smartap_runtime=fail: %s\n' "$*" >&2
	exit 1
}

for command_name in curl nc sed grep tr head wc; do
	command -v "$command_name" >/dev/null 2>&1 || fail "missing $command_name"
done
[ -x "$SERVER" ] || fail "test uhttpd is not executable: $SERVER"
[ -x "$MODULE" ] || fail "test ucode module is not executable: $MODULE"
[ -r "$HANDLER" ] || fail "LuCI ucode handler is not readable: $HANDLER"
[ -f "$HEADERS" ] && [ ! -L "$HEADERS" ] && [ -s "$HEADERS" ] || fail "security-header JSON is not a regular file: $HEADERS"
[ -f "$CERT" ] && [ ! -L "$CERT" ] && [ -s "$CERT" ] || fail "TLS certificate is not a regular file: $CERT"
[ -f "$KEY" ] && [ ! -L "$KEY" ] && [ -s "$KEY" ] || fail "TLS key is not a regular file: $KEY"
case "$PORT" in ''|*[!0-9]*) fail 'invalid port' ;; esac
[ "$PORT" -ge 1024 ] 2>/dev/null && [ "$PORT" -le 65535 ] 2>/dev/null || fail 'unsafe port'
case "$TLS_PORT" in ''|*[!0-9]*) fail 'invalid TLS port' ;; esac
[ "$TLS_PORT" -ge 1024 ] 2>/dev/null && [ "$TLS_PORT" -le 65535 ] 2>/dev/null || fail 'unsafe TLS port'
[ "$PORT" != "$TLS_PORT" ] || fail 'HTTP and HTTPS test ports must differ'
case "$INCOMPLETE_PORT" in ''|*[!0-9]*) fail 'invalid incomplete-CGI port' ;; esac
[ "$INCOMPLETE_PORT" -ge 1024 ] 2>/dev/null && [ "$INCOMPLETE_PORT" -le 65535 ] 2>/dev/null ||
	fail 'unsafe incomplete-CGI port'
[ "$INCOMPLETE_PORT" != "$PORT" ] && [ "$INCOMPLETE_PORT" != "$TLS_PORT" ] ||
	fail 'incomplete-CGI port must be distinct'

assert_security_headers() {
	response_headers="$1"
	response_label="$2"
	response_transport="$3"
	response_profile="$4"
	normalized_headers="$(printf '%s\n' "$response_headers" | tr -d '\r')"
	for expected_name in \
		'X-Content-Type-Options' \
		'X-Frame-Options' \
		'Referrer-Policy' \
		'Permissions-Policy' \
		'Cross-Origin-Resource-Policy' \
		'Content-Security-Policy'; do
		expected_count="$(printf '%s\n' "$normalized_headers" |
			grep -Eci "^${expected_name}:" || true)"
		[ "$expected_count" = 1 ] ||
			fail "$response_label has $expected_count copies of $expected_name"
	done
	case "$response_profile" in
		baseline)
			expected_policy_headers="$(printf '%s\n' \
				'X-Content-Type-Options: nosniff' \
				'X-Frame-Options: SAMEORIGIN' \
				'Referrer-Policy: no-referrer' \
				'Permissions-Policy: camera=(), microphone=(), geolocation=()' \
				'Cross-Origin-Resource-Policy: same-origin' \
				"Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self'; frame-ancestors 'self'; object-src 'none'; base-uri 'self'; form-action 'self'")"
			;;
		json_cgi)
			expected_policy_headers="$(printf '%s\n' \
				'X-Content-Type-Options: nosniff' \
				'X-Frame-Options: DENY' \
				'Referrer-Policy: no-referrer' \
				'Permissions-Policy: camera=(), microphone=(), geolocation=()' \
				'Cross-Origin-Resource-Policy: same-origin' \
				"Content-Security-Policy: default-src 'none'; frame-ancestors 'none'")"
			;;
		*) fail "invalid security-header profile: $response_profile" ;;
	esac
	printf '%s\n' "$expected_policy_headers" | while IFS= read -r expected_header; do
		printf '%s\n' "$normalized_headers" | grep -Fqxi "$expected_header" ||
			fail "$response_label lacks exact policy: $expected_header"
	done
	hsts_count="$(printf '%s\n' "$normalized_headers" |
		grep -Fci 'Strict-Transport-Security:' || true)"
	case "$response_transport" in
		http)
			[ "$hsts_count" = 0 ] || fail "$response_label exposes HSTS over cleartext HTTP"
			;;
		https)
			[ "$hsts_count" = 1 ] || fail "$response_label has $hsts_count HSTS headers"
			printf '%s\n' "$normalized_headers" |
				grep -Fqxi 'Strict-Transport-Security: max-age=31536000' ||
				fail "$response_label has the wrong HSTS policy"
			! printf '%s\n' "$normalized_headers" |
				grep -Eqi '^Strict-Transport-Security:.*(includeSubDomains|preload)' ||
				fail "$response_label extends HSTS beyond this host"
			;;
		*) fail "invalid response transport: $response_transport" ;;
	esac
}

probe_route() {
	probe_scheme="$1"
	probe_port="$2"
	probe_path="$3"
	probe_status="$4"
	probe_label="$5"
	probe_profile="$6"
	if [ "$probe_scheme" = https ]; then
		probe_headers="$(curl -ksS --max-time 5 --path-as-is -D - -o /dev/null \
			"https://127.0.0.1:$probe_port$probe_path")" || fail "$probe_label request failed"
	else
		probe_headers="$(curl -sS --max-time 5 --path-as-is -D - -o /dev/null \
			"http://127.0.0.1:$probe_port$probe_path")" || fail "$probe_label request failed"
	fi
	probe_actual_status="$(printf '%s\n' "$probe_headers" | tr -d '\r' | sed -n '1p')"
	[ "$probe_actual_status" = "$probe_status" ] ||
		fail "$probe_label returned $probe_actual_status instead of $probe_status"
	assert_security_headers "$probe_headers" "$probe_label" "$probe_scheme" "$probe_profile"
}

module_dir="${MODULE%/*}"
old_library_path="${LD_LIBRARY_PATH:-}"
if [ -n "$old_library_path" ]; then
	library_path="$module_dir:$old_library_path"
else
	library_path="$module_dir:/usr/lib"
fi

LD_LIBRARY_PATH="$library_path" "$SERVER" \
	-f -p "127.0.0.1:$PORT" -s "127.0.0.1:$TLS_PORT" \
	-C "$CERT" -K "$KEY" -H "$HEADERS" -h /www -x /cgi-bin \
	-o /cgi-bin/luci -O "$HANDLER" \
	-n 4 -N 12 -t 5 -T 5 -k 10 >"$LOG" 2>&1 &
server_pid=$!
incomplete_pid=''

cleanup() {
	if [ -n "$incomplete_pid" ]; then
		kill "$incomplete_pid" 2>/dev/null || true
		wait "$incomplete_pid" 2>/dev/null || true
	fi
	kill "$server_pid" 2>/dev/null || true
	wait "$server_pid" 2>/dev/null || true
	rm -f "$LOG" "$PIPELINE" "$PIPELINE_CHUNKED" "$PIPELINE_CONSUMED" \
		"$INCOMPLETE_LOG" "$INCOMPLETE_CGI"
	rmdir "$INCOMPLETE_ROOT/cgi-bin" "$INCOMPLETE_ROOT" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

sleep 1
kill -0 "$server_pid" 2>/dev/null || {
	cat "$LOG" >&2
	fail 'patched uhttpd did not start'
}

case "$INCOMPLETE_ROOT" in
	/tmp/cr6608-uhttpd-incomplete-root.[0-9]*) ;;
	*) fail 'unsafe incomplete-CGI fixture root' ;;
esac
[ ! -e "$INCOMPLETE_ROOT" ] || fail 'incomplete-CGI fixture root already exists'
mkdir -m 0700 "$INCOMPLETE_ROOT" "$INCOMPLETE_ROOT/cgi-bin"
printf '%s\n' \
	'#!/bin/sh' \
	"printf 'X-Frame-Options: DENY\\r\\n'" >"$INCOMPLETE_CGI"
chmod 0701 "$INCOMPLETE_CGI"
LD_LIBRARY_PATH="$library_path" "$SERVER" \
	-f -p "127.0.0.1:$INCOMPLETE_PORT" -H "$HEADERS" \
	-h "$INCOMPLETE_ROOT" -x /cgi-bin -n 2 -N 4 -t 5 -T 5 -k 5 \
	>"$INCOMPLETE_LOG" 2>&1 &
incomplete_pid=$!
sleep 1
kill -0 "$incomplete_pid" 2>/dev/null || {
	cat "$INCOMPLETE_LOG" >&2
	fail 'incomplete-CGI test uhttpd did not start'
}

entry_headers="$(curl -sS --max-time 5 -D - -o /dev/null \
	"http://127.0.0.1:$PORT/")" || fail 'Smart AP entry request failed'
entry_status="$(printf '%s\n' "$entry_headers" | tr -d '\r' | sed -n '1p')"
entry_cache="$(printf '%s\n' "$entry_headers" | tr -d '\r' | sed -n 's/^Cache-Control: //Ip' | head -n 1)"
entry_pragma="$(printf '%s\n' "$entry_headers" | tr -d '\r' | sed -n 's/^Pragma: //Ip' | head -n 1)"
printf 'smartap_entry_status=%s cache=%s pragma=%s\n' "$entry_status" "$entry_cache" "$entry_pragma"
[ "$entry_status" = 'HTTP/1.1 200 OK' ] || fail "wrong Smart AP entry status: $entry_status"
printf '%s\n' "$entry_cache" | grep -Fq 'no-store' || fail 'Smart AP entry permits document caching'
[ "$entry_pragma" = 'no-cache' ] || fail "wrong Smart AP entry pragma: $entry_pragma"
assert_security_headers "$entry_headers" http_static http baseline

# A conditional request for every representative static class must still be a
# fresh 200 with no-store. This proves the policy is not limited to index.html
# and prevents future scripts, icons or LuCI assets from becoming retained 304s.
for static_case in \
	'/dashboard.js:dashboard_script' \
	'/smartap-zero-retention.js:retention_migration' \
	'/luci-static/argon/icon/smart-ap.svg:smartap_icon' \
	'/luci-static/argon/css/cascade.css:luci_stylesheet'; do
	static_path="${static_case%%:*}"
	static_label="${static_case#*:}"
	static_headers="$(curl -sS --max-time 5 -H 'If-Modified-Since: Wed, 21 Oct 2037 07:28:00 GMT' \
		-D - -o /dev/null "http://127.0.0.1:$PORT$static_path")" ||
		fail "$static_label conditional request failed"
	static_status="$(printf '%s\n' "$static_headers" | tr -d '\r' | sed -n '1p')"
	[ "$static_status" = 'HTTP/1.1 200 OK' ] ||
		fail "$static_label returned $static_status instead of a fresh 200"
	printf '%s\n' "$static_headers" | tr -d '\r' |
		grep -Fqxi 'Cache-Control: no-store, no-cache, must-revalidate' ||
		fail "$static_label lacks the all-static no-store header"
	printf '%s\n' "$static_headers" | tr -d '\r' |
		grep -Fqxi 'Pragma: no-cache' || fail "$static_label lacks no-cache pragma"
	printf '%s\n' "$static_headers" | tr -d '\r' |
		grep -Fqxi 'Expires: 0' || fail "$static_label lacks zero expiry"
done

# The JSON request handler must cover every uhttpd dispatch outcome, not just
# files: a CGI-generated response and uhttpd's own 404 are checked on both
# transports. HSTS is emitted only when uhttpd reports HTTPS=on.
probe_route http "$PORT" /cgi-bin/dashlogin 'HTTP/1.1 405 Method Not Allowed' http_cgi json_cgi
probe_route http "$PORT" /cr6608-security-header-missing 'HTTP/1.1 404 Not Found' http_404 baseline
probe_route https "$TLS_PORT" / 'HTTP/1.1 200 OK' https_static baseline
probe_route https "$TLS_PORT" /cgi-bin/dashlogin 'HTTP/1.1 405 Method Not Allowed' https_cgi json_cgi
probe_route https "$TLS_PORT" /cr6608-security-header-missing 'HTTP/1.1 404 Not Found' https_404 baseline
probe_route http "$INCOMPLETE_PORT" /cgi-bin/incomplete 'HTTP/1.1 502 Bad Gateway' http_incomplete_cgi baseline

for target in \
	/cgi-bin/luci \
	/cgi-bin/luci/admin/network/wireless \
	/cgi-bin/%6cuci \
	/cgi-bin/luci%2fadmin/network/wireless \
	//cgi-bin/luci \
	/x/../cgi-bin/luci \
	/%63gi-bin/luci; do
	headers="$(curl -sS --max-time 5 --path-as-is -D - -o /dev/null \
		"http://127.0.0.1:$PORT$target")" || fail "request failed: $target"
	status="$(printf '%s\n' "$headers" | tr -d '\r' | sed -n '1p')"
	location="$(printf '%s\n' "$headers" | tr -d '\r' |
		sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p' | head -n 1)"
	luci_headers="$(printf '%s\n' "$headers" | tr -d '\r' | grep -ci '^x-luci-login-required:' || true)"
	printf 'route=%s status=%s location=%s luci_headers=%s\n' \
		"$target" "$status" "$location" "$luci_headers"
	[ "$status" = 'HTTP/1.1 302 Found' ] || fail "wrong status for $target: $status"
	[ "$location" = / ] || fail "wrong location for $target: $location"
	[ "$luci_headers" = 1 ] || fail "normalized route bypassed the LuCI handler: $target"
done

# The LuCI dispatcher emits x-luci-login-required before the overridden Argon
# sysauth template returns every unauthenticated request to Smart AP.  Requiring
# that marker proves every non-canonical variant reached the same ucode handler
# instead of falling through to the package CGI.  Session-authenticated requests
# are covered by the browser test.
post_headers="$(curl -sS --max-time 5 --path-as-is -X POST --data 'ABCD' \
	-D - -o /dev/null "http://127.0.0.1:$PORT/cgi-bin/luci")" || fail 'POST request failed'
post_status="$(printf '%s\n' "$post_headers" | tr -d '\r' | sed -n '1p')"
post_location="$(printf '%s\n' "$post_headers" | tr -d '\r' |
	sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p' | head -n 1)"
post_luci_headers="$(printf '%s\n' "$post_headers" | tr -d '\r' |
	grep -ci '^x-luci-login-required:' || true)"
printf 'post_status=%s location=%s luci_headers=%s\n' \
	"$post_status" "$post_location" "$post_luci_headers"
[ "$post_status" = 'HTTP/1.1 302 Found' ] || fail "wrong POST status: $post_status"
[ "$post_location" = / ] || fail "wrong POST location: $post_location"
[ "$post_luci_headers" = 1 ] || fail 'POST bypassed the LuCI handler'

# Put a complete second HTTP request inside a declared body on a static GET.
# Static-file dispatch does not consume request data.  Without the backported
# uh_request_done() guard, that body is parsed as another keepalive request.
smuggled_request='GET /cgi-bin/luci HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'
smuggled_length="$(printf '%b' "$smuggled_request" | wc -c | tr -d '[:space:]')"
{
	printf 'GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: %s\r\nConnection: keep-alive\r\n\r\n' "$smuggled_length"
	printf '%b' "$smuggled_request"
	sleep 2
} | nc 127.0.0.1 "$PORT" >"$PIPELINE"

pipeline_status="$(tr -d '\r' <"$PIPELINE" | sed -n '1p')"
pipeline_count="$(grep -c '^HTTP/1.1 ' "$PIPELINE" || true)"
pipeline_close_count="$(tr -d '\r' <"$PIPELINE" | grep -ci '^Connection: close$' || true)"
pipeline_keepalive_count="$(tr -d '\r' <"$PIPELINE" |
	grep -Eci '^(Connection: Keep-Alive|Keep-Alive:)' || true)"
printf 'unread_body_status=%s response_count=%s close=%s keepalive=%s\n' \
	"$pipeline_status" "$pipeline_count" "$pipeline_close_count" "$pipeline_keepalive_count"
[ "$pipeline_status" = 'HTTP/1.1 200 OK' ] || fail "wrong static status: $pipeline_status"
[ "$pipeline_count" = 1 ] || fail "unread body produced $pipeline_count responses"
[ "$pipeline_close_count" = 1 ] || fail "unread body emitted $pipeline_close_count Connection: close headers"
[ "$pipeline_keepalive_count" = 0 ] || fail "unread body advertised keepalive $pipeline_keepalive_count times"

# Repeat the same boundary test with chunked framing.  A valid chunk that
# contains a complete HTTP request must remain request data and the connection
# must close before any of it can be interpreted as a second request.
chunked_smuggled_request='GET /cgi-bin/luci HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'
chunked_smuggled_length="$(printf '%b' "$chunked_smuggled_request" | wc -c | tr -d '[:space:]')"
chunked_smuggled_hex="$(printf '%x' "$chunked_smuggled_length")"
{
	printf 'GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n'
	printf '%s\r\n' "$chunked_smuggled_hex"
	printf '%b' "$chunked_smuggled_request"
	printf '\r\n0\r\n\r\n'
	sleep 2
} | nc 127.0.0.1 "$PORT" >"$PIPELINE_CHUNKED"

chunked_status="$(tr -d '\r' <"$PIPELINE_CHUNKED" | sed -n '1p')"
chunked_count="$(grep -c '^HTTP/1.1 ' "$PIPELINE_CHUNKED" || true)"
chunked_close_count="$(tr -d '\r' <"$PIPELINE_CHUNKED" | grep -ci '^Connection: close$' || true)"
chunked_keepalive_count="$(tr -d '\r' <"$PIPELINE_CHUNKED" |
	grep -Eci '^(Connection: Keep-Alive|Keep-Alive:)' || true)"
printf 'unread_chunked_status=%s response_count=%s close=%s keepalive=%s\n' \
	"$chunked_status" "$chunked_count" "$chunked_close_count" "$chunked_keepalive_count"
[ "$chunked_status" = 'HTTP/1.1 200 OK' ] || fail "wrong chunked static status: $chunked_status"
[ "$chunked_count" = 1 ] || fail "unread chunked body produced $chunked_count responses"
[ "$chunked_close_count" = 1 ] || fail "unread chunked body emitted $chunked_close_count close headers"
[ "$chunked_keepalive_count" = 0 ] || fail "unread chunked body advertised keepalive $chunked_keepalive_count times"

# A CGI that consumes its complete form body must retain keepalive.  The
# following GET proves that the body guard does not close valid pipelines.
consumed_form='username=root&password=definitely-invalid'
consumed_length="$(printf '%s' "$consumed_form" | wc -c | tr -d '[:space:]')"
{
	printf 'POST /cgi-bin/dashlogin HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: %s\r\nConnection: keep-alive\r\n\r\n%s' "$consumed_length" "$consumed_form"
	printf 'GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'
	sleep 2
} | nc 127.0.0.1 "$PORT" >"$PIPELINE_CONSUMED"

consumed_count="$(grep -c '^HTTP/1.1 ' "$PIPELINE_CONSUMED" || true)"
consumed_second="$(tr -d '\r' <"$PIPELINE_CONSUMED" | grep '^HTTP/1.1 ' | sed -n '2p')"
printf 'consumed_body_response_count=%s second_status=%s\n' "$consumed_count" "$consumed_second"
[ "$consumed_count" = 2 ] || fail "consumed request pipeline produced $consumed_count responses"
[ "$consumed_second" = 'HTTP/1.1 200 OK' ] || fail "consumed request did not preserve keepalive"

printf 'uhttpd_smartap_runtime=pass\n'
