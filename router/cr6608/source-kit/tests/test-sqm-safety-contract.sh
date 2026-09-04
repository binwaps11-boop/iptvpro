#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASH="$ROOT/files/www/cgi-bin/dashctl"
SEED="$ROOT/cr6608.seed.config"
DSA_DEFAULTS="$ROOT/files/etc/uci-defaults/96-cr6608-sqm-dsa-defaults"

[ -s "$DSA_DEFAULTS" ]

for symbol in CONFIG_PACKAGE_sqm-scripts=y CONFIG_PACKAGE_kmod-sched-cake=y \
	CONFIG_PACKAGE_kmod-ifb=y CONFIG_PACKAGE_luci-app-sqm=y; do
	grep -Fqx "$symbol" "$SEED"
done

for marker in \
	'"$UCI_BIN" set sqm.smartap.interface='"'"'wan'"'"'' \
	'"$UCI_BIN" set sqm.smartap.download='"'"'0'"'"'' \
	'"$UCI_BIN" set sqm.smartap.upload='"'"'0'"'"'' \
	'set_default enabled 0' \
	'set_default qdisc cake' \
	'set_default script piece_of_cake.qos' \
	'[ "$migrated_placeholder" -eq 1 ]'; do
	grep -Fq "$marker" "$DSA_DEFAULTS"
done
grep -Fq '[ "$("$UCI_BIN" -q get "sqm.$legacy_section.enabled" 2>/dev/null || true)" != 1 ]' \
	"$DSA_DEFAULTS"

sqm_tmp="$(mktemp -d)"
trap 'rm -rf "$sqm_tmp"' EXIT HUP INT TERM
cat >"$sqm_tmp/uci" <<'EOF'
#!/bin/sh
quiet=0
if [ "${1-}" = -q ]; then
	quiet=1
	shift
fi
cmd="${1-}"
arg="${2-}"
case "${CR6608_SQM_TEST_MODE:-placeholder}:$cmd:$arg" in
	preserve:get:sqm.smartap) printf 'queue\n'; exit 0 ;;
	preserve:get:sqm.smartap.interface) printf 'pppoe-wan\n'; exit 0 ;;
	preserve:get:sqm.smartap.*) printf 'preserved\n'; exit 0 ;;
	placeholder:get:sqm.smartap) exit 1 ;;
	placeholder:show:sqm) printf 'sqm.eth1=queue\n'; exit 0 ;;
	placeholder:get:sqm.eth1.interface) printf 'eth1\n'; exit 0 ;;
	placeholder:get:sqm.eth1.enabled) printf '0\n'; exit 0 ;;
	placeholder:get:sqm.smartap.interface) printf 'eth1\n'; exit 0 ;;
	placeholder:get:sqm.smartap.*) exit 1 ;;
	*:rename:*|*:set:*|*:commit:*)
		printf '%s %s\n' "$cmd" "$arg" >>"$CR6608_SQM_TEST_LOG"
		exit 0
		;;
esac
[ "$quiet" -eq 1 ] && exit 1
exit 2
EOF
chmod 755 "$sqm_tmp/uci"
CR6608_SQM_TEST_LOG="$sqm_tmp/actions"
export CR6608_SQM_TEST_LOG

CR6608_SQM_UCI_BIN="$sqm_tmp/uci" CR6608_SQM_TEST_MODE=placeholder \
	sh "$DSA_DEFAULTS"
grep -Fqx 'rename sqm.eth1=smartap' "$CR6608_SQM_TEST_LOG"
grep -Fqx 'set sqm.smartap.interface=wan' "$CR6608_SQM_TEST_LOG"
grep -Fqx 'set sqm.smartap.download=0' "$CR6608_SQM_TEST_LOG"
grep -Fqx 'set sqm.smartap.upload=0' "$CR6608_SQM_TEST_LOG"
grep -Fqx 'set sqm.smartap.qdisc=cake' "$CR6608_SQM_TEST_LOG"
grep -Fqx 'commit sqm' "$CR6608_SQM_TEST_LOG"

: >"$CR6608_SQM_TEST_LOG"
CR6608_SQM_UCI_BIN="$sqm_tmp/uci" CR6608_SQM_TEST_MODE=preserve \
	sh "$DSA_DEFAULTS"
[ ! -s "$CR6608_SQM_TEST_LOG" ] || {
	printf 'SQM DSA defaults modified an existing non-placeholder profile\n' >&2
	exit 1
}

for marker in \
	'[ -d "/sys/class/net/$sqm_iface" ]' \
	'Line rate required' \
	'cake|fq_codel' \
	'piece_of_cake.qos|simple.qos' \
	"firewall.@defaults[0].flow_offloading='0'" \
	"firewall.@defaults[0].flow_offloading_hw='0'" \
	"sqm.smartap.eqdisc_opts='diffserv4 nat dual-srchost ack-filter ecn'" \
	"sqm.smartap.iqdisc_opts='diffserv4 nat dual-dsthost ingress wash ecn'" \
	"sqm.smartap.qdisc_really_really_advanced='1'" \
	'sqm_profile|SQM profile|' \
	'sqm_overhead|Packet overhead bytes|' \
	'action_arm_rollback "SQM"' \
	'action_commit firewall "SQM"' \
	'action_reload "SQM" "Firewall reload failed"' \
	'action_reload "SQM" "Restart failed"'; do
	grep -Fq "$marker" "$DASH"
done

grep -A8 -F 'for backup_file in \' "$DASH" | grep -Fq '/etc/config/sqm' || {
	printf 'SQM config is missing from guarded backups\n' >&2
	exit 1
}
grep -A30 -F 'restore_loaded() {' "$ROOT/files/usr/sbin/cr6608-safe-apply" | \
	grep -Fq '/etc/init.d/sqm restart' || {
	printf 'SQM runtime is not restored after rollback\n' >&2
	exit 1
}

preflight="$(grep -n 'Line rate required' "$DASH" | sed -n '1s/:.*//p')"
backup="$(grep -n 'action_backup sqm' "$DASH" | sed -n '1s/:.*//p')"
[ -n "$preflight" ] && [ -n "$backup" ] && [ "$preflight" -lt "$backup" ]

printf 'sqm_safety_contract=pass\n'
