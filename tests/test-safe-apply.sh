#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
HELPER="${SCRIPT_DIR}/../files/usr/sbin/cr6608-safe-apply"
DASHCTL="${SCRIPT_DIR}/../files/www/cgi-bin/dashctl"
DASHBOARD="${SCRIPT_DIR}/../files/www/dashboard.js"
CONFIRM_CGI="${SCRIPT_DIR}/../files/www/cgi-bin/cr6608-quick-confirm"

[ -f "$HELPER" ] || {
	echo "safe_apply_test=missing" >&2
	exit 1
}

block="$(sed -n '/^do_rollback()/,/^}/p' "$HELPER")"
printf '%s\n' "$block" | grep -Fq 'elif [ -n "$requested" ]; then' || {
	echo "safe_apply_test=watcher_guard_missing" >&2
	exit 1
}
printf '%s\n' "$block" | grep -Fq 'expired rollback watcher ignored after confirmation' || {
	echo "safe_apply_test=watcher_log_missing" >&2
	exit 1
}

guard_line="$(printf '%s\n' "$block" | grep -nF 'elif [ -n "$requested" ]; then' | cut -d: -f1)"
manual_line="$(printf '%s\n' "$block" | grep -nF 'elif ! load_manual_pointer; then' | cut -d: -f1)"
[ -n "$guard_line" ] && [ -n "$manual_line" ] && [ "$guard_line" -lt "$manual_line" ] || {
	echo "safe_apply_test=watcher_guard_order_invalid" >&2
	exit 1
}

confirm_block="$(sed -n '/^do_confirm()/,/^}/p' "$HELPER")"
printf '%s\n' "$confirm_block" | grep -Fq 'valid_token "$requested" || return 2' || {
	echo "safe_apply_test=confirmation_token_not_required" >&2
	exit 1
}
printf '%s\n' "$confirm_block" | grep -Fq '[ -f "$STATE" ] || return 1' || {
	echo "safe_apply_test=empty_confirmation_still_allowed" >&2
	exit 1
}
grep -Fq 'retain-ip) do_retain_ip' "$HELPER" || {
	echo "safe_apply_test=management_reachability_missing" >&2
	exit 1
}
grep -Fq 'old_security=' "$HELPER" || {
	echo "safe_apply_test=security_service_state_missing" >&2
	exit 1
}
grep -Fq '"$old_security" = "1"' "$HELPER" || {
	echo "safe_apply_test=security_service_restore_missing" >&2
	exit 1
}
grep -Fq 'cr6608-security-apply clear-runtime' "$HELPER" || {
	echo "safe_apply_test=disabled_security_runtime_not_cleared" >&2
	exit 1
}
grep -Fq 'rollback_token="$(/usr/sbin/cr6608-safe-apply arm' "$DASHCTL" || {
	echo "safe_apply_test=dashboard_discards_token" >&2
	exit 1
}
grep -Fq 'confirm "$requested_rollback_token"' "$DASHCTL" || {
	echo "safe_apply_test=dashboard_confirmation_not_bound" >&2
	exit 1
}
if grep -Fq 'needsReachabilityConfirm' "$DASHBOARD"; then
	echo "safe_apply_test=dashboard_auto_confirms" >&2
	exit 1
fi
grep -Fq "case \"\$token\" in ''|*[!0-9a-f]*) reply" "$CONFIRM_CGI" || {
	echo "safe_apply_test=confirm_cgi_allows_empty_token" >&2
	exit 1
}

echo "safe_apply_tests=pass"
