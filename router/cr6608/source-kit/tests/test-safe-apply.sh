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
printf '%s\n' "$block" | grep -Fq 'pending rollback state is invalid; refusing to treat it as confirmation' || {
	echo "safe_apply_test=corrupt_state_treated_as_confirmation" >&2
	exit 1
}
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
restore_line="$(printf '%s\n' "$block" | grep -nF 'if restore_loaded; then' | cut -d: -f1)"
retained_cleanup_line="$(printf '%s\n' "$block" | grep -nF 'cleanup_retained_ip "${token:-}"' | cut -d: -f1)"
[ -n "$restore_line" ] && [ -n "$retained_cleanup_line" ] &&
	[ "$restore_line" -lt "$retained_cleanup_line" ] || {
	echo "safe_apply_test=retained_ip_cleaned_before_restore" >&2
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
restore_block="$(sed -n '/^restore_loaded()/,/^}/p' "$HELPER")"
printf '%s\n' "$restore_block" | grep -Fq '/usr/sbin/smartap-qos-apply' || {
	echo "safe_apply_test=bridge_policy_not_restored" >&2
	exit 1
}
if printf '%s\n' "$restore_block" | grep -F '/usr/sbin/smartap-qos-apply' | grep -Fq '|| true'; then
	echo "safe_apply_test=bridge_policy_restore_failure_ignored" >&2
	exit 1
fi
printf '%s\n' "$restore_block" | grep -Fq '/etc/init.d/cr6608-neighbor restart' || {
	echo "safe_apply_test=neighbor_identity_not_restarted" >&2
	exit 1
}
if printf '%s\n' "$restore_block" | grep -F '/etc/init.d/cr6608-neighbor restart' | grep -Fq '|| true'; then
	echo "safe_apply_test=neighbor_identity_restart_failure_ignored" >&2
	exit 1
fi
grep -Fq 'CR6608_SAFE_LOCK:-/var/run/cr6608-apply.lock' "$HELPER" || {
	echo "safe_apply_test=global_apply_lock_not_shared" >&2
	exit 1
}
for marker in \
	'POINTER="${CR6608_SAFE_POINTER:-$SAFE_RUNTIME_DIR/backup}"' \
	'META="${CR6608_SAFE_META:-$SAFE_RUNTIME_DIR/meta}"' \
	'ARMED="${CR6608_SAFE_ARMED:-$SAFE_RUNTIME_DIR/armed}"' \
	'READY="${CR6608_SAFE_READY:-$SAFE_RUNTIME_DIR/ready}"' \
	'RETAINED_IP="${CR6608_SAFE_RETAINED_IP:-$SAFE_RUNTIME_DIR/retained-ip}"'; do
	grep -Fq "$marker" "$HELPER" || {
		echo "safe_apply_test=private_marker_layout_missing" >&2
		exit 1
	}
done
grep -Fq 'cr6608_private_runtime_dir safe-apply' "$HELPER" || {
	echo "safe_apply_test=private_runtime_helper_missing" >&2
	exit 1
}
if grep -Fq '/tmp/' "$HELPER" || grep -Fq '.tmp.$$' "$HELPER"; then
	echo "safe_apply_test=predictable_root_temp_write" >&2
	exit 1
fi
grep -Fq '/usr/sbin/cr6608-safe-wifi-reload --verify-only 30 all' "$HELPER" || {
	echo "safe_apply_test=rollback_runtime_not_verified" >&2
	exit 1
}
grep -Fq 'rollback_timeout_for_wireless' "$DASHCTL" || {
	echo "safe_apply_test=dfs_rollback_timeout_missing" >&2
	exit 1
}
grep -Fq '_rt_timeout=720' "$DASHCTL" || {
	echo "safe_apply_test=dfs_rollback_timeout_too_short" >&2
	exit 1
}
backup_block="$(sed -n '/^backup_cfg()/,/^}/p' "$DASHCTL")"
printf '%s\n' "$backup_block" | grep -Fq 'mktemp "/root/dashboard-backups/.smartap-' || {
	echo "safe_apply_test=dashboard_backup_not_unique" >&2
	exit 1
}
printf '%s\n' "$backup_block" | grep -Fq '/etc/smartap-pending-rollback' || {
	echo "safe_apply_test=dashboard_backup_created_while_pending" >&2
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
grep -Fq 'ready) do_ready "${2:-}"' "$HELPER" || {
	echo "safe_apply_test=success_marker_command_missing" >&2
	exit 1
}
grep -Fq 'safe_apply_ready_mark "$rollback_token"' "$DASHCTL" || {
	echo "safe_apply_test=dashboard_success_marker_missing" >&2
	exit 1
}
grep -Fq '"$SAFE_APPLY" ready "$rollback_token"' "${SCRIPT_DIR}/../files/www/cgi-bin/cr6608-quick-apply" || {
	echo "safe_apply_test=quick_apply_success_marker_missing" >&2
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
