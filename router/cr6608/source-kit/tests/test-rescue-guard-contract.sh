#!/bin/sh
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR%/tests}"
GUARD_SOURCE="$ROOT_DIR/files/usr/sbin/cr6608-rescue-guard"
INIT_SOURCE="$ROOT_DIR/files/etc/init.d/cr6608-rescue-guard"
IFACE_HOTPLUG="$ROOT_DIR/files/etc/hotplug.d/iface/99-cr6608-rescue-guard"
NET_HOTPLUG="$ROOT_DIR/files/etc/hotplug.d/net/99-cr6608-rescue-guard"
NETWORK_CONFIG="$ROOT_DIR/files/etc/config/network"
FIREWALL_CONFIG="$ROOT_DIR/files/etc/config/firewall"
UHTTPD_CONFIG="$ROOT_DIR/files/etc/config/uhttpd"
MIGRATION="$ROOT_DIR/files/etc/uci-defaults/96-cr6608-wlanrescue-isolation"
FIREWALL_INCLUDE="$ROOT_DIR/files/usr/libexec/cr6608-rescue-firewall-include"
FIREWALL_INIT_SOURCE="$ROOT_DIR/files/etc/init.d/firewall"

fail() {
	printf 'rescue guard contract failed: %s\n' "$*" >&2
	exit 1
}

for required in "$GUARD_SOURCE" "$INIT_SOURCE" "$IFACE_HOTPLUG" \
	"$NET_HOTPLUG" "$NETWORK_CONFIG" "$FIREWALL_CONFIG" \
	"$UHTTPD_CONFIG" "$MIGRATION" "$FIREWALL_INCLUDE" \
	"$FIREWALL_INIT_SOURCE"; do
	[ -s "$required" ] || fail "missing $required"
done

tmp="$(mktemp -d)" || fail 'mktemp'
cleanup() {
	trap - EXIT HUP INT TERM
	rm -rf -- "$tmp" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM
mock_bin="$tmp/bin"
mock_state="$tmp/state"
mock_sys="$tmp/sys-class-net"
mkdir -p "$mock_bin" "$mock_state" "$mock_sys/phy0-ap0" \
	"$mock_sys/br-lan" "$mock_sys/br-lan.100" || \
	fail 'mock directories'
export MOCK_STATE="$mock_state"

guard="$tmp/cr6608-rescue-guard"
sed \
	-e "s@NFT_BIN='/usr/sbin/nft'@NFT_BIN='$mock_bin/nft'@" \
	-e "s@UCI_BIN='/sbin/uci'@UCI_BIN='$mock_bin/uci'@" \
	-e "s@IW_BIN='/usr/sbin/iw'@IW_BIN='$mock_bin/iw'@" \
	-e "s@IP_BIN='/sbin/ip'@IP_BIN='$mock_bin/ip'@" \
	-e "s@UBUS_BIN='/bin/ubus'@UBUS_BIN='$mock_bin/ubus'@" \
	-e "s@JSONFILTER_BIN='/usr/bin/jsonfilter'@JSONFILTER_BIN='$mock_bin/jsonfilter'@" \
	-e "s@FW4_BIN='/sbin/fw4'@FW4_BIN='$mock_bin/firewall'@" \
	-e "s@RESCUE_INIT='/etc/init.d/cr6608-rescue-guard'@RESCUE_INIT='$mock_bin/rescue-init'@" \
	-e "s@GUARD_BIN='/usr/sbin/cr6608-rescue-guard'@GUARD_BIN='$mock_bin/self-guard'@" \
	-e "s@FLOCK_BIN='flock'@FLOCK_BIN='$mock_bin/flock'@" \
	-e "s@LOGGER_BIN='logger'@LOGGER_BIN='$mock_bin/logger'@" \
	-e "s@MKTEMP_BIN='mktemp'@MKTEMP_BIN='$mock_bin/mktemp'@" \
	-e "s@SETSID_BIN='/usr/bin/setsid'@SETSID_BIN='$mock_bin/setsid'@" \
	-e "s@KILL_BIN='/bin/kill'@KILL_BIN='$mock_bin/kill'@" \
	-e "s@SYS_CLASS_NET='/sys/class/net'@SYS_CLASS_NET='$mock_sys'@" \
	-e "s@STATE_DIR='/var/run/cr6608-rescue-guard'@STATE_DIR='$tmp/runtime'@" \
	-e "s@LOCK_FILE='/var/lock/cr6608-rescue-guard.lock'@LOCK_FILE='$tmp/lock/rescue.lock'@" \
	-e "s@LOCK_WAIT_ATTEMPTS='5'@LOCK_WAIT_ATTEMPTS='2'@" \
	-e "s@LOCK_RETRY_SECONDS='1'@LOCK_RETRY_SECONDS='0'@" \
	-e "s@COMMAND_TIMEOUT='8'@COMMAND_TIMEOUT='1'@" \
	-e "s@FIREWALL_TIMEOUT='45'@FIREWALL_TIMEOUT='2'@" \
	-e "s@CLOSE_TIMEOUT='3'@CLOSE_TIMEOUT='1'@" \
	-e "s@KILL_TIMEOUT='2'@KILL_TIMEOUT='1'@" \
	-e "s@MONITOR_INTERVAL='10'@MONITOR_INTERVAL='1'@" \
	-e "s@MONITOR_RECOVERY_DELAY='2'@MONITOR_RECOVERY_DELAY='0'@" \
	-e "s@MONITOR_FAILURE_BACKOFF='30'@MONITOR_FAILURE_BACKOFF='1'@" \
	"$GUARD_SOURCE" >"$guard" || fail 'rewrite guard copy'
chmod 0755 "$guard" || fail 'guard mode'

firewall_init="$tmp/firewall-init-stop"
{
	printf '#!/bin/sh\n'
	sed -n '/^stop_service() {$/,/^}$/p' "$FIREWALL_INIT_SOURCE" |
		sed "s@/usr/sbin/cr6608-rescue-guard@$guard@g"
	printf 'stop_service\n'
} >"$firewall_init" || fail 'mock direct firewall init fixture'
chmod 0755 "$firewall_init" || fail 'mock direct firewall init fixture mode'

rescue_stop_order="$tmp/rescue-stop-order"
{
	printf '#!/bin/sh\n'
	printf "GUARD='%s'\n" "$guard"
	sed -n '/^stop_service() {$/,/^}$/p' "$INIT_SOURCE"
	sed -n '/^service_stopped() {$/,/^}$/p' "$INIT_SOURCE"
	cat <<EOF
stop_service
# Official OpenWrt rc.common calls procd_kill only after stop_service. Model a
# sleeping monitor wake in that exact interval.
"$guard" apply >"$tmp/stop-order-monitor-wake.out" 2>"$tmp/stop-order-monitor-wake.err"
service_stopped
EOF
	} >"$rescue_stop_order" || fail 'mock rc.common stop-order fixture'
chmod 0755 "$rescue_stop_order" || fail 'mock rc.common stop-order fixture mode'

startup_guard="$tmp/startup-guard"
cat >"$startup_guard" <<EOF
#!/bin/sh
printf '%s\n' "\${1:-}" >>"$mock_state/startup-guard-calls"
if [ "\${1:-}" = start ]; then
	[ -e "$mock_state/procd-registered" ] && \
		[ -e "$mock_state/monitor-observed" ] || \
		: >"$mock_state/start-before-registration"
	if [ -n "\${MOCK_STARTUP_FAIL_COUNT:-}" ]; then
		_startup_attempt=0
		[ ! -s "$mock_state/startup-attempt-count" ] || \
			_startup_attempt="\$(cat "$mock_state/startup-attempt-count")"
		_startup_attempt=\$((_startup_attempt + 1))
		printf '%s\n' "\$_startup_attempt" >"$mock_state/startup-attempt-count"
		[ "\$_startup_attempt" -gt "\$MOCK_STARTUP_FAIL_COUNT" ] || exit 97
	fi
	[ ! -e "$mock_state/fail-startup-activation" ] || exit 97
	"$guard" "\$@"
	_startup_guard_rc=\$?
	[ "\$_startup_guard_rc" -ne 0 ] || : >"$mock_state/activation-complete"
	exit "\$_startup_guard_rc"
fi
exec "$guard" "\$@"
EOF
chmod 0755 "$startup_guard" || fail 'mock startup guard mode'

startup_probe="$tmp/startup-probe"
{
	printf '#!/bin/sh\n'
	printf "GUARD='%s'\n" "$startup_guard"
	printf 'RESCUE_START_PREPARED=0\n'
	printf "RESCUE_INSTANCE=''\n"
	printf 'RESCUE_REGISTRATION_ATTEMPTS=30\n'
	printf 'RESCUE_ACTIVATION_ATTEMPTS=30\n'
	cat <<'EOF'
procd_open_instance() {
	printf 'open %s\n' "${1:-}" >>"$MOCK_STATE/procd-calls"
	[ "${MOCK_PROCD_CONFIG_FAIL:-}" != open ]
	printf '%s\n' "${1:-}" >"$MOCK_STATE/procd-instance-prepared"
}
procd_set_param() {
	printf 'set %s\n' "$*" >>"$MOCK_STATE/procd-calls"
	[ "${MOCK_PROCD_CONFIG_FAIL:-}" != set ]
}
procd_close_instance() {
	printf 'close\n' >>"$MOCK_STATE/procd-calls"
	[ "${MOCK_PROCD_CONFIG_FAIL:-}" != close ] || return 1
}
rc_common_publish() {
	[ -s "$MOCK_STATE/procd-instance-prepared" ] || return 1
	cp "$MOCK_STATE/procd-instance-prepared" "$MOCK_STATE/procd-instance-published"
	: >"$MOCK_STATE/procd-registered"
}
service_running() {
	printf 'running %s\n' "${1:-}" >>"$MOCK_STATE/procd-calls"
	if [ "${MOCK_STALE_INSTANCE_RUNNING:-0}" = 1 ] &&
	   { [ -z "${1:-}" ] || [ "${1:-}" = stale-monitor ]; }; then
		return 0
	fi
	[ "${MOCK_PROCD_RUNNING:-0}" = 1 ] || return 1
	[ -e "$MOCK_STATE/procd-registered" ] || return 1
	[ "${1:-}" = "$(cat "$MOCK_STATE/procd-instance-published" 2>/dev/null)" ] || return 1
	if [ -n "${MOCK_PROCD_READY_AFTER:-}" ]; then
		_ready_probe=0
		[ ! -s "$MOCK_STATE/procd-ready-probes" ] || \
			_ready_probe="$(cat "$MOCK_STATE/procd-ready-probes")"
		_ready_probe=$((_ready_probe + 1))
		printf '%s\n' "$_ready_probe" >"$MOCK_STATE/procd-ready-probes"
		[ "$_ready_probe" -gt "$MOCK_PROCD_READY_AFTER" ] || return 1
	fi
	if [ "${MOCK_PROCD_VANISH_AFTER_START:-0}" = 1 ] &&
	   [ -e "$MOCK_STATE/activation-complete" ]; then
		return 1
	fi
	: >"$MOCK_STATE/monitor-observed"
}
sleep() { :; }
EOF
	sed -n '/^rescue_process_start_ticks() {$/,/^}$/p' "$INIT_SOURCE"
	sed -n '/^rescue_instance_valid() {$/,/^}$/p' "$INIT_SOURCE"
	sed -n '/^rescue_instance_running() {$/,/^}$/p' "$INIT_SOURCE"
	sed -n '/^start_service() {$/,/^}$/p' "$INIT_SOURCE"
	sed -n '/^service_started() {$/,/^}$/p' "$INIT_SOURCE"
	cat <<'EOF'
if [ "${MOCK_START_TICKS_FAIL:-0}" = 1 ]; then
	rescue_process_start_ticks() { return 1; }
fi
case "${STARTUP_PROBE_MODE:-full}" in
	start-only) start_service ;;
	started-only) service_started ;;
	full) start_service && rc_common_publish && service_started ;;
	*) exit 2 ;;
esac
EOF
} >"$startup_probe" || fail 'mock procd startup probe fixture'
chmod 0755 "$startup_probe" || fail 'mock procd startup probe mode'

cat >"$mock_bin/uci" <<'EOF'
#!/bin/sh
printf 'uci %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-uci"
if [ -e "$MOCK_STATE/uci-delay" ] && [ ! -e "$MOCK_STATE/uci-delay-started" ]; then
	: >"$MOCK_STATE/uci-delay-started"
	sleep 2
fi
[ "${1:-}" = -q ] && shift
command_name="${1:-}"; shift || true
case "$command_name" in
	show)
		case "${1:-}" in
		network.wlanrescue) cat <<'SHOW'
network.wlanrescue=interface
network.wlanrescue.cr6608_owner='wlanrescue-v1'
network.wlanrescue.proto='none'
network.wlanrescue.ipv6='0'
network.wlanrescue.delegate='0'
network.wlanrescue.auto='0'
SHOW
			;;
		firewall) cat <<'SHOW'
firewall.lan=zone
firewall.lan.name='lan'
firewall.cr6608_rescue_zone=zone
firewall.cr6608_rescue_zone.name='cr6608_rescue'
SHOW
			;;
		wireless) cat <<'SHOW'
wireless.radio0=wifi-device
wireless.radio1=wifi-device
wireless.wifinet0=wifi-iface
wireless.wifinet1=wifi-iface
SHOW
			[ ! -e "$MOCK_STATE/alternative-ap" ] || \
				printf 'wireless.wifinet2=wifi-iface\n'
			[ ! -e "$MOCK_STATE/ambiguous-ap" ] || \
				printf 'wireless.wifinet3=wifi-iface\n'
			[ ! -e "$MOCK_STATE/receiver-mesh-smartap" ] || \
				printf 'wireless.smartap_mesh=wifi-iface\n'
			[ ! -e "$MOCK_STATE/receiver-mesh-cr6608" ] || \
				printf 'wireless.cr6608_mesh=wifi-iface\n'
			[ ! -e "$MOCK_STATE/receiver-wds-smartap" ] || \
				printf 'wireless.smartap_wds=wifi-iface\n'
			[ ! -e "$MOCK_STATE/receiver-wds-cr6608" ] || \
				printf 'wireless.cr6608_wds=wifi-iface\n'
			;;
		*) exit 1 ;;
		esac
		;;
	get)
		key="${1:-}"
		case "$key" in
			network.wlanrescue) value=interface ;;
			network.wlanrescue.cr6608_owner) value=wlanrescue-v1 ;;
			network.wlanrescue.proto) value=none ;;
			network.wlanrescue.ipv6|network.wlanrescue.delegate|network.wlanrescue.auto) value=0 ;;
			wireless.radio0|wireless.radio1) value=wifi-device ;;
			wireless.radio0.disabled) value=0 ;;
			wireless.radio1.disabled)
				if [ -e "$MOCK_STATE/radio1-disabled" ]; then value=1; else value=0; fi ;;
			wireless.wifinet0|wireless.wifinet1|wireless.wifinet2|wireless.wifinet3|wireless.smartap_mesh|wireless.cr6608_mesh|wireless.smartap_wds|wireless.cr6608_wds) value=wifi-iface ;;
			wireless.wifinet0.device) value=radio0 ;;
			wireless.wifinet1.device) value=radio1 ;;
			wireless.wifinet2.device|wireless.wifinet3.device) value=radio0 ;;
			wireless.smartap_mesh.device|wireless.cr6608_mesh.device|wireless.smartap_wds.device|wireless.cr6608_wds.device) value=radio1 ;;
			wireless.wifinet0.mode|wireless.wifinet2.mode|wireless.wifinet3.mode) value=ap ;;
			wireless.wifinet1.mode)
				if [ -e "$MOCK_STATE/primary1-sta" ]; then value=sta
				elif [ -e "$MOCK_STATE/primary1-mesh" ]; then value=mesh
				else value=ap
				fi ;;
			wireless.smartap_mesh.mode|wireless.cr6608_mesh.mode) value=mesh ;;
			wireless.smartap_wds.mode|wireless.cr6608_wds.mode) value=sta ;;
			wireless.smartap_wds.wds|wireless.cr6608_wds.wds) value=1 ;;
			wireless.wifinet0.disabled)
				if [ -e "$MOCK_STATE/primary0-disabled" ]; then value=1; else value=0; fi ;;
			wireless.wifinet1.disabled)
				if [ -e "$MOCK_STATE/primary1-disabled" ] ||
				   [ -e "$MOCK_STATE/receiver-mesh-smartap" ] ||
				   [ -e "$MOCK_STATE/receiver-mesh-cr6608" ] ||
				   [ -e "$MOCK_STATE/receiver-wds-smartap" ] ||
				   [ -e "$MOCK_STATE/receiver-wds-cr6608" ]; then value=1; else value=0; fi ;;
			wireless.wifinet2.disabled|wireless.wifinet3.disabled|wireless.smartap_mesh.disabled|wireless.cr6608_mesh.disabled|wireless.smartap_wds.disabled|wireless.cr6608_wds.disabled) value=0 ;;
			wireless.wifinet0.network)
				if [ -e "$MOCK_STATE/custom-primary0" ]; then value=iot0
				elif [ -e "$MOCK_STATE/vlan-primary" ]; then value=cr6608_vlan
				else value=lan
				fi ;;
			wireless.wifinet1.network)
				if [ -e "$MOCK_STATE/custom-primary1" ]; then
					value=iot1
				elif [ -e "$MOCK_STATE/vlan-primary" ] || [ -e "$MOCK_STATE/path-conflict" ]; then
					value=cr6608_vlan
				else
					value=lan
				fi ;;
			wireless.wifinet2.network|wireless.wifinet3.network) value=cr6608_vlan ;;
			wireless.smartap_mesh.network|wireless.cr6608_mesh.network|wireless.smartap_wds.network|wireless.cr6608_wds.network)
				if [ -e "$MOCK_STATE/receiver-vlan" ]; then value=cr6608_vlan; else value=lan; fi ;;
			network.lan|network.cr6608_vlan|network.iot0|network.iot1) value=interface ;;
			network.cr6608_vlan.device) value=br-lan.100 ;;
			network.iot0.device) value=br-iot0 ;;
			network.iot1.device) value=eth0 ;;
			network.lan.device)
				if [ -e "$MOCK_STATE/bad-network" ]; then value=eth0; else value=br-lan; fi ;;
			firewall.lan.network) value='lan cr6608_vlan' ;;
			firewall.cr6608_rescue_zone) value=zone ;;
			firewall.cr6608_rescue_zone.name) value=cr6608_rescue ;;
			firewall.cr6608_rescue_zone.network) value=wlanrescue ;;
			firewall.cr6608_rescue_zone.input|firewall.cr6608_rescue_zone.forward) value=REJECT ;;
			firewall.cr6608_rescue_zone.output) value=ACCEPT ;;
			firewall.cr6608_rescue_zone.cr6608_owner|firewall.cr6608_rescue_web.cr6608_owner|firewall.cr6608_rescue_ping.cr6608_owner|firewall.cr6608_rescue_reject.cr6608_owner|firewall.cr6608_rescue_guard_reload.cr6608_owner) value=wlanrescue-v1 ;;
			firewall.cr6608_rescue_web|firewall.cr6608_rescue_ping|firewall.cr6608_rescue_reject) value=rule ;;
			firewall.cr6608_rescue_web.src|firewall.cr6608_rescue_ping.src|firewall.cr6608_rescue_reject.src) value=lan ;;
			firewall.cr6608_rescue_web.dest_ip|firewall.cr6608_rescue_ping.dest_ip|firewall.cr6608_rescue_reject.dest_ip) value=221.221.221.221 ;;
			firewall.cr6608_rescue_web.proto) value=tcp ;;
			firewall.cr6608_rescue_web.dest_port) value='80 443' ;;
			firewall.cr6608_rescue_web.family|firewall.cr6608_rescue_ping.family|firewall.cr6608_rescue_reject.family) value=ipv4 ;;
			firewall.cr6608_rescue_web.mark|firewall.cr6608_rescue_ping.mark) value=0x6608cafe/0xffffffff ;;
			firewall.cr6608_rescue_web.target|firewall.cr6608_rescue_ping.target) value=ACCEPT ;;
			firewall.cr6608_rescue_ping.proto) value=icmp ;;
			firewall.cr6608_rescue_ping.icmp_type) value=echo-request ;;
			firewall.cr6608_rescue_reject.target) value=REJECT ;;
			firewall.cr6608_rescue_guard_reload) value=include ;;
			firewall.cr6608_rescue_guard_reload.type) value=script ;;
			firewall.cr6608_rescue_guard_reload.path) value=/usr/libexec/cr6608-rescue-firewall-include ;;
			firewall.cr6608_rescue_guard_reload.fw4_compatible) value=1 ;;
			uhttpd.main.rfc1918_filter) value=1 ;;
			*) exit 1 ;;
		esac
		printf '%s\n' "$value"
		;;
	*) exit 1 ;;
esac
EOF

cat >"$mock_bin/iw" <<'EOF'
#!/bin/sh
printf 'iw %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-iw"
[ "${1:-}" = dev ] || exit 1
[ ! -e "$MOCK_STATE/iw-timeout" ] || exit 124
if [ -e "$MOCK_STATE/iw-stop-hang" ]; then
	printf '%s\n' "$$" >"$MOCK_STATE/iw-stop-hang-pid"
	kill -STOP "$$"
	exec sleep 30
fi
if [ -e "$MOCK_STATE/iw-hang" ]; then
	printf '%s\n' "$$" >"$MOCK_STATE/iw-hang-pid"
	trap '' TERM
	exec sleep 30
fi
if [ -e "$MOCK_STATE/no-ap" ]; then
	printf 'phy#0\n\tInterface phy0-sta0\n\t\ttype managed\n'
else
	printf 'phy#0\n\tInterface phy0-ap0\n\t\ttype AP\n'
fi
EOF

cat >"$mock_bin/nft" <<'EOF'
#!/bin/sh
printf 'nft %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-nft"
case "${1:-}" in
	delete)
		case " $* " in *' cr6608_rescue '*) rm -f "$MOCK_STATE/applied" ;; esac
		exit 0
		;;
	-c)
		[ "${2:-}" = -f ] || exit 1
		if [ "${3:-}" = - ]; then
			cat >"$MOCK_STATE/nft-stdin" || exit 1
			nft_source="$MOCK_STATE/nft-stdin"
		else
			nft_source="${3:-}"
		fi
		[ -s "$nft_source" ] || exit 1
		if grep -Fq CR6608_RESCUE_DENY_ONLY "$nft_source"; then
			[ ! -e "$MOCK_STATE/fail-deny-precheck" ] || exit 1
		else
			[ ! -e "$MOCK_STATE/fail-precheck" ] || exit 1
		fi
		cp "$nft_source" "$MOCK_STATE/prechecked"
		exit 0
		;;
	-f)
		if [ "${2:-}" = - ]; then
			cat >"$MOCK_STATE/nft-stdin" || exit 1
			nft_source="$MOCK_STATE/nft-stdin"
		else
			nft_source="${2:-}"
		fi
		[ -s "$nft_source" ] || exit 1
		if grep -Fq CR6608_RESCUE_DENY_ONLY "$nft_source"; then
			[ ! -e "$MOCK_STATE/fail-deny-apply" ] || exit 1
		else
			[ ! -e "$MOCK_STATE/fail-apply" ] || exit 1
		fi
		cp "$nft_source" "$MOCK_STATE/applied"
		if grep -Fq CR6608_RESCUE_STATIC_INET_MARK_DENY "$nft_source"; then
			cp "$nft_source" "$MOCK_STATE/static-rules"
		fi
		exit 0
		;;
	list)
		case " $* " in
			*' list tables '*)
				[ ! -e "$MOCK_STATE/fail-list-tables" ] || exit 1
				[ ! -e "$MOCK_STATE/fw4-table" ] || printf 'table inet fw4\n'
				[ ! -s "$MOCK_STATE/applied" ] || printf 'table bridge cr6608_rescue\n'
				[ ! -s "$MOCK_STATE/static-rules" ] || printf 'table inet cr6608_rescue_static\n'
				;;
			*' list table inet fw4 '*)
				[ -e "$MOCK_STATE/fw4-table" ] || exit 1
				printf 'table inet fw4\n'
				;;
			*' cr6608_rescue_static '*)
				[ -s "$MOCK_STATE/static-rules" ] || exit 1
				cat "$MOCK_STATE/static-rules"
				;;
			*)
				[ -s "$MOCK_STATE/applied" ] || exit 1
				cat "$MOCK_STATE/applied"
				;;
		esac
		exit 0
		;;
esac
exit 1
EOF

cat >"$mock_bin/ip" <<'EOF'
#!/bin/sh
printf 'ip %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-ip"
case " $* " in
	' -4 -o addr show ')
		if [ -s "$MOCK_STATE/address" ]; then
			address_dev="$(cat "$MOCK_STATE/address")"
			printf '7: %s    inet 221.221.221.221/32 scope global %s\n' \
				"$address_dev" "$address_dev"
		fi
		[ -e "$MOCK_STATE/rescue-on-lan" ] && \
			printf '8: br-lan    inet 221.221.221.221/32 scope global br-lan\n'
		exit 0 ;;
	' -4 addr del 221.221.221.221/32 dev br-lan ' | \
	' -4 addr del 221.221.221.221/32 dev br-lan.100 ')
		[ ! -e "$MOCK_STATE/fail-addr-delete" ] || exit 1
		rm -f "$MOCK_STATE/address" "$MOCK_STATE/rescue-on-lan"; exit 0 ;;
	' -4 addr add 221.221.221.221/32 dev br-lan ')
		[ ! -s "$MOCK_STATE/address" ] || exit 2
		printf 'br-lan\n' >"$MOCK_STATE/address"; exit 0 ;;
	' -4 addr add 221.221.221.221/32 dev br-lan.100 ')
		[ ! -s "$MOCK_STATE/address" ] || exit 2
		printf 'br-lan.100\n' >"$MOCK_STATE/address"; exit 0 ;;
	' -4 -o route show exact 221.221.221.221/32 table main ')
		[ -s "$MOCK_STATE/route" ] && cat "$MOCK_STATE/route"
		[ -s "$MOCK_STATE/foreign-route" ] && cat "$MOCK_STATE/foreign-route"
		exit 0 ;;
	' -4 -o route show exact 221.221.221.221/32 table main proto 221 ')
		# Real iproute2 omits the selected protocol token from filtered output.
		[ -s "$MOCK_STATE/route" ] && sed 's/ proto 221//' "$MOCK_STATE/route"
		exit 0 ;;
	' -4 route del 221.221.221.221/32 dev br-lan src 221.221.221.221 scope link proto 221 table main ' | \
	' -4 route del 221.221.221.221/32 dev br-lan.100 src 221.221.221.221 scope link proto 221 table main ')
		rm -f "$MOCK_STATE/route"; exit 0 ;;
	' -4 route add 221.221.221.221/32 dev br-lan src 221.221.221.221 scope link proto 221 ')
		[ ! -s "$MOCK_STATE/foreign-route" ] || exit 2
		printf '221.221.221.221 dev br-lan proto 221 scope link src 221.221.221.221\n' >"$MOCK_STATE/route"; exit 0 ;;
	' -4 route add 221.221.221.221/32 dev br-lan.100 src 221.221.221.221 scope link proto 221 ')
		[ ! -s "$MOCK_STATE/foreign-route" ] || exit 2
		printf '221.221.221.221 dev br-lan.100 proto 221 scope link src 221.221.221.221\n' >"$MOCK_STATE/route"; exit 0 ;;
esac
exit 1
EOF

cat >"$mock_bin/ubus" <<'EOF'
#!/bin/sh
printf 'ubus %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-ubus"
[ "${1:-}" = -S ] && [ "${2:-}" = call ] || exit 1
case "${3:-}" in
	network.interface.lan) path=br-lan ;;
	network.interface.cr6608_vlan) path=br-lan.100 ;;
	*) exit 1 ;;
esac
if [ -e "$MOCK_STATE/runtime-down" ]; then up=false; else up=true; fi
[ ! -e "$MOCK_STATE/runtime-mismatch" ] || path=br-lan.100
printf '{"up":%s,"l3_device":"%s","device":"%s"}\n' "$up" "$path" "$path"
EOF

cat >"$mock_bin/jsonfilter" <<'EOF'
#!/bin/sh
printf 'jsonfilter %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-jsonfilter"
json=''; expr=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-s) json="${2:-}"; shift 2 ;;
		-e) expr="${2:-}"; shift 2 ;;
		*) exit 1 ;;
	esac
done
case "$expr" in
	'@.up') printf '%s\n' "$json" | sed -n 's/.*"up":\(true\|false\).*/\1/p' ;;
	'@.l3_device') printf '%s\n' "$json" | sed -n 's/.*"l3_device":"\([^"]*\)".*/\1/p' ;;
	'@.device') printf '%s\n' "$json" | sed -n 's/.*"device":"\([^"]*\)".*/\1/p' ;;
	*) exit 1 ;;
esac
EOF

cat >"$mock_bin/firewall" <<'EOF'
#!/bin/sh
printf 'firewall %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-firewall"
[ "${1:-}" = stop ] || exit 2
[ ! -s "$MOCK_STATE/address" ] || : >"$MOCK_STATE/firewall-stopped-while-address-live"
rm -f "$MOCK_STATE/applied" "$MOCK_STATE/static-rules"
[ -e "$MOCK_STATE/firewall-retain-fw4" ] || rm -f "$MOCK_STATE/fw4-table"
exit 0
EOF

cat >"$mock_bin/rescue-init" <<'EOF'
#!/bin/sh
printf 'rescue-init %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-rescue-init"
case "${1:-}" in
	running)
		running_count="$(cat "$MOCK_STATE/rescue-init-running-count" 2>/dev/null || printf 0)"
		running_count=$((running_count + 1))
		printf '%s\n' "$running_count" >"$MOCK_STATE/rescue-init-running-count"
		if [ -s "$MOCK_STATE/monitor-stop-on-running-call" ]; then
			stop_on="$(cat "$MOCK_STATE/monitor-stop-on-running-call")"
			[ "$running_count" -lt "$stop_on" ] || exit 1
		fi
		[ ! -e "$MOCK_STATE/monitor-stopped" ]
		;;
	enabled) [ ! -e "$MOCK_STATE/monitor-disabled" ] ;;
	*) exit 2 ;;
esac
EOF

cat >"$mock_bin/flock" <<'EOF'
#!/bin/sh
printf 'flock %s\n' "$*" >>"$MOCK_STATE/calls"
[ -e /proc/$$/fd/9 ] && : >"$MOCK_STATE/flock-saw-fd9" || : >"$MOCK_STATE/flock-missed-fd9"
[ ! -e "$MOCK_STATE/lock-busy" ] || exit 1
exit 0
EOF
cat >"$mock_bin/logger" <<'EOF'
#!/bin/sh
printf 'logger %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-logger"
exit 0
EOF
cat >"$mock_bin/mktemp" <<'EOF'
#!/bin/sh
[ ! -e "$MOCK_STATE/mktemp-fail" ] || exit 1
exec /usr/bin/mktemp "$@"
EOF
cat >"$mock_bin/setsid" <<'EOF'
#!/bin/sh
if [ -x /usr/bin/setsid ]; then
	exec /usr/bin/setsid "$@"
fi
exec "$@"
EOF
cat >"$mock_bin/kill" <<'EOF'
#!/bin/sh
exec /bin/kill "$@"
EOF
cat >"$mock_bin/self-guard" <<'EOF'
#!/bin/sh
printf 'self-guard %s\n' "$*" >>"$MOCK_STATE/calls"
[ ! -e /proc/$$/fd/9 ] || : >"$MOCK_STATE/fd9-leak-self-guard"
case "${1:-}" in
	health)
		[ ! -e "$MOCK_STATE/monitor-health-busy" ] || exit 75
		[ ! -e "$MOCK_STATE/monitor-always-fail" ] || exit 1
		if [ -e "$MOCK_STATE/monitor-health-fail" ]; then
			rm -f "$MOCK_STATE/monitor-health-fail"
			exit 1
		fi
		exit 0
		;;
	apply)
		monitor_count="$(cat "$MOCK_STATE/monitor-apply-count" 2>/dev/null || printf 0)"
		monitor_count=$((monitor_count + 1))
		printf '%s\n' "$monitor_count" >"$MOCK_STATE/monitor-apply-count"
		[ ! -e "$MOCK_STATE/monitor-always-fail" ] || exit 1
		: >"$MOCK_STATE/monitor-recovered"
		exit 0
		;;
	close)
		printf '%s\n' 'ip -4 -o addr show' >>"$MOCK_STATE/calls"
		rm -f "$MOCK_STATE/address" "$MOCK_STATE/route" "$MOCK_STATE/applied"
		printf '%s\n' 'ip -4 addr del 221.221.221.221/32 dev br-lan' \
			>>"$MOCK_STATE/calls"
		exit 0
		;;
esac
exit 2
EOF
chmod 0755 "$mock_bin"/* || fail 'mock modes'

reset_state() {
	rm -f "$mock_state/address" "$mock_state/route" "$mock_state/applied" \
		"$mock_state/static-rules" \
		"$mock_state/prechecked" "$mock_state/nft-stdin" \
		"$mock_state/fail-precheck" "$mock_state/fail-deny-precheck" \
		"$mock_state/fail-apply" "$mock_state/fail-deny-apply" \
		"$mock_state/fail-addr-delete" \
		"$mock_state/no-ap" "$mock_state/bad-network" \
		"$mock_state/foreign-route" \
		"$mock_state/vlan-primary" "$mock_state/path-conflict" \
		"$mock_state/radio1-disabled" "$mock_state/primary0-disabled" \
		"$mock_state/primary1-disabled" \
		"$mock_state/primary1-sta" "$mock_state/primary1-mesh" \
		"$mock_state/alternative-ap" "$mock_state/ambiguous-ap" \
		"$mock_state/receiver-mesh-smartap" "$mock_state/receiver-mesh-cr6608" \
		"$mock_state/receiver-wds-smartap" "$mock_state/receiver-wds-cr6608" \
		"$mock_state/receiver-vlan" "$mock_state/runtime-down" \
		"$mock_state/runtime-mismatch" \
		"$mock_state/custom-primary0" "$mock_state/custom-primary1" \
		"$mock_state/iw-timeout" \
		"$mock_state/iw-stop-hang" "$mock_state/iw-stop-hang-pid" \
		"$mock_state/iw-hang" "$mock_state/iw-hang-pid" \
		"$mock_state/lock-busy" "$mock_state/rescue-on-lan" \
		"$mock_state/lan-management" "$mock_state/monitor-health-fail" \
		"$mock_state/monitor-health-busy" \
		"$mock_state/monitor-always-fail" "$mock_state/monitor-apply-count" \
		"$mock_state/monitor-recovered" "$mock_state/mktemp-fail" \
		"$mock_state/uci-delay" "$mock_state/uci-delay-started" \
		"$mock_state/flock-saw-fd9" "$mock_state/flock-missed-fd9" \
		"$mock_state/firewall-stopped-while-address-live" \
		"$mock_state/fw4-table" "$mock_state/fail-list-tables" \
		"$mock_state/firewall-retain-fw4" \
		"$mock_state/monitor-stopped" "$mock_state/monitor-disabled" \
		"$mock_state/monitor-stop-on-running-call" \
		"$mock_state/rescue-init-running-count" \
		"$mock_state/qos-table" "$mock_state/security-table" \
		"$mock_state"/fd9-leak-* "$tmp/runtime/route-owner" \
		"$tmp/runtime/ruleset.snapshot" "$tmp/runtime/operator-quiesced"
	: >"$mock_state/calls"
}

assert_endpoint_dark() {
	case_name="$1"
	[ ! -e "$mock_state/address" ] || fail "$case_name retained address"
	[ ! -e "$mock_state/rescue-on-lan" ] || fail "$case_name retained LAN rescue address"
	! grep -Fq 'ifdown wlanrescue' "$mock_state/calls" || fail "$case_name invoked unsafe ifdown"
	grep -Fq 'ip -4 -o addr show' "$mock_state/calls" || fail "$case_name skipped global address scan"
}

assert_failure_closed() {
	case_name="$1"
	assert_endpoint_dark "$case_name"
	[ ! -e "$mock_state/route" ] || fail "$case_name retained owned route"
}

assert_close_precedes_validation() {
	case_name="$1"
	close_line="$(grep -n -m1 '^ip -4 -o addr show$' "$mock_state/calls" | cut -d: -f1)"
	uci_line="$(grep -n -m1 '^uci ' "$mock_state/calls" | cut -d: -f1)"
	iw_line="$(grep -n -m1 '^iw dev$' "$mock_state/calls" | cut -d: -f1)"
	[ -n "$close_line" ] && [ -n "$uci_line" ] && [ -n "$iw_line" ] ||
		fail "$case_name missing close/UCI/iw ordering evidence"
	[ "$close_line" -lt "$uci_line" ] && [ "$close_line" -lt "$iw_line" ] ||
		fail "$case_name validated before darkening endpoint"
}

reset_state
"$guard" apply >"$tmp/apply.out" 2>"$tmp/apply.err" || {
	cat "$tmp/apply.err" >&2
	fail 'healthy apply'
}
grep -Eq '^CR6608_RESCUE_GUARD=PASS mode=apply wifi_aps=1 address=221\.221\.221\.221/32$' \
	"$tmp/apply.out" || fail 'healthy PASS marker'
[ ! -s "$tmp/apply.err" ] || fail 'healthy apply stderr'
[ -e "$mock_state/address" ] && [ -s "$mock_state/route" ] || fail 'healthy endpoint activation'
grep -Fq '221.221.221.221 dev br-lan proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'healthy route did not follow primary AP LAN path'
[ "$(cat "$tmp/runtime/route-owner" 2>/dev/null)" = br-lan ] || fail 'route owner state missing'
[ -s "$tmp/runtime/ruleset.snapshot" ] || fail 'exact ruleset snapshot missing'
[ "$(stat -c '%a' "$tmp/runtime/ruleset.snapshot" 2>/dev/null)" = 600 ] || \
	fail 'ruleset snapshot is not root-only'
grep -Fq 'ip -4 route add 221.221.221.221/32 dev br-lan src 221.221.221.221 scope link proto 221' \
	"$mock_state/calls" || fail 'product protocol route add absent'
assert_close_precedes_validation 'healthy apply'
grep -Fq CR6608_RESCUE_DENY_ONLY_BRIDGE_IN "$mock_state/nft-stdin" || \
	fail 'deny-only rules did not reach nft stdin'
grep -Fq CR6608_RESCUE_DENY_ONLY_INET_IN "$mock_state/nft-stdin" || \
	fail 'atomic inet deny did not reach nft stdin'
[ -e "$mock_state/flock-saw-fd9" ] && [ ! -e "$mock_state/flock-missed-fd9" ] || \
	fail 'flock acquisition did not inherit fd 9'
if find "$mock_state" -maxdepth 1 -name 'fd9-leak-*' -print -quit | grep -q .; then
	fail 'watched non-flock child inherited fd 9'
fi
grep -Fq 'nft -c -f' "$mock_state/calls" || fail 'nft precheck absent'
precheck_line="$(grep -n -m1 'nft -c -f' "$mock_state/calls" | cut -d: -f1)"
apply_line="$(grep -n -m1 'nft -f' "$mock_state/calls" | cut -d: -f1)"
address_line="$(grep -n -m1 'ip -4 addr add 221.221.221.221/32 dev br-lan' "$mock_state/calls" | cut -d: -f1)"
[ "$precheck_line" -lt "$apply_line" ] && [ "$apply_line" -lt "$address_line" ] || \
	fail 'nft must precheck/apply before address attachment'

rules="$mock_state/applied"
grep -Fq 'elements = { "phy0-ap0" }' "$rules" || fail 'dynamic AP set absent'
grep -Fq 'iifname @wifi_ap_ifaces ether type ip ip daddr 221.221.221.221 tcp dport { 80, 443 } meta mark set 0x6608cafe accept' "$rules" || \
	fail 'Wi-Fi web allow absent'
grep -Fq 'iifname "br-lan" meta mark 0x6608cafe ip daddr 221.221.221.221 accept' "$rules" || \
	fail 'inet ingress does not require the AP packet mark'
grep -Fq 'ether type ip ip daddr 221.221.221.221 counter drop comment "CR6608_RESCUE_WIRED_DENY"' "$rules" || \
	fail 'unconditional wired ingress deny absent'
grep -Fq 'ether type ip ip saddr 221.221.221.221 drop comment "CR6608_RESCUE_WIRED_REPLY_DENY"' "$rules" || \
	fail 'unconditional wired egress deny absent'
for spoof_marker in CR6608_RESCUE_SOURCE_SPOOF_ARP_DENY \
	CR6608_RESCUE_SOURCE_SPOOF_VLAN_ARP_DENY \
	CR6608_RESCUE_SOURCE_SPOOF_IP_DENY \
	CR6608_RESCUE_SOURCE_SPOOF_VLAN_IP_DENY; do
	grep -Fq "$spoof_marker" "$rules" || fail "cable source-spoof gate absent: $spoof_marker"
done
grep -Fq 'oifname @wifi_ap_ifaces ether type ip ip saddr 221.221.221.221 tcp sport { 80, 443 } meta mark 0x6608cafe accept' \
	"$rules" || fail 'IP reply bridge path does not require the inet output mark'
! grep -Fq 'oifname @wifi_ap_ifaces ether type ip ip saddr 221.221.221.221 tcp sport { 80, 443 } meta mark set' \
	"$rules" || fail 'bridge egress can mint the trusted IP reply mark'
! grep -Eq 'ether type ip ip (saddr|daddr) 169[.]254[.]66[.]1' "$rules" || \
	fail 'active bridge rules black-hole separately routed legacy traffic'
allow_line="$(grep -n -m1 'CR6608_RESCUE_WIFI_WEB' "$rules" | cut -d: -f1)"
deny_line="$(grep -n -m1 'CR6608_RESCUE_WIRED_DENY' "$rules" | cut -d: -f1)"
[ "$allow_line" -lt "$deny_line" ] || fail 'wired deny precedes Wi-Fi allow'
! grep -F 'elements =' "$rules" | grep -Eq 'lan[123]|wan' || fail 'wired connector entered AP set'

# OpenWrt rc.common invokes stop_service before procd_kill. The init script's
# quiesce marker must make a monitor wake in that interval reinforce CLOSED,
# and ordinary apply/health must never clear an operator stop.
: >"$mock_state/calls"
"$rescue_stop_order" >"$tmp/stop-order.out" 2>"$tmp/stop-order.err" || \
	fail 'rc.common stop-order simulation'
[ -f "$tmp/runtime/operator-quiesced" ] && \
	[ ! -L "$tmp/runtime/operator-quiesced" ] || fail 'operator quiesce marker missing'
assert_failure_closed 'rc.common stop-order monitor wake'
grep -Fxq 'CR6608_RESCUE_GUARD=QUIESCED mode=apply' \
	"$tmp/stop-order-monitor-wake.out" || fail 'monitor wake ignored operator quiesce'
! grep -Eq '^ip -4 addr add 221[.]221[.]221[.]221/32 ' "$mock_state/calls" || \
	fail 'monitor wake reattached address between stop_service and procd_kill'
"$guard" health >"$tmp/quiesced-health.out" 2>"$tmp/quiesced-health.err" || \
	fail 'quiesced health should be a non-recovery success'
grep -Fxq 'CR6608_RESCUE_GUARD=QUIESCED mode=health' \
	"$tmp/quiesced-health.out" || fail 'quiesced health marker'
assert_failure_closed 'quiesced health'
: >"$mock_state/fail-apply"
if "$guard" start >"$tmp/quiesced-start-fail.out" \
	2>"$tmp/quiesced-start-fail.err"; then
	fail 'failed explicit start reported success'
fi
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'failed explicit start cleared operator quiesce'
rm -f "$mock_state/fail-apply"
"$guard" apply >"$tmp/post-failed-start-apply.out" \
	2>"$tmp/post-failed-start-apply.err" || fail 'apply after failed start'
grep -Fxq 'CR6608_RESCUE_GUARD=QUIESCED mode=apply' \
	"$tmp/post-failed-start-apply.out" || fail 'apply bypassed failed-start quiesce'
assert_failure_closed 'apply after failed explicit start'
"$guard" start >"$tmp/quiesced-start.out" 2>"$tmp/quiesced-start.err" || \
	fail 'explicit start after operator quiesce'
grep -Eq '^CR6608_RESCUE_GUARD=PASS mode=start wifi_aps=1 address=221\.221\.221\.221/32$' \
	"$tmp/quiesced-start.out" || fail 'explicit start PASS marker'
[ ! -e "$tmp/runtime/operator-quiesced" ] && \
	[ ! -L "$tmp/runtime/operator-quiesced" ] || fail 'explicit start retained quiesce marker'
[ "$(cat "$mock_state/address" 2>/dev/null)" = br-lan ] || \
	fail 'explicit start did not restore monitored endpoint'

# Even failure to derive a unique instance identity must first publish stop
# intent and close an endpoint left live by an earlier instance.
rm -f "$mock_state/startup-guard-calls" "$mock_state/procd-calls" \
	"$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed"
if STARTUP_PROBE_MODE=full MOCK_START_TICKS_FAIL=1 \
	MOCK_PROCD_RUNNING=1 "$startup_probe" \
	>"$tmp/start-identity-fail.out" 2>"$tmp/start-identity-fail.err"; then
	fail 'failed per-start identity derivation reported success'
fi
grep -Fxq quiesce "$mock_state/startup-guard-calls" || \
	fail 'identity derivation failure occurred before quiesce'
[ ! -s "$mock_state/procd-calls" ] || \
	fail 'identity derivation failure constructed a procd instance'
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'identity derivation failure lost quiesce marker'
assert_failure_closed 'per-start identity derivation failure'

# rc.common publishes the procd instance only after start_service returns.
# start_service must therefore leave CLOSED + quiesced even after it has built
# the instance; only service_started may activate after observing ownership.
rm -f "$mock_state/startup-guard-calls" "$mock_state/procd-calls" \
	"$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
STARTUP_PROBE_MODE=start-only MOCK_PROCD_RUNNING=1 "$startup_probe" \
	>"$tmp/start-service-only.out" 2>"$tmp/start-service-only.err" || \
	fail 'quiesced procd instance preparation failed'
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'start_service did not retain operator quiesce'
assert_failure_closed 'start_service before procd publication'
grep -Fxq quiesce "$mock_state/startup-guard-calls" || \
	fail 'start_service did not quiesce before constructing procd instance'
! grep -Fxq start "$mock_state/startup-guard-calls" || \
	fail 'start_service activated before procd publication'
[ -s "$mock_state/procd-instance-prepared" ] || \
	fail 'start_service did not construct a named procd instance'
[ ! -e "$mock_state/procd-registered" ] || \
	fail 'fixture published procd before start_service returned'

# Model rc.common invoking service_started despite a preparation callback
# failure. The per-start preparation flag must deny activation even if a stale
# service_running response says an instance exists.
: >"$mock_state/startup-guard-calls"
if STARTUP_PROBE_MODE=started-only MOCK_PROCD_RUNNING=1 "$startup_probe" \
	>"$tmp/service-started-unprepared.out" \
	2>"$tmp/service-started-unprepared.err"; then
	fail 'unprepared service_started reported success'
fi
! grep -Fxq start "$mock_state/startup-guard-calls" || \
	fail 'unprepared service_started activated rescue'
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'unprepared service_started lost quiesce'
assert_failure_closed 'unprepared service_started'

# If the registered monitor never becomes observable, no explicit start may
# run and later apply/health calls remain unable to clear the quiesce marker.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
: >"$mock_state/startup-guard-calls"
if STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=0 "$startup_probe" \
	>"$tmp/service-started-fail.out" 2>"$tmp/service-started-fail.err"; then
	fail 'missing procd monitor passed service_started verification'
fi
! grep -Fxq start "$mock_state/startup-guard-calls" || \
	fail 'missing procd monitor reached explicit start'
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'failed procd registration did not retain quiesce'
assert_failure_closed 'failed procd registration'
"$guard" apply >"$tmp/post-registration-fail-apply.out" \
	2>"$tmp/post-registration-fail-apply.err" || fail 'apply after registration failure'
grep -Fxq 'CR6608_RESCUE_GUARD=QUIESCED mode=apply' \
	"$tmp/post-registration-fail-apply.out" || \
	fail 'apply bypassed failed procd-registration quiesce'
assert_failure_closed 'apply after failed procd registration'

# A stale monitor from a previous restart must not satisfy this start.  The
# service probes only its per-start instance name, never wildcard ownership.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
: >"$mock_state/startup-guard-calls"
if STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=0 \
	MOCK_STALE_INSTANCE_RUNNING=1 "$startup_probe" \
	>"$tmp/service-started-stale.out" 2>"$tmp/service-started-stale.err"; then
	fail 'stale procd instance satisfied per-start monitor ownership'
fi
! grep -Fxq start "$mock_state/startup-guard-calls" || \
	fail 'stale procd instance reached explicit guard start'
grep -Eq '^running monitor-[0-9]+-[0-9]+$' "$mock_state/procd-calls" || \
	fail 'service_running did not receive the per-start instance name'
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'stale procd instance test lost quiesce'
assert_failure_closed 'stale procd instance during restart'

# A guard activation error after registration also remains durably CLOSED.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
: >"$mock_state/fail-startup-activation"
: >"$mock_state/startup-guard-calls"
if STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=1 "$startup_probe" \
	>"$tmp/service-started-activation-fail.out" \
	2>"$tmp/service-started-activation-fail.err"; then
	fail 'failed post-registration activation reported success'
fi
rm -f "$mock_state/fail-startup-activation"
grep -Fxq start "$mock_state/startup-guard-calls" || \
	fail 'registered activation failure did not reach guard start'
[ ! -e "$mock_state/start-before-registration" ] || \
	fail 'guard start preceded mocked procd registration/observation'
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'failed post-registration activation cleared quiesce'
assert_failure_closed 'failed post-registration activation'

# A registered monitor must survive the normal boot race where AP netdevs are
# not yet discoverable. Bounded retries recover once the guard can activate.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration" \
	"$mock_state/startup-attempt-count"
: >"$mock_state/startup-guard-calls"
STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=1 MOCK_STARTUP_FAIL_COUNT=2 \
	"$startup_probe" >"$tmp/service-started-delayed-pass.out" \
	2>"$tmp/service-started-delayed-pass.err" || \
	fail 'delayed AP readiness did not recover within the activation bound'
[ "$(cat "$mock_state/startup-attempt-count")" = 3 ] || \
	fail 'startup activation retry count is not bounded/deterministic'
[ ! -e "$mock_state/start-before-registration" ] || \
	fail 'startup retry preceded monitor registration/observation'
[ ! -e "$tmp/runtime/operator-quiesced" ] || \
	fail 'successful delayed activation retained quiesce'
[ "$(cat "$mock_state/address" 2>/dev/null)" = br-lan ] || \
	fail 'successful delayed activation left endpoint closed'

# procd publication may be visible only after several boot-time scheduling
# turns. The bounded registration wait must not quiesce a valid named monitor.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration" \
	"$mock_state/procd-ready-probes"
: >"$mock_state/startup-guard-calls"
STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=1 MOCK_PROCD_READY_AFTER=7 \
	"$startup_probe" >"$tmp/service-started-registration-delay.out" \
	2>"$tmp/service-started-registration-delay.err" || \
	fail 'delayed procd registration failed ordered activation'
[ "$(cat "$mock_state/procd-ready-probes")" -gt 7 ] || \
	fail 'delayed procd registration was not exercised'
[ ! -e "$mock_state/start-before-registration" ] || \
	fail 'guard start preceded delayed procd registration'
[ ! -e "$tmp/runtime/operator-quiesced" ] || \
	fail 'successful delayed registration retained quiesce'

# Successful startup ordering is quiesce -> publish/observe monitor -> start;
# the final service_running check must also close if ownership vanishes during
# the synchronous address/rules activation.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
: >"$mock_state/startup-guard-calls"
STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=1 "$startup_probe" \
	>"$tmp/service-started-pass.out" 2>"$tmp/service-started-pass.err" || \
	fail 'live procd monitor failed ordered activation'
[ ! -e "$mock_state/start-before-registration" ] || \
	fail 'guard start preceded mocked procd registration/observation'
[ "$(sed -n '1p' "$mock_state/startup-guard-calls")" = quiesce ] && \
	grep -Fxq start "$mock_state/startup-guard-calls" || \
	fail 'successful startup did not quiesce before explicit start'
[ ! -e "$tmp/runtime/operator-quiesced" ] || \
	fail 'successful monitored activation retained quiesce'
[ "$(cat "$mock_state/address" 2>/dev/null)" = br-lan ] || \
	fail 'successful monitored activation left endpoint closed'

rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
: >"$mock_state/startup-guard-calls"
if STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=1 \
	MOCK_PROCD_VANISH_AFTER_START=1 "$startup_probe" \
	>"$tmp/service-started-vanished.out" 2>"$tmp/service-started-vanished.err"; then
	fail 'monitor loss during activation reported success'
fi
[ -f "$tmp/runtime/operator-quiesced" ] || \
	fail 'monitor loss during activation did not re-publish quiesce'
assert_failure_closed 'monitor vanished during activation'

# Restore the monitored endpoint for the remaining firewall-stop tests.
rm -f "$mock_state/procd-registered" "$mock_state/procd-instance-prepared" \
	"$mock_state/procd-instance-published" "$mock_state/monitor-observed" \
	"$mock_state/activation-complete" "$mock_state/start-before-registration"
STARTUP_PROBE_MODE=full MOCK_PROCD_RUNNING=1 "$startup_probe" \
	>/dev/null 2>&1 || fail 'restore after procd startup ordering tests'

# Product stop uses `fw4 stop` (inet/fw4 only), never the upstream init
# `fw4 flush` behavior.  The wrapper still removes the live address, holds the
# transition lock across the stop, then verifies nft before reattaching /32.
: >"$mock_state/calls"
: >"$mock_state/qos-table"
: >"$mock_state/security-table"
: >"$mock_state/fw4-table"
"$firewall_init" >"$tmp/firewall-stop.out" 2>"$tmp/firewall-stop.err" || \
	fail 'serialized firewall stop'
grep -Eq '^CR6608_RESCUE_GUARD=PASS mode=firewall-stop wifi_aps=1 address=221\.221\.221\.221/32$' \
	"$tmp/firewall-stop.out" || fail 'firewall-stop PASS marker'
[ ! -e "$mock_state/firewall-stopped-while-address-live" ] || \
	fail 'firewall stopped while rescue address was still live'
firewall_close_line="$(grep -n -m1 '^ip -4 addr del 221.221.221.221/32 dev br-lan$' \
	"$mock_state/calls" | cut -d: -f1)"
firewall_stop_line="$(grep -n -m1 '^firewall stop$' "$mock_state/calls" | cut -d: -f1)"
firewall_reapply_line="$(awk -v after="$firewall_stop_line" \
	'NR > after && /^nft -f / { print NR; exit }' "$mock_state/calls")"
firewall_address_line="$(awk -v after="$firewall_reapply_line" \
	'NR > after && /^ip -4 addr add 221[.]221[.]221[.]221\/32 dev br-lan$/ { print NR; exit }' \
	"$mock_state/calls")"
[ -n "$firewall_close_line" ] && [ -n "$firewall_stop_line" ] && \
	[ -n "$firewall_reapply_line" ] && [ -n "$firewall_address_line" ] && \
	[ "$firewall_close_line" -lt "$firewall_stop_line" ] && \
	[ "$firewall_stop_line" -lt "$firewall_reapply_line" ] && \
	[ "$firewall_reapply_line" -lt "$firewall_address_line" ] || \
	fail 'firewall-stop close/flush/reapply/address ordering'
[ "$(cat "$mock_state/address" 2>/dev/null)" = br-lan ] && \
	[ -s "$mock_state/applied" ] && [ -s "$mock_state/static-rules" ] || \
	fail 'firewall-stop did not restore the verified endpoint'
[ -e "$mock_state/qos-table" ] && [ -e "$mock_state/security-table" ] || \
	fail 'fw4-own-table stop deleted unrelated QoS/security nft owners'
[ "$(cat "$mock_state/rescue-init-running-count" 2>/dev/null)" -ge 5 ] || \
	fail 'firewall-stop did not prove monitor ownership before and after restore'
! grep -Eq '^rescue-init (start|stop|restart)$' "$mock_state/calls" || \
	fail 'firewall-stop changed monitor lifecycle ownership'

# LuCI may Stop and Disable the rescue service before the operator stops the
# firewall.  That action must remain authoritative: the direct firewall init
# path removes only fw4, reinstalls deny-only, and never opens an unmonitored
# endpoint merely because the service had once been enabled.
: >"$mock_state/monitor-stopped"
: >"$mock_state/monitor-disabled"
: >"$mock_state/fw4-table"
: >"$mock_state/calls"
"$firewall_init" >"$tmp/firewall-stop-stopped.out" \
	2>"$tmp/firewall-stop-stopped.err" || fail 'stopped-monitor firewall stop'
grep -Fxq 'CR6608_RESCUE_GUARD=CLOSED mode=firewall-stop monitor=stopped' \
	"$tmp/firewall-stop-stopped.out" || fail 'stopped monitor did not remain CLOSED'
assert_failure_closed 'stopped/disabled monitor firewall stop'
grep -Fq CR6608_RESCUE_DENY_ONLY "$mock_state/applied" || \
	fail 'stopped monitor lacks deny-only nft boundary'
! grep -Eq '^ip -4 addr add 221[.]221[.]221[.]221/32 ' "$mock_state/calls" || \
	fail 'stopped monitor firewall stop reattached the endpoint'
! grep -Eq '^(uci|iw) ' "$mock_state/calls" || \
	fail 'stopped monitor firewall stop entered activation validation'

# Also close when a monitor that owned the endpoint disappears after fw4 Stop
# but before activation.  The third running probe is the post-validation gate.
rm -f "$mock_state/monitor-stopped" "$mock_state/monitor-disabled" \
	"$mock_state/rescue-init-running-count"
"$guard" apply >/dev/null 2>&1 || fail 'restore before monitor-race firewall stop'
: >"$mock_state/fw4-table"
printf '3\n' >"$mock_state/monitor-stop-on-running-call"
: >"$mock_state/calls"
"$firewall_init" >"$tmp/firewall-stop-race.out" \
	2>"$tmp/firewall-stop-race.err" || fail 'monitor-race firewall stop'
grep -Fxq 'CR6608_RESCUE_GUARD=CLOSED mode=firewall-stop monitor=stopped' \
	"$tmp/firewall-stop-race.out" || fail 'vanished monitor did not remain CLOSED'
assert_failure_closed 'monitor vanished during firewall stop'
grep -Fq CR6608_RESCUE_DENY_ONLY "$mock_state/applied" || \
	fail 'monitor-race path lacks deny-only nft boundary'
! grep -Eq '^ip -4 addr add 221[.]221[.]221[.]221/32 ' "$mock_state/calls" || \
	fail 'monitor-race path reattached the endpoint'

# A successful fw4 exit status is not proof that its table disappeared.
rm -f "$mock_state/monitor-stop-on-running-call" \
	"$mock_state/rescue-init-running-count"
"$guard" apply >/dev/null 2>&1 || fail 'restore before fw4 absence proof'
: >"$mock_state/fw4-table"
: >"$mock_state/firewall-retain-fw4"
: >"$mock_state/calls"
if "$firewall_init" >"$tmp/firewall-stop-retained.out" \
	2>"$tmp/firewall-stop-retained.err"; then
	fail 'firewall-stop trusted rc=0 while inet/fw4 remained'
fi
grep -Fq 'CR6608_RESCUE_GUARD=FAIL reason=firewall-stop' \
	"$tmp/firewall-stop-retained.err" || fail 'retained fw4 failure reason'
assert_failure_closed 'retained fw4 table'

# Restore the healthy monitored endpoint for the remaining health contracts.
rm -f "$mock_state/firewall-retain-fw4" "$mock_state/fw4-table" \
	"$mock_state/rescue-init-running-count"
"$guard" apply >/dev/null 2>&1 || fail 'restore after firewall lifecycle tests'

# The monitor-facing health transaction validates only live ownership/runtime
# state.  It must not pay for or trust the full UCI configuration walk.
: >"$mock_state/calls"
"$guard" health >"$tmp/health.out" 2>"$tmp/health.err" || fail 'healthy fast health'
grep -Eq '^CR6608_RESCUE_GUARD=PASS mode=health wifi_aps=1 address=221\.221\.221\.221/32$' \
	"$tmp/health.out" || fail 'health PASS marker'
[ ! -s "$tmp/health.err" ] || fail 'healthy health stderr'
! grep -q '^uci ' "$mock_state/calls" || fail 'health invoked UCI'
grep -Fq 'iw dev' "$mock_state/calls" || fail 'health skipped live AP enumeration'
health_nft_line="$(grep -n -m1 '^nft list table' "$mock_state/calls" | cut -d: -f1)"
health_iw_line="$(grep -n -m1 '^iw dev$' "$mock_state/calls" | cut -d: -f1)"
[ -n "$health_nft_line" ] && [ "$health_nft_line" -lt "$health_iw_line" ] || \
	fail 'health waited on iw before checking the exact nft snapshot'

# Rules disappearing after a successful apply must close immediately on health check.
rm -f "$mock_state/applied"
if "$guard" health >"$tmp/lost.out" 2>"$tmp/lost.err"; then
	fail 'lost rules reported success'
fi
! grep -Fq 'CR6608_RESCUE_GUARD=PASS' "$tmp/lost.out" || fail 'lost rules emitted PASS'
grep -Fq 'CR6608_RESCUE_GUARD=FAIL reason=rules-snapshot-health' "$tmp/lost.err" || fail 'lost rules reason'
assert_failure_closed 'lost rules'

# A stale extra AP ifname must not remain authorized after the live AP set
# changes, even though every currently expected AP is still present.
reset_state
"$guard" apply >"$tmp/stale-seed.out" 2>"$tmp/stale-seed.err" || fail 'stale AP seed apply'
sed 's/elements = { "phy0-ap0" }/elements = { "phy0-ap0", "stale-ap9" }/' \
	"$mock_state/applied" >"$mock_state/applied.new" || fail 'stale AP mutation'
mv "$mock_state/applied.new" "$mock_state/applied" || fail 'stale AP mutation publish'
if "$guard" health >"$tmp/stale-ap.out" 2>"$tmp/stale-ap.err"; then
	fail 'stale AP set reported success'
fi
grep -Fq 'reason=rules-snapshot-health' "$tmp/stale-ap.err" || fail 'stale AP set reason'
assert_failure_closed 'stale AP set'

reset_state
mv "$mock_bin/nft" "$mock_bin/nft.saved"
if "$guard" apply >"$tmp/missing.out" 2>"$tmp/missing.err"; then fail 'missing nft success'; fi
mv "$mock_bin/nft.saved" "$mock_bin/nft"
! grep -Fq PASS "$tmp/missing.out" || fail 'missing nft emitted PASS'
grep -Fq 'reason=dark-close' "$tmp/missing.err" || fail 'missing nft dark-first reason'
assert_failure_closed 'missing nft'

reset_state
: >"$mock_state/fail-precheck"
if "$guard" apply >"$tmp/fail-precheck.out" 2>"$tmp/fail-precheck.err"; then
	fail 'invalid nft rules reported success'
fi
! grep -Fq PASS "$tmp/fail-precheck.out" || fail 'invalid nft rules emitted PASS'
grep -Fq 'reason=rules-precheck' "$tmp/fail-precheck.err" || fail 'invalid nft reason'
assert_failure_closed 'invalid nft rules'

# Close must not depend on tmpfs scratch space, and every cleanup failure keeps
# the already-installed bridge+inet deny-only transaction in place.
reset_state
printf 'br-lan\n' >"$mock_state/address"
: >"$mock_state/fail-addr-delete"
if "$guard" close >"$tmp/addr-delete.out" 2>"$tmp/addr-delete.err"; then
	fail 'address deletion failure reported a successful close'
fi
[ -e "$mock_state/address" ] || fail 'address-delete failure fixture was unexpectedly removed'
grep -Fq 'reason=close-incomplete' "$tmp/addr-delete.err" || fail 'address-delete failure reason'
grep -Fq CR6608_RESCUE_DENY_ONLY_BRIDGE_IP_IN "$mock_state/applied" || \
	fail 'address-delete failure lost bridge deny-only'
grep -Fq CR6608_RESCUE_DENY_ONLY_INET_IN "$mock_state/applied" || \
	fail 'address-delete failure lost inet deny-only'

reset_state
: >"$mock_state/mktemp-fail"
if "$guard" apply >"$tmp/mktemp-fail.out" 2>"$tmp/mktemp-fail.err"; then
	fail 'mktemp/ENOSPC simulation reported success'
fi
grep -Fq CR6608_RESCUE_DENY_ONLY_BRIDGE_IN "$mock_state/applied" || \
	fail 'mktemp failure prevented streamed close deny'
assert_failure_closed 'mktemp failure'

# Route state is published only after route add.  If the publication target is
# unusable, the indistinguishable route is preserved behind deny-only instead
# of risking deletion of a foreign replacement.
reset_state
mkdir -p "$tmp/runtime/route-owner" || fail 'route-owner collision fixture'
if "$guard" apply >"$tmp/owner-state.out" 2>"$tmp/owner-state.err"; then
	fail 'unpublishable route owner state succeeded'
fi
grep -Fq 'reason=route-owner-state' "$tmp/owner-state.err" || fail 'route-owner failure reason'
[ -s "$mock_state/route" ] || fail 'unpublished route was destructively rolled back'
[ ! -e "$mock_state/address" ] || fail 'unpublished route retained the local endpoint address'
grep -Fq CR6608_RESCUE_DENY_ONLY_INET_IN "$mock_state/applied" || \
	fail 'unpublished route is not protected by deny-only'
rmdir "$tmp/runtime/route-owner" || fail 'route-owner collision cleanup'

reset_state
: >"$mock_state/bad-network"
: >"$mock_state/rescue-on-lan"
: >"$mock_state/lan-management"
if "$guard" apply >"$tmp/bad-network.out" 2>"$tmp/bad-network.err"; then fail 'all unsupported primary paths succeeded'; fi
grep -Fq 'reason=network:no-active-primary-ap' "$tmp/bad-network.err" || fail 'unsupported primary paths reason'
assert_failure_closed 'bridge binding'
grep -Fq 'ip -4 addr del 221.221.221.221/32 dev br-lan' "$mock_state/calls" || \
	fail 'invalid binding rescue address survived direct close'
[ -e "$mock_state/lan-management" ] || fail 'invalid binding damaged LAN management state'

# The primary AP network, not the mere existence of a VLAN section, owns the
# return path.  Both primary radios must agree or activation fails closed.
reset_state
: >"$mock_state/vlan-primary"
"$guard" apply >"$tmp/vlan.out" 2>"$tmp/vlan.err" || fail 'VLAN primary apply'
grep -Fq 'dev br-lan.100 proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'VLAN primary route path'
[ "$(cat "$tmp/runtime/route-owner" 2>/dev/null)" = br-lan.100 ] || fail 'VLAN route owner state'

reset_state
: >"$mock_state/path-conflict"
if "$guard" apply >"$tmp/path-conflict.out" 2>"$tmp/path-conflict.err"; then
	fail 'conflicting primary AP paths succeeded'
fi
grep -Fq 'reason=network:primary-ap-path-conflict' "$tmp/path-conflict.err" || \
	fail 'primary AP path conflict reason'
assert_failure_closed 'primary AP path conflict'

reset_state
: >"$mock_state/path-conflict"
: >"$mock_state/radio1-disabled"
"$guard" apply >"$tmp/disabled-radio.out" 2>"$tmp/disabled-radio.err" || \
	fail 'disabled secondary radio blocked active primary'
grep -Fq 'dev br-lan proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'disabled radio path selection'

reset_state
: >"$mock_state/primary0-disabled"
"$guard" apply >"$tmp/disabled-primary0.out" 2>"$tmp/disabled-primary0.err" || \
	fail 'disabled 2.4 GHz primary blocked valid 5 GHz AP'
grep -Fq 'dev br-lan proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'disabled 2.4 GHz path selection'

reset_state
: >"$mock_state/primary1-disabled"
"$guard" apply >"$tmp/disabled-primary1.out" 2>"$tmp/disabled-primary1.err" || \
	fail 'disabled 5 GHz primary blocked valid 2.4 GHz AP'
grep -Fq 'dev br-lan proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'disabled 5 GHz path selection'

reset_state
: >"$mock_state/primary0-disabled"
: >"$mock_state/primary1-disabled"
if "$guard" apply >"$tmp/all-primary-disabled.out" 2>"$tmp/all-primary-disabled.err"; then
	fail 'all primary APs disabled left rescue active'
fi
grep -Fq 'reason=network:no-active-primary-ap' "$tmp/all-primary-disabled.err" || \
	fail 'all primary APs disabled reason'
assert_failure_closed 'all primary APs disabled'

# Every receiver ID emitted by both supported configuration engines, and the
# direct UI conversion of the primary 5 GHz iface to client/mesh, must leave
# rescue reachable through the still-valid 2.4 GHz AP.
for receiver_fixture in receiver-mesh-smartap receiver-mesh-cr6608 \
	receiver-wds-smartap receiver-wds-cr6608 primary1-sta primary1-mesh; do
	reset_state
	: >"$mock_state/$receiver_fixture"
	"$guard" apply >"$tmp/$receiver_fixture.out" 2>"$tmp/$receiver_fixture.err" || \
		fail "$receiver_fixture blocked valid 2.4 GHz rescue path"
	grep -Fq 'dev br-lan proto 221 scope link src 221.221.221.221' \
		"$mock_state/route" || fail "$receiver_fixture selected wrong rescue path"
done

reset_state
: >"$mock_state/custom-primary0"
"$guard" apply >"$tmp/custom-primary0.out" 2>"$tmp/custom-primary0.err" || \
	fail 'custom 2.4 GHz network blocked valid 5 GHz management AP'
grep -Fq 'dev br-lan proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'custom 2.4 GHz network selected wrong path'

reset_state
: >"$mock_state/custom-primary1"
"$guard" apply >"$tmp/custom-primary1.out" 2>"$tmp/custom-primary1.err" || \
	fail 'custom 5 GHz network blocked valid 2.4 GHz management AP'

reset_state
: >"$mock_state/custom-primary0"
: >"$mock_state/custom-primary1"
if "$guard" apply >"$tmp/all-custom-primary.out" 2>"$tmp/all-custom-primary.err"; then
	fail 'all primary APs on custom networks left rescue active'
fi
grep -Fq 'reason=network:no-active-primary-ap' "$tmp/all-custom-primary.err" || \
	fail 'all custom primary APs reason'
assert_failure_closed 'all custom primary APs'

reset_state
: >"$mock_state/primary0-disabled"
: >"$mock_state/alternative-ap"
: >"$mock_state/vlan-primary"
"$guard" apply >"$tmp/alternative-primary.out" 2>"$tmp/alternative-primary.err" || \
	fail 'single enabled fallback AP failed'
grep -Fq 'dev br-lan.100 proto 221 scope link src 221.221.221.221' \
	"$mock_state/route" || fail 'enabled fallback AP path'

reset_state
: >"$mock_state/primary0-disabled"
: >"$mock_state/alternative-ap"
: >"$mock_state/ambiguous-ap"
if "$guard" apply >"$tmp/ambiguous-primary.out" 2>"$tmp/ambiguous-primary.err"; then
	fail 'ambiguous fallback AP selection succeeded'
fi
grep -Fq 'reason=wireless:radio0-primary-ap' "$tmp/ambiguous-primary.err" || \
	fail 'ambiguous fallback AP reason'
assert_failure_closed 'ambiguous fallback AP'

# A foreign route is never replaced or removed.  Protocol 221 alone is also
# insufficient ownership proof without the root-only state file.
reset_state
printf '221.221.221.221 dev br-lan.100 proto static scope link src 221.221.221.221\n' \
	>"$mock_state/foreign-route"
if "$guard" apply >"$tmp/foreign-route.out" 2>"$tmp/foreign-route.err"; then
	fail 'foreign route conflict succeeded'
fi
grep -Fq 'reason=route-conflict' "$tmp/foreign-route.err" || fail 'foreign route conflict reason'
grep -Fq 'proto static' "$mock_state/foreign-route" || fail 'foreign route was changed'
assert_endpoint_dark 'foreign route conflict'

# A foreign exact-prefix route injected beside a healthy owned route must make
# health fail closed.  The owned route is removable through its root-only state;
# the foreign route is preserved byte-for-byte.
reset_state
"$guard" apply >"$tmp/mixed-route-setup.out" 2>"$tmp/mixed-route-setup.err" || \
	fail 'mixed route health setup'
printf '221.221.221.221 dev br-lan.100 proto static scope link src 221.221.221.221\n' \
	>"$mock_state/foreign-route"
if "$guard" health >"$tmp/mixed-route.out" 2>"$tmp/mixed-route.err"; then
	fail 'owned and foreign route health succeeded'
fi
grep -Fq 'reason=route-health' "$tmp/mixed-route.err" || fail 'mixed route health reason'
grep -Fqx '221.221.221.221 dev br-lan.100 proto static scope link src 221.221.221.221' \
	"$mock_state/foreign-route" || fail 'mixed route health changed the foreign route'
assert_failure_closed 'owned and foreign route health'

reset_state
printf '221.221.221.221 dev br-lan proto 221 scope link src 221.221.221.221\n' \
	>"$mock_state/route"
if "$guard" apply >"$tmp/forged-route.out" 2>"$tmp/forged-route.err"; then
	fail 'stateless protocol route accepted as owned'
fi
grep -Fq 'reason=route-conflict' "$tmp/forged-route.err" || fail 'stateless route conflict reason'
[ -s "$mock_state/route" ] || fail 'stateless protocol route was deleted'
assert_endpoint_dark 'stateless protocol route'

# External command and lock failures must be bounded and leave the endpoint
# dark.  The hung iw process ignores TERM so the KILL path is exercised.
reset_state
: >"$mock_state/iw-timeout"
if "$guard" apply >"$tmp/iw-timeout.out" 2>"$tmp/iw-timeout.err"; then
	fail 'iw timeout status succeeded'
fi
grep -Fq 'reason=iw-enumeration' "$tmp/iw-timeout.err" || fail 'iw timeout reason'
assert_failure_closed 'iw timeout status'

reset_state
: >"$mock_state/iw-hang"
printf 'br-lan\n' >"$mock_state/address"
: >"$mock_state/applied"
printf '221.221.221.221 dev br-lan proto 221 scope link src 221.221.221.221\n' \
	>"$mock_state/route"
mkdir -p "$tmp/runtime" || fail 'hung iw owner directory'
printf 'br-lan\n' >"$tmp/runtime/route-owner"
hung_started="$(date +%s)"
if "$guard" apply >"$tmp/iw-hang.out" 2>"$tmp/iw-hang.err"; then
	fail 'hung iw succeeded'
fi
hung_elapsed=$(( $(date +%s) - hung_started ))
[ "$hung_elapsed" -le 30 ] || fail "hung iw exceeded transaction bound (${hung_elapsed}s)"
grep -Fq 'reason=iw-enumeration' "$tmp/iw-hang.err" || fail 'hung iw reason'
assert_failure_closed 'hung iw'
assert_close_precedes_validation 'hung iw apply'
hung_pid="$(cat "$mock_state/iw-hang-pid" 2>/dev/null || true)"
[ -n "$hung_pid" ] || fail 'hung iw pid not recorded'
if /bin/kill -0 "$hung_pid" 2>/dev/null; then
	fail 'hung iw child survived watchdog'
fi

reset_state
: >"$mock_state/lock-busy"
printf 'br-lan\n' >"$mock_state/address"
printf '221.221.221.221 dev br-lan proto 221 scope link src 221.221.221.221\n' \
	>"$mock_state/route"
mkdir -p "$tmp/runtime" || fail 'busy lock owner directory'
printf 'br-lan\n' >"$tmp/runtime/route-owner"
"$guard" apply >"$tmp/lock-busy.out" 2>"$tmp/lock-busy.err"
lock_busy_rc=$?
[ "$lock_busy_rc" -eq 75 ] || fail "busy lock status $lock_busy_rc"
grep -Fq 'CR6608_RESCUE_GUARD=BUSY reason=lock-acquire' "$tmp/lock-busy.err" || \
	fail 'busy lock reason'
[ "$(grep -c '^flock -xn 9$' "$mock_state/calls")" -eq 2 ] || fail 'lock retry bound'
[ -e "$mock_state/address" ] && [ -e "$mock_state/route" ] || \
	fail 'lock loser mutated active transaction state'
! grep -q '^ip ' "$mock_state/calls" || fail 'lock loser invoked endpoint mutation'
! grep -q '^nft ' "$mock_state/calls" || fail 'lock loser invoked nft mutation'

# Exercise the actual util-linux flock implementation, not only the behavioral
# mock: while one dark-first transaction is inside UCI validation, a second
# process must return EX_TEMPFAIL without entering the endpoint mutation path.
if real_flock_bin="$(command -v flock 2>/dev/null)" && [ -x "$real_flock_bin" ]; then
	real_flock_guard="$tmp/cr6608-rescue-guard-real-flock"
	sed \
		-e "s@FLOCK_BIN='$mock_bin/flock'@FLOCK_BIN='$real_flock_bin'@" \
		-e "s@COMMAND_TIMEOUT='1'@COMMAND_TIMEOUT='4'@" \
		"$guard" >"$real_flock_guard" || fail 'real-flock guard rewrite'
	chmod 0755 "$real_flock_guard" || fail 'real-flock guard mode'
	reset_state
	: >"$mock_state/uci-delay"
	"$real_flock_guard" apply >"$tmp/flock-winner.out" 2>"$tmp/flock-winner.err" &
	flock_winner_pid=$!
	flock_wait=0
	while [ ! -e "$mock_state/uci-delay-started" ] && [ "$flock_wait" -lt 80 ]; do
		sleep 0.05
		flock_wait=$((flock_wait + 1))
	done
	[ -e "$mock_state/uci-delay-started" ] || {
		kill "$flock_winner_pid" 2>/dev/null || true
		wait "$flock_winner_pid" 2>/dev/null || true
		fail 'real flock winner never entered validation'
	}
	"$real_flock_guard" apply >"$tmp/flock-loser.out" 2>"$tmp/flock-loser.err"
	flock_loser_rc=$?
	[ "$flock_loser_rc" -eq 75 ] || fail "real flock loser status $flock_loser_rc"
	grep -Fq 'BUSY reason=lock-acquire' "$tmp/flock-loser.err" || fail 'real flock loser reason'
	wait "$flock_winner_pid" || {
		cat "$tmp/flock-winner.err" >&2
		fail 'real flock winner failed'
	}

	# A watched child stopped mid-command and then SIGKILLed by the watchdog
	# must not retain fd9.  The next transaction must acquire the real kernel
	# flock immediately rather than returning BUSY forever.
	reset_state
	: >"$mock_state/iw-stop-hang"
	if "$real_flock_guard" apply >"$tmp/flock-stop.out" 2>"$tmp/flock-stop.err"; then
		fail 'SIGSTOP fixture unexpectedly succeeded'
	fi
	grep -Fq 'reason=iw-enumeration' "$tmp/flock-stop.err" || fail 'SIGSTOP watchdog reason'
	stopped_pid="$(cat "$mock_state/iw-stop-hang-pid" 2>/dev/null || true)"
	[ -n "$stopped_pid" ] || fail 'SIGSTOP child pid missing'
	if /bin/kill -0 "$stopped_pid" 2>/dev/null; then fail 'SIGKILL did not reap stopped child'; fi
	rm -f "$mock_state/iw-stop-hang"
	"$real_flock_guard" apply >"$tmp/flock-after-kill.out" 2>"$tmp/flock-after-kill.err" || \
		fail 'watched child retained fd9/kernel flock after SIGKILL'
fi

# The monitor recovers through a full apply transaction, retries exactly three
# times on persistent failure, then stays alive and dark with bounded backoff.
reset_state
: >"$mock_state/monitor-health-fail"
"$guard" monitor >"$tmp/monitor-recover.out" 2>"$tmp/monitor-recover.err" &
monitor_pid=$!
monitor_wait=0
while [ ! -e "$mock_state/monitor-recovered" ] && [ "$monitor_wait" -lt 50 ]; do
	sleep 0.1
	monitor_wait=$((monitor_wait + 1))
done
[ -e "$mock_state/monitor-recovered" ] || {
	kill "$monitor_pid" 2>/dev/null || true
	wait "$monitor_pid" 2>/dev/null || true
	fail 'monitor did not recover'
}
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
[ "$(cat "$mock_state/monitor-apply-count" 2>/dev/null)" -eq 1 ] || \
	fail 'monitor recovery apply count'

reset_state
: >"$mock_state/monitor-health-busy"
"$guard" monitor >"$tmp/monitor-busy.out" 2>"$tmp/monitor-busy.err" &
monitor_pid=$!
monitor_wait=0
while ! grep -Fq 'self-guard health' "$mock_state/calls" && [ "$monitor_wait" -lt 50 ]; do
	sleep 0.1
	monitor_wait=$((monitor_wait + 1))
done
grep -Fq 'self-guard health' "$mock_state/calls" || fail 'monitor busy health not called'
sleep 0.2
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
! grep -Fq 'self-guard apply' "$mock_state/calls" || \
	fail 'monitor recovered while serialized transaction was busy'

reset_state
: >"$mock_state/monitor-always-fail"
"$guard" monitor >"$tmp/monitor-fail.out" 2>"$tmp/monitor-fail.err" &
monitor_pid=$!
monitor_wait=0
while ! grep -Fq 'monitor-recovery-exhausted' "$mock_state/calls" && \
	[ "$monitor_wait" -lt 100 ]; do
	sleep 0.05
	monitor_wait=$((monitor_wait + 1))
done
grep -Fq 'monitor-recovery-exhausted' "$mock_state/calls" || {
	kill "$monitor_pid" 2>/dev/null || true
	wait "$monitor_pid" 2>/dev/null || true
	fail 'monitor exhaustion not logged'
}
[ "$(cat "$mock_state/monitor-apply-count" 2>/dev/null)" -eq 3 ] || \
	fail 'monitor recovery retry bound'
grep -Fq 'self-guard close' "$mock_state/calls" || \
	fail 'monitor exhaustion skipped serialized close'
kill -0 "$monitor_pid" 2>/dev/null || fail 'monitor exited after recovery exhaustion'
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
assert_failure_closed 'monitor recovery exhaustion'

# Execute the firewall include itself.  A busy or incomplete rescue transition
# must never make fw4's already-loaded primary ruleset fail, while a successful
# close may reapply through the existing monitor or start it when absent.
include_guard="$tmp/include-guard"
include_init="$tmp/include-init"
include_copy="$tmp/cr6608-rescue-firewall-include"
cat >"$include_guard" <<'EOF'
#!/bin/sh
printf 'include-guard %s\n' "$*" >>"$MOCK_STATE/include-calls"
case "${1:-}" in
	close) exit "${INCLUDE_CLOSE_RC:-0}" ;;
	apply) exit 0 ;;
esac
exit 2
EOF
cat >"$include_init" <<'EOF'
#!/bin/sh
printf 'include-init %s\n' "$*" >>"$MOCK_STATE/include-calls"
	case "${1:-}" in
		enabled) [ "${INCLUDE_ENABLED:-0}" = 1 ] ;;
		running) [ "${INCLUDE_RUNNING:-0}" = 1 ] ;;
		reload) exit 0 ;;
	esac
EOF
chmod 0755 "$include_guard" "$include_init" || fail 'include mock modes'
sed \
	-e "s@INIT='/etc/init.d/cr6608-rescue-guard'@INIT='$include_init'@" \
	-e "s@GUARD='/usr/sbin/cr6608-rescue-guard'@GUARD='$include_guard'@" \
	"$FIREWALL_INCLUDE" >"$include_copy" || fail 'include rewrite'
chmod 0755 "$include_copy" || fail 'include mode'

for include_failure_rc in 75 1; do
	: >"$mock_state/include-calls"
	if ! PATH="$mock_bin:$PATH" INCLUDE_CLOSE_RC="$include_failure_rc" \
		"$include_copy"; then
		fail "firewall include propagated close rc $include_failure_rc"
	fi
	grep -Fxq 'include-guard close' "$mock_state/include-calls" || fail 'include skipped dark-first close'
	! grep -q '^include-init ' "$mock_state/include-calls" || \
		fail "include started service after close rc $include_failure_rc"
done

: >"$mock_state/include-calls"
PATH="$mock_bin:$PATH" INCLUDE_CLOSE_RC=0 INCLUDE_ENABLED=1 INCLUDE_RUNNING=1 \
	"$include_copy" || fail 'running-monitor include execution'
grep -Fxq 'include-init reload' "$mock_state/include-calls" || \
	fail 'running monitor was not reloaded after firewall reload'
! grep -Fxq 'include-init start' "$mock_state/include-calls" || \
	fail 'running monitor was replaced after firewall reload'

: >"$mock_state/include-calls"
PATH="$mock_bin:$PATH" INCLUDE_CLOSE_RC=0 INCLUDE_ENABLED=1 INCLUDE_RUNNING=0 \
	"$include_copy" || fail 'stopped-monitor include execution'
! grep -Eq '^include-init (start|reload)$' "$mock_state/include-calls" || \
	fail 'stopped monitor was activated after firewall reload'

# Execute the first-boot migration with a stateful command fixture.  It must
# establish close/deny before its first UCI access, complete a clean migration,
# and reject an unowned product-ID collision before staging any UCI delta.
migration_bin="$tmp/migration-bin"
mkdir -p "$migration_bin" || fail 'migration mock directory'
cat >"$migration_bin/guard" <<'EOF'
#!/bin/sh
printf 'guard %s\n' "$*" >>"$MIGRATION_LOG"
[ "${1:-}" = close ]
EOF
cat >"$migration_bin/ip" <<'EOF'
#!/bin/sh
printf 'ip %s\n' "$*" >>"$MIGRATION_LOG"
case " $* " in
	*' route show exact 221.221.221.221/32 '*) exit 0 ;;
	*) exit 0 ;;
esac
EOF
cat >"$migration_bin/uci" <<'EOF'
#!/bin/sh
printf 'uci %s\n' "$*" >>"$MIGRATION_LOG"
savedir=''
uci_savedir_option=''
if [ "${1:-}" = -P ] || [ "${1:-}" = -t ]; then
	uci_savedir_option="$1"
	savedir="${2:-}"
	shift 2
fi
[ "${1:-}" = -q ] && shift
command_name="${1:-}"; shift || true
case "$command_name" in
	changes)
		[ ! -e "$MIGRATION_STATE/global-delta" ] || printf 'global.pending=value\n'
		exit 0
		;;
	get)
		key="${1:-}"
		if [ "${MIGRATION_PREVIOUS_HEAD:-0}" = 1 ]; then
			case "$key" in
				network.wlanrescue) printf 'interface\n'; exit 0 ;;
				network.wlanrescue.cr6608_owner) exit 1 ;;
				network.wlanrescue.device) printf '%s\n' "${MIGRATION_PREVIOUS_DEVICE:-br-lan}"; exit 0 ;;
				network.wlanrescue.proto) printf 'static\n'; exit 0 ;;
				network.wlanrescue.ipaddr) printf '169.254.66.1\n'; exit 0 ;;
				network.wlanrescue.netmask) printf '255.255.255.0\n'; exit 0 ;;
				network.wlanrescue.ipv6) printf '0\n'; exit 0 ;;
				network.wlanrescue.delegate) printf '0\n'; exit 0 ;;
				'firewall.@zone[0].name') printf 'lan\n'; exit 0 ;;
				'firewall.@zone[0].network')
					if [ -n "$savedir" ] && [ -e "$savedir/legacy-lan-clean" ]; then
						printf 'lan\n'
					else
						printf 'lan wlanrescue\n'
					fi
					exit 0
					;;
				'firewall.@zone[0].input'|'firewall.@zone[0].output'|'firewall.@zone[0].forward')
					printf 'ACCEPT\n'; exit 0 ;;
			esac
		fi
		if [ "${MIGRATION_NETWORK_COLLISION:-0}" = 1 ]; then
			case "$key" in
				network.wlanrescue) printf 'interface\n'; exit 0 ;;
				network.wlanrescue.cr6608_owner) printf 'foreign-owner\n'; exit 0 ;;
			esac
		fi
		if [ "${MIGRATION_COLLISION:-0}" = 1 ]; then
			case "$key" in
				firewall.cr6608_rescue_zone) printf 'zone\n'; exit 0 ;;
				firewall.cr6608_rescue_zone.cr6608_owner) printf 'foreign-owner\n'; exit 0 ;;
			esac
		fi
		exit 1
		;;
	show)
		case "${1:-}" in
			network.wlanrescue)
				if [ -n "$savedir" ] && [ -s "$savedir/mock-ops" ] &&
				   grep -Fq 'set network.wlanrescue.proto=none' "$savedir/mock-ops"; then
					printf '%s\n' \
						'network.wlanrescue=interface' \
						"network.wlanrescue.cr6608_owner='wlanrescue-v1'" \
						"network.wlanrescue.proto='none'" \
						"network.wlanrescue.ipv6='0'" \
						"network.wlanrescue.delegate='0'" \
						"network.wlanrescue.auto='0'"
				elif [ "${MIGRATION_PREVIOUS_HEAD:-0}" = 1 ]; then
					printf '%s\n' \
						'network.wlanrescue=interface' \
						"network.wlanrescue.device='${MIGRATION_PREVIOUS_DEVICE:-br-lan}'" \
						"network.wlanrescue.proto='static'" \
						"network.wlanrescue.ipaddr='169.254.66.1'" \
						"network.wlanrescue.netmask='255.255.255.0'" \
						"network.wlanrescue.ipv6='0'" \
						"network.wlanrescue.delegate='0'"
				else
					exit 1
				fi
				;;
			firewall|'firewall.@zone[0]')
				if [ "${MIGRATION_PREVIOUS_HEAD:-0}" = 1 ]; then
					printf '%s\n' \
						'firewall.@zone[0]=zone' \
						"firewall.@zone[0].name='lan'" \
						"firewall.@zone[0].network='lan' 'wlanrescue'" \
						"firewall.@zone[0].input='ACCEPT'" \
						"firewall.@zone[0].output='ACCEPT'" \
						"firewall.@zone[0].forward='ACCEPT'"
				else
					printf '%s\n' 'firewall.lan=zone' "firewall.lan.name='lan'"
				fi
				;;
			*) exit 1 ;;
		esac
		;;
	set|add_list|del_list|delete)
		if [ -z "$savedir" ]; then
			: >"$MIGRATION_STATE/global-delta"
		else
			: >"$savedir/mock-delta"
			printf '%s %s\n' "$command_name" "${1:-}" >>"$savedir/mock-ops"
		fi
		if [ "$command_name" = del_list ] &&
		   [ "${1:-}" = 'firewall.@zone[0].network=wlanrescue' ]; then
			[ -n "$savedir" ] || exit 1
			: >"$savedir/legacy-lan-clean"
		fi
		if [ "${MIGRATION_FAIL_MID:-0}" = 1 ] &&
		   [ "${1:-}" = firewall.cr6608_rescue_ping=rule ]; then
			exit 1
		fi
		exit 0
		;;
	commit)
		[ "$uci_savedir_option" = -t ] && [ -n "$savedir" ] || {
			: >"$MIGRATION_STATE/global-delta"
			exit 1
		}
		case "${1:-}" in
			network)
				grep -Fqx 'delete network.cr6608_rescue_dev' \
					"$savedir/mock-ops" || exit 1
				grep -Fqx 'set network.wlanrescue.cr6608_owner=wlanrescue-v1' \
					"$savedir/mock-ops" || exit 1
				grep -Fqx 'set network.wlanrescue.proto=none' \
					"$savedir/mock-ops" || exit 1
				! grep -Eq 'set network\.wlanrescue\.(device|ipaddr|netmask)=' \
					"$savedir/mock-ops" || exit 1
				: >"$MIGRATION_STATE/committed-network"
				;;
			firewall)
				grep -Fqx 'set firewall.cr6608_rescue_zone.cr6608_owner=wlanrescue-v1' \
					"$savedir/mock-ops" || exit 1
				if [ "${MIGRATION_PREVIOUS_HEAD:-0}" = 1 ]; then
					[ -e "$savedir/legacy-lan-clean" ] || exit 1
				fi
				: >"$MIGRATION_STATE/committed-firewall"
				;;
			uhttpd)
				[ -e "$MIGRATION_STATE/committed-network" ] &&
					[ -e "$MIGRATION_STATE/committed-firewall" ] || exit 1
				: >"$MIGRATION_STATE/migration-complete"
				;;
			*) exit 1 ;;
		esac
		exit 0
		;;
	*) exit 1 ;;
esac
EOF
for migration_service in network firewall uhttpd; do
	cat >"$migration_bin/$migration_service" <<'EOF'
#!/bin/sh
printf 'service %s %s\n' "${0##*/}" "$*" >>"$MIGRATION_LOG"
exit 0
EOF
done
chmod 0755 "$migration_bin"/* || fail 'migration mock modes'
migration_copy="$tmp/96-cr6608-wlanrescue-isolation"
sed \
	-e "s@RESCUE_GUARD='/usr/sbin/cr6608-rescue-guard'@RESCUE_GUARD='$migration_bin/guard'@" \
	-e "s@/sbin/ip@$migration_bin/ip@g" \
	-e "s@/etc/init.d/network@$migration_bin/network@g" \
	-e "s@/etc/init.d/firewall@$migration_bin/firewall@g" \
	-e "s@/etc/init.d/uhttpd@$migration_bin/uhttpd@g" \
	"$MIGRATION" >"$migration_copy" || fail 'migration rewrite'
chmod 0755 "$migration_copy" || fail 'migration copy mode'

migration_log="$mock_state/migration-calls"
migration_state="$mock_state/migration-state"
mkdir -p "$migration_state" || fail 'migration state directory'
: >"$migration_log"
PATH="$migration_bin:$PATH" MIGRATION_LOG="$migration_log" MIGRATION_STATE="$migration_state" \
	MIGRATION_COLLISION=0 MIGRATION_NETWORK_COLLISION=0 MIGRATION_FAIL_MID=0 \
	"$migration_copy" || fail 'clean migration execution'
[ "$(sed -n '1p' "$migration_log")" = 'guard close' ] || \
	fail 'migration accessed state before establishing deny-only'
grep -Eq '^uci -P [^ ]+ set firewall\.cr6608_rescue_web\.mark=0x6608cafe/0xffffffff$' "$migration_log" || \
	fail 'migration did not stage the exact web packet mark'
grep -Eq '^uci -t [^ ]+ commit firewall$' "$migration_log" || fail 'clean migration did not commit firewall privately'
! grep -q '^service ' "$migration_log" || fail 'UCI-default migration reloaded a service before netifd/fw4'

for previous_device in br-lan br-lan.100; do
	: >"$migration_log"
	rm -rf "$migration_state"/*
	PATH="$migration_bin:$PATH" MIGRATION_LOG="$migration_log" MIGRATION_STATE="$migration_state" \
		MIGRATION_PREVIOUS_HEAD=1 MIGRATION_PREVIOUS_DEVICE="$previous_device" \
		MIGRATION_COLLISION=0 MIGRATION_NETWORK_COLLISION=0 MIGRATION_FAIL_MID=0 \
		"$migration_copy" || fail "historical delegate=0 migration ($previous_device)"
	grep -Eq '^uci -P [^ ]+ -q delete network\.cr6608_rescue_dev$' "$migration_log" || \
		fail "historical dummy metadata was not deleted ($previous_device)"
	grep -Eq '^uci -P [^ ]+ set network\.wlanrescue\.proto=none$' "$migration_log" || \
		fail "historical rescue was not made addressless ($previous_device)"
	! grep -q '^service ' "$migration_log" || \
		fail "historical migration reloaded a service ($previous_device)"
done

: >"$migration_log"
if PATH="$migration_bin:$PATH" MIGRATION_LOG="$migration_log" MIGRATION_STATE="$migration_state" \
	MIGRATION_COLLISION=1 MIGRATION_NETWORK_COLLISION=0 MIGRATION_FAIL_MID=0 \
	"$migration_copy"; then
	fail 'unowned migration section collision succeeded'
fi
[ "$(sed -n '1p' "$migration_log")" = 'guard close' ] || \
	fail 'collision path did not establish deny first'
! grep -Eq '^uci .* (set|add_list|delete|commit) ' "$migration_log" || \
	fail 'collision path staged a persistent UCI delta'

: >"$migration_log"
printf 'foreign-network-sentinel\n' >"$migration_state/foreign-network"
if PATH="$migration_bin:$PATH" MIGRATION_LOG="$migration_log" MIGRATION_STATE="$migration_state" \
	MIGRATION_COLLISION=0 MIGRATION_NETWORK_COLLISION=1 MIGRATION_FAIL_MID=0 \
	"$migration_copy"; then
	fail 'foreign network.wlanrescue collision succeeded'
fi
[ "$(cat "$migration_state/foreign-network")" = foreign-network-sentinel ] || \
	fail 'foreign network collision was changed'
! grep -Eq '^uci .* (set|add_list|delete|commit) ' "$migration_log" || \
	fail 'foreign network collision staged a UCI delta'

: >"$migration_log"
rm -f "$migration_state/global-delta"
if PATH="$migration_bin:$PATH" MIGRATION_LOG="$migration_log" MIGRATION_STATE="$migration_state" \
	MIGRATION_COLLISION=0 MIGRATION_NETWORK_COLLISION=0 MIGRATION_FAIL_MID=1 \
	"$migration_copy"; then
	fail 'injected mid-stage migration failure succeeded'
fi
staged_savedir="$(sed -n 's/^uci -P \([^ ]*\) .*/\1/p' "$migration_log" | head -n 1)"
[ -n "$staged_savedir" ] && [ ! -e "$staged_savedir" ] || \
	fail 'failed migration left its private UCI savedir'
[ ! -e "$migration_state/global-delta" ] || fail 'failed migration polluted global UCI deltas'
default_changes="$(PATH="$migration_bin:$PATH" MIGRATION_LOG="$migration_log" \
	MIGRATION_STATE="$migration_state" "$migration_bin/uci" changes network)" || \
	fail 'default UCI changes probe'
[ -z "$default_changes" ] || fail 'default UCI changes are not empty after migration failure'

# On a privileged Linux builder, validate the actual nft parser, bridge->inet
# skb-mark path, wired denial, guard-table-loss fallback, snapshot detection,
# and deny-only recovery inside an isolated network namespace.
real_nft_bin="$(command -v nft 2>/dev/null || true)"
real_ip_bin="$(command -v ip 2>/dev/null || true)"
real_unshare_bin="$(command -v unshare 2>/dev/null || true)"
real_nsenter_bin="$(command -v nsenter 2>/dev/null || true)"
real_ping_bin="$(command -v ping 2>/dev/null || true)"
real_flock_bin="$(command -v flock 2>/dev/null || true)"
real_python_bin="$(command -v python3 2>/dev/null || true)"
real_sysctl_bin="$(command -v sysctl 2>/dev/null || true)"
real_bridge_bin="$(command -v bridge 2>/dev/null || true)"
real_mount_bin="$(command -v mount 2>/dev/null || true)"
real_netns_ran=0
if [ "$(id -u)" -eq 0 ] && [ -x "$real_nft_bin" ] && [ -x "$real_ip_bin" ] && \
	[ -x "$real_unshare_bin" ] && [ -x "$real_nsenter_bin" ] && [ -x "$real_ping_bin" ] && \
	[ -x "$real_flock_bin" ] && [ -x "$real_python_bin" ] && \
	[ -x "$real_sysctl_bin" ] && [ -x "$real_bridge_bin" ] && [ -x "$real_mount_bin" ] && \
	"$real_unshare_bin" -m -n /bin/sh -c '
		set -eu
		"$1" --make-rprivate /
		"$1" -t sysfs sysfs /sys
		test -d /sys/class/net
		"$2" list tables >/dev/null
	' cr6608-real-netns-preflight "$real_mount_bin" "$real_nft_bin" >/dev/null 2>&1; then
	real_net_dir="$tmp/real-netns"
	mkdir -p "$real_net_dir" || fail 'real nft fixture directory'
	real_firewall="$real_net_dir/fw4"
	cat >"$real_firewall" <<EOF
#!/bin/sh
[ "\${1:-}" = stop ] || exit 2
if "$real_nft_bin" list table inet fw4 >/dev/null 2>&1; then
	"$real_nft_bin" delete table inet fw4
else
	exit 1
	fi
EOF
	chmod 0755 "$real_firewall" || fail 'real fw4 fixture mode'
	real_rescue_init="$real_net_dir/rescue-init"
	cat >"$real_rescue_init" <<EOF
#!/bin/sh
case "\${1:-}" in
	running) [ ! -e "$real_net_dir/monitor-stopped" ] ;;
	enabled) [ ! -e "$real_net_dir/monitor-disabled" ] ;;
	*) exit 2 ;;
esac
EOF
	chmod 0755 "$real_rescue_init" || fail 'real rescue init fixture mode'
	real_guard="$real_net_dir/guard"
	sed \
		-e "s@NFT_BIN='$mock_bin/nft'@NFT_BIN='$real_nft_bin'@" \
		-e "s@IP_BIN='$mock_bin/ip'@IP_BIN='$real_ip_bin'@" \
		-e "s@FW4_BIN='$mock_bin/firewall'@FW4_BIN='$real_firewall'@" \
		-e "s@RESCUE_INIT='$mock_bin/rescue-init'@RESCUE_INIT='$real_rescue_init'@" \
		-e "s@FLOCK_BIN='$mock_bin/flock'@FLOCK_BIN='$real_flock_bin'@" \
		-e "s@SYS_CLASS_NET='$mock_sys'@SYS_CLASS_NET='/sys/class/net'@" \
		-e "s@COMMAND_TIMEOUT='1'@COMMAND_TIMEOUT='5'@" \
		"$guard" >"$real_guard" || fail 'real nft guard rewrite'
	chmod 0755 "$real_guard" || fail 'real nft guard mode'
	real_init_stop="$real_net_dir/firewall-init-stop"
	{
		printf '#!/bin/sh\n'
		sed -n '/^stop_service() {$/,/^}$/p' "$FIREWALL_INIT_SOURCE" |
			sed "s@/usr/sbin/cr6608-rescue-guard@$real_guard@g"
		printf 'stop_service\n'
	} >"$real_init_stop" || fail 'direct firewall init fixture'
	chmod 0755 "$real_init_stop" || fail 'direct firewall init fixture mode'
	real_spoof="$real_net_dir/spoof.py"
	cat >"$real_spoof" <<'PY'
import ipaddress
import fcntl
import socket
import struct
import sys

iface = sys.argv[1]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as control:
    ifreq = struct.pack("256s", iface.encode("ascii")[:15])
    mac = fcntl.ioctl(control.fileno(), 0x8927, ifreq)[18:24]
broadcast = b"\xff" * 6

def checksum(data):
    if len(data) & 1:
        data += b"\0"
    words = struct.unpack("!%dH" % (len(data) // 2), data)
    total = sum(words)
    total = (total & 0xffff) + (total >> 16)
    total = (total & 0xffff) + (total >> 16)
    return (~total) & 0xffff

def ethernet(inner_type, payload, tagged):
    if tagged:
        return broadcast + mac + struct.pack("!HHH", 0x8100, 100, inner_type) + payload
    return broadcast + mac + struct.pack("!H", inner_type) + payload

spa = ipaddress.IPv4Address("221.221.221.221").packed
tpa = ipaddress.IPv4Address("169.254.66.2").packed
arp = struct.pack("!HHBBH", 1, 0x0800, 6, 4, 1) + mac + spa + (b"\0" * 6) + tpa
udp = struct.pack("!HHHH", 5555, 5555, 12, 0) + b"test"
ip0 = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), 0x6608, 0, 64, 17, 0, spa, tpa)
ip4 = ip0[:10] + struct.pack("!H", checksum(ip0)) + ip0[12:] + udp

sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
sock.bind((iface, 0))
for tagged in (False, True):
    sock.send(ethernet(0x0806, arp, tagged))
    sock.send(ethernet(0x0800, ip4, tagged))
PY
	chmod 0644 "$real_spoof" || fail 'real spoof fixture mode'
	real_net_test="$real_net_dir/run"
	cat >"$real_net_test" <<'EOF'
#!/bin/sh
set -eu
wifi_ns_pid=''
wired_ns_pid=''
wan_ns_pid=''
web_pid=''
net_cleanup() {
	trap - EXIT HUP INT TERM
	[ -z "$wifi_ns_pid" ] || kill "$wifi_ns_pid" 2>/dev/null || true
	[ -z "$wired_ns_pid" ] || kill "$wired_ns_pid" 2>/dev/null || true
	[ -z "$wan_ns_pid" ] || kill "$wan_ns_pid" 2>/dev/null || true
	[ -z "$web_pid" ] || kill "$web_pid" 2>/dev/null || true
	[ -z "$wifi_ns_pid" ] || wait "$wifi_ns_pid" 2>/dev/null || true
	[ -z "$wired_ns_pid" ] || wait "$wired_ns_pid" 2>/dev/null || true
	[ -z "$wan_ns_pid" ] || wait "$wan_ns_pid" 2>/dev/null || true
	[ -z "$web_pid" ] || wait "$web_pid" 2>/dev/null || true
}
trap net_cleanup EXIT HUP INT TERM

"$REAL_IP" link set lo up
"$REAL_IP" link add br-lan type bridge
"$REAL_IP" link set br-lan up
"$REAL_IP" addr add 10.66.0.1/24 dev br-lan
"$REAL_SYSCTL" -qw net.ipv4.ip_forward=1
"$REAL_SYSCTL" -qw net.ipv4.conf.all.arp_ignore=1
"$REAL_SYSCTL" -qw net.ipv4.conf.default.arp_ignore=1
"$REAL_SYSCTL" -qw net.ipv4.conf.br-lan.arp_ignore=1
"$REAL_IP" link add phy0-ap0 type veth peer name wifi-peer
"$REAL_IP" link set phy0-ap0 master br-lan
"$REAL_IP" link set phy0-ap0 up
"$REAL_IP" link add lan1 type veth peer name wired-peer
"$REAL_IP" link set lan1 master br-lan
"$REAL_IP" link set lan1 up
"$REAL_IP" link add wan0 type veth peer name wan-peer
"$REAL_IP" link set wan0 up
"$REAL_IP" addr add 198.51.100.1/24 dev wan0

"$REAL_UNSHARE" -n sleep 180 &
wifi_ns_pid=$!
"$REAL_UNSHARE" -n sleep 180 &
wired_ns_pid=$!
"$REAL_UNSHARE" -n sleep 180 &
wan_ns_pid=$!
sleep 0.1
"$REAL_IP" link set wifi-peer netns "$wifi_ns_pid"
"$REAL_IP" link set wired-peer netns "$wired_ns_pid"
"$REAL_IP" link set wan-peer netns "$wan_ns_pid"
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" link set lo up
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" link set wifi-peer up
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" addr add 169.254.66.2/24 dev wifi-peer
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" addr add 10.66.0.2/24 dev wifi-peer
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" route add 221.221.221.221/32 \
	dev wifi-peer src 10.66.0.2
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" route add 169.254.66.1/32 via 10.66.0.1
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_IP" link set lo up
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_IP" link set wired-peer up
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_IP" addr add 169.254.66.3/24 dev wired-peer
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_IP" addr add 10.66.0.3/24 dev wired-peer
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_IP" route add 221.221.221.221/32 \
	dev wired-peer src 10.66.0.3
"$REAL_NSENTER" -t "$wan_ns_pid" -n "$REAL_IP" link set lo up
"$REAL_NSENTER" -t "$wan_ns_pid" -n "$REAL_IP" link set wan-peer up
"$REAL_NSENTER" -t "$wan_ns_pid" -n "$REAL_IP" addr add 198.51.100.2/24 dev wan-peer
"$REAL_NSENTER" -t "$wan_ns_pid" -n "$REAL_IP" addr add 169.254.66.1/32 dev lo
"$REAL_NSENTER" -t "$wan_ns_pid" -n "$REAL_IP" route add 10.66.0.0/24 via 198.51.100.1
"$REAL_IP" route add 169.254.66.1/32 via 198.51.100.2 dev wan0

"$REAL_GUARD" apply >"$REAL_NET_DIR/apply.out" 2>"$REAL_NET_DIR/apply.err"
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1 || exit 21
"$REAL_GUARD" quiesce >"$REAL_NET_DIR/quiesce.out" \
	2>"$REAL_NET_DIR/quiesce.err" || exit 58
"$REAL_GUARD" apply >"$REAL_NET_DIR/quiesced-apply.out" \
	2>"$REAL_NET_DIR/quiesced-apply.err" || exit 59
grep -Fxq 'CR6608_RESCUE_GUARD=QUIESCED mode=apply' \
	"$REAL_NET_DIR/quiesced-apply.out" || exit 60
if "$REAL_IP" -4 -o addr show | grep -Fq '221.221.221.221/32'; then exit 61; fi
if "$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1; then
	exit 62
fi
"$REAL_GUARD" start >"$REAL_NET_DIR/post-quiesce-start.out" \
	2>"$REAL_NET_DIR/post-quiesce-start.err" || exit 63
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1 || exit 64
"$REAL_PYTHON" -m http.server 80 --bind 221.221.221.221 \
	>"$REAL_NET_DIR/http.out" 2>"$REAL_NET_DIR/http.err" &
web_pid=$!
web_wait=0
while ! "$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PYTHON" -c \
	'import socket; s=socket.create_connection(("221.221.221.221",80),.4); s.sendall(b"GET / HTTP/1.0\r\n\r\n"); assert s.recv(16).startswith(b"HTTP/"); s.close()' \
	>/dev/null 2>&1; do
	web_wait=$((web_wait + 1))
	[ "$web_wait" -lt 20 ] || exit 47
	sleep 0.05
done
if "$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1; then
	exit 22
fi

# Exercise a wired TCP/80 request as well as ICMP; both must hit the bridge
# cable drop before inet input can see an untrusted packet.  The preceding ARP
# denial intentionally prevents neighbor discovery, so pin the endpoint MAC
# only after proving that denial; otherwise the kernel never emits an IP frame.
rescue_mac="$(cat /sys/class/net/br-lan/address)" || exit 65
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_IP" neigh replace \
	221.221.221.221 lladdr "$rescue_mac" nud permanent dev wired-peer || exit 66
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_PYTHON" -c \
	'import socket; s=socket.socket(); s.settimeout(.4); s.connect_ex(("221.221.221.221",80)); s.close()' \
	>/dev/null 2>&1 || exit 30
"$REAL_NFT" list chain bridge cr6608_rescue ingress |
	grep 'CR6608_RESCUE_WIRED_ARP_DENY' | grep -Eq 'counter packets [1-9]' || exit 31
"$REAL_NFT" list chain bridge cr6608_rescue ingress |
	grep 'CR6608_RESCUE_WIRED_DENY' | grep -Eq 'counter packets [1-9]' || exit 32

# Inject locally forged endpoint-source ARP and IPv4 frames from the cable,
# both untagged and 802.1Q-tagged.  Each dedicated early rule must count/drop.
"$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_PYTHON" "$REAL_SPOOF" wired-peer || exit 33
for spoof_marker in CR6608_RESCUE_SOURCE_SPOOF_ARP_DENY \
	CR6608_RESCUE_SOURCE_SPOOF_VLAN_ARP_DENY \
	CR6608_RESCUE_SOURCE_SPOOF_IP_DENY \
	CR6608_RESCUE_SOURCE_SPOOF_VLAN_IP_DENY; do
	"$REAL_NFT" list chain bridge cr6608_rescue ingress |
		grep "$spoof_marker" | grep -Eq 'counter packets [1-9]' || exit 34
done
"$REAL_GUARD" health >"$REAL_NET_DIR/counter-health.out" \
	2>"$REAL_NET_DIR/counter-health.err" || exit 49
grep -Fq 'CR6608_RESCUE_GUARD=PASS mode=health' \
	"$REAL_NET_DIR/counter-health.out" || exit 50

# The legacy link-local value is denied only for local input/output.  A
# separately routed destination with that exact value must not be black-holed.
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 169.254.66.1 \
	>/dev/null 2>&1 || exit 35

# Standard firewall Stop delegates here.  Only inet/fw4 may disappear;
# independently owned rescue, QoS and DHCP-isolation tables must survive, and
# the rescue address may be reattached only after the serialized recheck.
"$REAL_NFT" add table bridge smartap_qos
"$REAL_NFT" add table bridge smartap_guard
"$REAL_NFT" add table inet fw4
rm -f "$REAL_NET_DIR/wired-stop-attempts" "$REAL_NET_DIR/wired-stop-exposure"
"$REAL_NSENTER" -t "$wired_ns_pid" -n sh -c '
	i=0
	while [ "$i" -lt 4 ]; do
		printf x >>"$REAL_NET_DIR/wired-stop-attempts"
		if "$REAL_PING" -c 1 -W 1 221.221.221.221 >/dev/null 2>&1; then
			printf exposed >>"$REAL_NET_DIR/wired-stop-exposure"
		fi
		i=$((i + 1))
	done
' &
wired_probe_pid=$!
probe_wait=0
while [ ! -s "$REAL_NET_DIR/wired-stop-attempts" ] && [ "$probe_wait" -lt 50 ]; do
	sleep 0.02
	probe_wait=$((probe_wait + 1))
done
[ -s "$REAL_NET_DIR/wired-stop-attempts" ] || exit 36
"$REAL_INIT_STOP" >"$REAL_NET_DIR/firewall-stop.out" \
	2>"$REAL_NET_DIR/firewall-stop.err" || exit 37
wait "$wired_probe_pid" || exit 38
[ ! -s "$REAL_NET_DIR/wired-stop-exposure" ] || exit 39
if "$REAL_NFT" list table inet fw4 >/dev/null 2>&1; then exit 40; fi
"$REAL_NFT" list table bridge smartap_qos >/dev/null 2>&1 || exit 41
"$REAL_NFT" list table bridge smartap_guard >/dev/null 2>&1 || exit 42
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1 || exit 43

# If the rescue service is stopped/disabled first, the exact same shipped init
# Stop path must leave the endpoint dark and deny-only instead of reopening it
# without a procd monitor.
: >"$REAL_NET_DIR/monitor-stopped"
: >"$REAL_NET_DIR/monitor-disabled"
"$REAL_NFT" add table inet fw4
"$REAL_INIT_STOP" >"$REAL_NET_DIR/firewall-stop-disabled.out" \
	2>"$REAL_NET_DIR/firewall-stop-disabled.err" || exit 51
grep -Fxq 'CR6608_RESCUE_GUARD=CLOSED mode=firewall-stop monitor=stopped' \
	"$REAL_NET_DIR/firewall-stop-disabled.out" || exit 52
if "$REAL_IP" -4 -o addr show | grep -Fq '221.221.221.221/32'; then exit 53; fi
"$REAL_NFT" list table bridge cr6608_rescue | \
	grep -Fq CR6608_RESCUE_DENY_ONLY_BRIDGE_IP_IN || exit 54
if "$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1; then
	exit 55
fi
rm -f "$REAL_NET_DIR/monitor-stopped" "$REAL_NET_DIR/monitor-disabled"
"$REAL_GUARD" apply >"$REAL_NET_DIR/post-disabled-apply.out" \
	2>"$REAL_NET_DIR/post-disabled-apply.err" || exit 56
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1 || exit 57

# Remove both live guard tables while retaining the configured address and the
# static fw4-like exact-mark rule.  Neither Wi-Fi nor cable can now synthesize
# the reserved mark, so the endpoint remains unreachable during the window.
"$REAL_NFT" delete table bridge cr6608_rescue
"$REAL_NFT" delete table inet cr6608_rescue
if "$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1; then
	exit 23
fi
if "$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1; then
	exit 24
fi

if "$REAL_GUARD" health >"$REAL_NET_DIR/health.out" 2>"$REAL_NET_DIR/health.err"; then
	exit 25
fi
grep -Fq 'reason=rules-snapshot-health' "$REAL_NET_DIR/health.err" || exit 26
"$REAL_NFT" list table bridge cr6608_rescue |
	grep -Fq CR6608_RESCUE_DENY_ONLY_BRIDGE_IP_IN || exit 27
"$REAL_NFT" list table inet cr6608_rescue |
	grep -Fq CR6608_RESCUE_DENY_ONLY_INET_IN || exit 28
if "$REAL_IP" -4 -o addr show | grep -Fq '221.221.221.221/32'; then
	exit 29
fi

# Closed-mode legacy protection must still leave routed Internet forwarding
# untouched; only stale local ownership is denied.
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 169.254.66.1 \
	>/dev/null 2>&1 || exit 41

# Repeat the live packet gate with the management AP on br-lan.100 and an
# actually tagged station path.  This exercises vlan-type ARP/IP rules rather
# than only proving that the text parses.
: >"$MOCK_STATE/vlan-primary"
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" route del 221.221.221.221/32 \
	dev wifi-peer
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" addr del 169.254.66.2/24 dev wifi-peer
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" addr del 10.66.0.2/24 dev wifi-peer
"$REAL_IP" link set br-lan type bridge vlan_filtering 1
"$REAL_BRIDGE" vlan del dev phy0-ap0 vid 1 >/dev/null 2>&1 || true
"$REAL_BRIDGE" vlan add dev phy0-ap0 vid 100
"$REAL_BRIDGE" vlan add dev br-lan self vid 100
"$REAL_BRIDGE" vlan del dev lan1 vid 1 >/dev/null 2>&1 || true
"$REAL_BRIDGE" vlan add dev lan1 vid 100 pvid untagged
"$REAL_IP" link add link br-lan name br-lan.100 type vlan id 100
"$REAL_IP" link set br-lan.100 up
"$REAL_IP" addr del 10.66.0.1/24 dev br-lan
"$REAL_IP" addr add 10.66.0.1/24 dev br-lan.100
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" link add link wifi-peer \
	name wifi-peer.100 type vlan id 100
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" link set wifi-peer.100 up
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" addr add 169.254.66.2/24 dev wifi-peer.100
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" addr add 10.66.0.2/24 dev wifi-peer.100
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_IP" route add 221.221.221.221/32 \
	dev wifi-peer.100 src 10.66.0.2
"$REAL_GUARD" apply >"$REAL_NET_DIR/vlan-apply.out" 2>"$REAL_NET_DIR/vlan-apply.err" || exit 42
"$REAL_IP" -4 -o addr show dev br-lan.100 | grep -Fq '221.221.221.221/32' || exit 43
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1 || exit 44
"$REAL_NSENTER" -t "$wifi_ns_pid" -n "$REAL_PYTHON" -c \
	'import socket; s=socket.create_connection(("221.221.221.221",80),.5); s.sendall(b"GET / HTTP/1.0\r\n\r\n"); assert s.recv(16).startswith(b"HTTP/"); s.close()' \
	>/dev/null 2>&1 || exit 48
if "$REAL_NSENTER" -t "$wired_ns_pid" -n "$REAL_PING" -c 1 -W 1 221.221.221.221 \
	>/dev/null 2>&1; then
	exit 45
fi
"$REAL_GUARD" close >"$REAL_NET_DIR/vlan-close.out" 2>"$REAL_NET_DIR/vlan-close.err" || exit 46
rm -f "$MOCK_STATE/vlan-primary"
EOF
	chmod 0755 "$real_net_test" || fail 'real nft test mode'
	reset_state
	if MOCK_STATE="$mock_state" REAL_NFT="$real_nft_bin" REAL_IP="$real_ip_bin" \
		REAL_UNSHARE="$real_unshare_bin" REAL_NSENTER="$real_nsenter_bin" \
		REAL_PING="$real_ping_bin" REAL_GUARD="$real_guard" REAL_NET_DIR="$real_net_dir" \
		REAL_SYSCTL="$real_sysctl_bin" REAL_BRIDGE="$real_bridge_bin" \
		REAL_PYTHON="$real_python_bin" REAL_SPOOF="$real_spoof" \
		REAL_INIT_STOP="$real_init_stop" \
		"$real_unshare_bin" -m -n /bin/sh -c '
			set -eu
			"$1" --make-rprivate /
			"$1" -t sysfs sysfs /sys
			shift
			exec "$@"
		' cr6608-real-netns "$real_mount_bin" "$real_net_test"; then
		:
	else
		real_net_rc=$?
		cat "$real_net_dir"/*.err >&2 2>/dev/null || true
		fail "real nft/netns packet-path gate (exit $real_net_rc)"
	fi
	real_netns_ran=1
fi

case "${CR6608_REQUIRE_REAL_NETNS:-${CR6608_REQUIRE_REAL_NFT:-0}}" in
	0|1) ;;
	*) fail 'CR6608_REQUIRE_REAL_NETNS must be 0 or 1' ;;
esac
if [ "${CR6608_REQUIRE_REAL_NETNS:-${CR6608_REQUIRE_REAL_NFT:-0}}" = 1 ] && \
	[ "$real_netns_ran" != 1 ]; then
	fail 'mandatory real nft/netns prerequisites or CAP_NET_ADMIN are unavailable'
fi

if [ -n "${CR6608_RESCUE_REAL_EVIDENCE:-}" ] && [ "$real_netns_ran" = 1 ]; then
	evidence_path="$CR6608_RESCUE_REAL_EVIDENCE"
	evidence_dir="$(dirname -- "$evidence_path")"
	[ "$(id -u)" -eq 0 ] || fail 'real-netns evidence must be emitted by root'
	[ -d "$evidence_dir" ] || fail 'real-netns evidence directory is absent'
	[ ! -L "$evidence_dir" ] || fail 'real-netns evidence directory is a symlink'
	[ ! -e "$evidence_path" ] && [ ! -L "$evidence_path" ] || \
		fail 'real-netns evidence target already exists'
	require_evidence_hex() {
		evidence_value="$1"
		evidence_length="$2"
		evidence_label="$3"
		[ "${#evidence_value}" -eq "$evidence_length" ] || \
			fail "missing or malformed $evidence_label"
		case "$evidence_value" in
			*[!0-9a-f]*) fail "missing or malformed $evidence_label" ;;
		esac
	}
	require_evidence_hex "${CR6608_EVIDENCE_ORIGINAL_COMMIT:-}" 40 \
		'original commit evidence binding'
	require_evidence_hex "${CR6608_EVIDENCE_ORIGINAL_TREE:-}" 40 \
		'original tree evidence binding'
	require_evidence_hex "${CR6608_EVIDENCE_CONTAINER_COMMIT:-}" 40 \
		'container commit evidence binding'
	require_evidence_hex "${CR6608_EVIDENCE_CONTAINER_TREE:-}" 40 \
		'container tree evidence binding'
	require_evidence_hex "${CR6608_EVIDENCE_SOURCE_MANIFEST_SHA256:-}" 64 \
		'payload manifest evidence binding'
	evidence_tmp="$(mktemp "$evidence_dir/.cr6608-rescue-real.XXXXXX")" || \
		fail 'real-netns evidence temp file'
	{
		printf 'rescue_real_evidence_version=1\n'
		printf 'rescue_real_result=pass\n'
		printf 'source_original_commit=%s\n' "${CR6608_EVIDENCE_ORIGINAL_COMMIT:-}"
		printf 'source_original_tree=%s\n' "${CR6608_EVIDENCE_ORIGINAL_TREE:-}"
		printf 'source_container_commit=%s\n' "${CR6608_EVIDENCE_CONTAINER_COMMIT:-}"
		printf 'source_container_tree=%s\n' "${CR6608_EVIDENCE_CONTAINER_TREE:-}"
		printf 'source_payload_manifest_sha256=%s\n' "${CR6608_EVIDENCE_SOURCE_MANIFEST_SHA256:-}"
		printf 'rescue_guard_sha256=%s\n' "$(sha256sum "$GUARD_SOURCE" | awk '{print $1}')"
		printf 'rescue_test_sha256=%s\n' "$(sha256sum "$0" | awk '{print $1}')"
		printf 'rescue_firewall_include_sha256=%s\n' "$(sha256sum "$FIREWALL_INCLUDE" | awk '{print $1}')"
		printf 'rescue_firewall_init_sha256=%s\n' "$(sha256sum "$FIREWALL_INIT_SOURCE" | awk '{print $1}')"
		printf 'rescue_real_paths=br-lan,br-lan.100\n'
		printf 'rescue_real_arp_ignore=all,default,br-lan:1\n'
		printf 'rescue_real_spoof=arp,ipv4,vlan-arp,vlan-ipv4\n'
		printf 'rescue_real_firewall_stop=fw4-own-table\n'
	} >"$evidence_tmp" || {
		rm -f -- "$evidence_tmp"
		fail 'real-netns evidence write'
	}
	chmod 0444 "$evidence_tmp" || fail 'real-netns evidence mode'
	mv -Tn -- "$evidence_tmp" "$evidence_path" || fail 'real-netns evidence publish'
	[ ! -e "$evidence_tmp" ] || fail 'real-netns evidence no-clobber publish'
fi

# Shipped identity is fixed; only this temporary test copy rewrites paths.
! grep -Fq '${CR6608_RESCUE_' "$GUARD_SOURCE" || \
	fail 'production path override remains'
network_rescue_block="$(sed -n "/^config interface 'wlanrescue'$/,/^$/p" "$NETWORK_CONFIG")"
printf '%s\n' "$network_rescue_block" | grep -Fq "option proto 'none'" || \
	fail 'rescue metadata is not addressless'
! printf '%s\n' "$network_rescue_block" | grep -Eq \
	"^[[:space:]]*option (device|ipaddr|netmask|ip6addr)[[:space:]]" || \
	fail 'rescue metadata can attach an address/device before nft isolation'
! grep -Fq "config device 'cr6608_rescue_dev'" "$NETWORK_CONFIG" || \
	fail 'obsolete rescue dummy is shipped'
grep -Fq "option auto '0'" "$NETWORK_CONFIG" || fail 'rescue is auto-started'
lan_zone_block="$(sed -n "/^config zone 'lan'$/,/^$/p" "$FIREWALL_CONFIG")"
printf '%s\n' "$lan_zone_block" | grep -Fq "list network 'lan'" || fail 'LAN zone lost LAN'
! printf '%s\n' "$lan_zone_block" | grep -Fq wlanrescue || fail 'rescue remains trusted LAN'
rescue_zone_block="$(sed -n "/^config zone 'cr6608_rescue_zone'$/,/^$/p" "$FIREWALL_CONFIG")"
printf '%s\n' "$rescue_zone_block" | grep -Fq "list network 'wlanrescue'" || fail 'rescue zone missing network'
printf '%s\n' "$rescue_zone_block" | grep -Fq "option cr6608_owner 'wlanrescue-v1'" || \
	fail 'rescue zone ownership marker missing'
for rescue_allow_section in cr6608_rescue_web cr6608_rescue_ping; do
	rescue_allow_block="$(sed -n "/^config rule '$rescue_allow_section'$/,/^$/p" "$FIREWALL_CONFIG")"
	printf '%s\n' "$rescue_allow_block" | grep -Fq "option mark '0x6608cafe/0xffffffff'" || \
		fail "$rescue_allow_section lacks exact AP packet mark"
done
grep -Fq "option rfc1918_filter '1'" "$UHTTPD_CONFIG" || fail 'global rebinding filter disabled'
grep -Fq 'procd_set_param command "$GUARD" monitor' "$INIT_SOURCE" || fail 'procd monitor absent'
grep -Fq 'procd_open_instance "$RESCUE_INSTANCE"' "$INIT_SOURCE" || \
	fail 'procd monitor lacks per-start instance identity'
grep -Fq 'rescue_instance_running "$RESCUE_INSTANCE"' "$INIT_SOURCE" || \
	fail 'startup accepts wildcard/stale procd ownership'
grep -Fq "PROCD_SERVICE='cr6608-rescue-guard'" "$INIT_SOURCE" && \
	grep -Fq ".instances['\$rescue_running_instance'].running" "$INIT_SOURCE" || \
	fail 'startup lacks exact direct procd ownership fallback'
grep -Fq 'rescue_process_start_ticks()' "$INIT_SOURCE" || \
	fail 'per-start instance lacks PID-reuse identity'
grep -Fq 'procd_set_param respawn 10 2 0' "$INIT_SOURCE" || fail 'lifelong bounded monitor respawn absent'
grep -Fq "MONITOR_INTERVAL='10'" "$GUARD_SOURCE" || fail 'monitor interval regression'
grep -Fq "MONITOR_RECOVERY_ATTEMPTS='3'" "$GUARD_SOURCE" || fail 'monitor recovery is unbounded'
grep -Fq '"$GUARD_BIN" health' "$GUARD_SOURCE" || fail 'monitor health is not isolated'
grep -Fq '"$GUARD_BIN" apply' "$GUARD_SOURCE" || fail 'monitor apply is not isolated'
grep -Fq 'run_stream_timed_seconds "$MONITOR_CHILD_TIMEOUT" "$GUARD_BIN" close' \
	"$GUARD_SOURCE" || fail 'monitor close bypasses transaction lock'
grep -Fq "monitor_health_rc\" -eq 75" "$GUARD_SOURCE" || fail 'monitor cannot defer to active transaction'
grep -Fq "verify_rules || fail_closed 'rules-health'" "$GUARD_SOURCE" || \
	fail 'monitor does not close on nft health loss'
grep -Fq 'build_wifi_elements' "$GUARD_SOURCE" || fail 'monitor does not recheck live APs'
grep -Fq "fail_closed 'no-live-ap'" "$GUARD_SOURCE" || fail 'no-AP state is not fail-closed'
sync_apply_line="$(grep -n -m1 '"$GUARD" start' "$INIT_SOURCE" | cut -d: -f1)"
procd_line="$(grep -n -m1 'procd_open_instance' "$INIT_SOURCE" | cut -d: -f1)"
procd_publish_line="$(grep -n -m1 'procd_close_instance' "$INIT_SOURCE" | cut -d: -f1)"
startup_quiesce_line="$(grep -n -m1 '"$GUARD" quiesce' "$INIT_SOURCE" | cut -d: -f1)"
[ "$startup_quiesce_line" -lt "$procd_line" ] || \
	fail 'start_service can construct procd before publishing quiesce'
[ "$procd_publish_line" -lt "$sync_apply_line" ] || \
	fail 'rescue endpoint can activate before procd instance publication'
grep -Fq 'service_started()' "$INIT_SOURCE" && \
	grep -Fq 'service_running' "$INIT_SOURCE" && \
	grep -Fq 'RESCUE_START_PREPARED' "$INIT_SOURCE" && \
	grep -Fq '"$GUARD" start' "$INIT_SOURCE" && \
	grep -Fq '"$GUARD" quiesce' "$INIT_SOURCE" || \
	fail 'procd publication/activation ordering can leave an unmonitored endpoint'
grep -Fq '"$GUARD" quiesce' "$INIT_SOURCE" || fail 'stop_service lacks operator quiesce'
grep -Fq 'service_stopped()' "$INIT_SOURCE" && \
	grep -Fq '"$GUARD" close' "$INIT_SOURCE" || fail 'post-procd stop does not re-prove CLOSED'
for rescue_hotplug in "$IFACE_HOTPLUG" "$NET_HOTPLUG"; do
	grep -Fq '"$INIT" running' "$rescue_hotplug" || fail 'hotplug ignores live monitor ownership'
	grep -Fq '"$INIT" reload' "$rescue_hotplug" || fail 'hotplug cannot refresh a running monitor'
	! grep -Fq '"$INIT" start' "$rescue_hotplug" || fail 'hotplug can replace the owned procd instance'
done
! grep -Fq '/usr/sbin/cr6608-rescue-guard apply' "$IFACE_HOTPLUG" || fail 'iface hotplug opens unmonitored'
! grep -Fq '/usr/sbin/cr6608-rescue-guard apply' "$NET_HOTPLUG" || fail 'net hotplug opens unmonitored'
grep -Fq '"$INIT" running' "$FIREWALL_INCLUDE" || fail 'firewall reload does not preserve monitor ownership'
grep -Fq '"$INIT" reload' "$FIREWALL_INCLUDE" || fail 'firewall reload bypasses the live monitor lifecycle'
! grep -Fq '"$INIT" start' "$FIREWALL_INCLUDE" || fail 'firewall callback can replace the owned procd instance'
grep -Fq '"$GUARD" close' "$FIREWALL_INCLUDE" || fail 'pre-enable firewall reload does not close'
grep -Fq '75) exit 0' "$FIREWALL_INCLUDE" || fail 'firewall reload treats lock contention as fatal'
reload_block="$(sed -n '/^reload_service() {$/,/^}$/p' "$INIT_SOURCE")"
printf '%s\n' "$reload_block" | grep -Fq '"$GUARD" start' || \
	fail 'reload cannot recover startup quiesce through a live monitor'
! printf '%s\n' "$reload_block" | grep -Fq '"$GUARD" apply' || \
	fail 'reload cannot clear a startup quiesce'
grep -Fq "option path '/usr/libexec/cr6608-rescue-firewall-include'" "$FIREWALL_CONFIG" || \
	fail 'firewall4 rescue include missing'
grep -Fq '/usr/sbin/cr6608-rescue-guard firewall-stop' "$FIREWALL_INIT_SOURCE" || \
	fail 'direct init/LuCI firewall stop bypasses rescue serialization'
grep -Fq '"$FW4_BIN" stop' "$GUARD_SOURCE" || fail 'firewall coordinator does not use fw4-own-table stop'
grep -Fq "RESCUE_INIT='/etc/init.d/cr6608-rescue-guard'" "$GUARD_SOURCE" || \
	fail 'firewall coordinator lacks fixed monitor lifecycle owner'
grep -Fq 'run_timed "$RESCUE_INIT" running' "$GUARD_SOURCE" || \
	fail 'firewall coordinator does not prove live monitor ownership'
grep -Fq 'run_timed "$NFT_BIN" list tables' "$GUARD_SOURCE" || \
	fail 'firewall coordinator trusts fw4 exit status without table proof'
grep -Fq 'CR6608_RESCUE_GUARD=CLOSED mode=firewall-stop monitor=stopped' \
	"$GUARD_SOURCE" || fail 'stopped monitor firewall Stop can reopen rescue'
grep -Fq 'QUIESCE_FILE="$STATE_DIR/operator-quiesced"' "$GUARD_SOURCE" || \
	fail 'operator quiesce state path missing'
grep -Fq 'publish_quiesce_state || fail_closed' "$GUARD_SOURCE" || \
	fail 'operator stop intent is not serialized before monitor kill'
grep -Fq 'clear_quiesce_state || fail_closed' "$GUARD_SOURCE" || \
	fail 'explicit successful start cannot clear operator quiesce'
quiesce_clear_line="$(grep -n -m1 'clear_quiesce_state || fail_closed' "$GUARD_SOURCE" | cut -d: -f1)"
final_rules_verify_line="$(grep -n 'verify_ruleset_snapshot || fail_closed' "$GUARD_SOURCE" | tail -n1 | cut -d: -f1)"
[ "$final_rules_verify_line" -lt "$quiesce_clear_line" ] || \
	fail 'start clears quiesce before activation is fully verified'
! grep -Eq '(^|[[:space:]])fw4[[:space:]]+flush([[:space:]]|$)' \
	"$FIREWALL_INIT_SOURCE" "$GUARD_SOURCE" || \
	fail 'firewall stop can flush unrelated rescue/security/QoS tables'

# Every external command and lock transition is watchdog bounded with helpers
# available in the BusyBox image.  No optional `timeout` package is assumed.
grep -Fq "SETSID_BIN='/usr/bin/setsid'" "$GUARD_SOURCE" || fail 'setsid helper identity'
grep -Fq "KILL_BIN='/bin/kill'" "$GUARD_SOURCE" || fail 'kill helper identity'
grep -Fq "PROC_ROOT='/proc'" "$GUARD_SOURCE" || fail 'proc identity root'
grep -Fq 'run_limit_process_identity' "$GUARD_SOURCE" || fail 'PID identity watchdog absent'
grep -Fq 'run_limit_signal_group TERM' "$GUARD_SOURCE" || fail 'watchdog TERM absent'
grep -Fq 'run_limit_signal_group KILL' "$GUARD_SOURCE" || fail 'watchdog KILL absent'
grep -Fq 'run_stdin_close_timed "$NFT_BIN" -f -' "$GUARD_SOURCE" || \
	fail 'deny-only rules are not streamed through the watchdog'
grep -Fq '"$FLOCK_BIN" -xn 9' "$GUARD_SOURCE" || fail 'nonblocking flock absent'
! grep -Fq '"$FLOCK_BIN" -x 9' "$GUARD_SOURCE" || fail 'blocking flock remains'
! grep -Fq 'TIMEOUT_BIN=' "$GUARD_SOURCE" || fail 'unsupported timeout dependency remains'
grep -Fq "exit 75" "$GUARD_SOURCE" || fail 'lock contention cannot defer without mutation'

apply_close_line="$(awk '
	/^case "\$mode" in$/ { in_mode=1; next }
	in_mode && /^\tstart\|apply\|firewall-stop\)$/ { in_apply=1; next }
	in_apply && /close_endpoint \|\| fail_closed/ { print NR; exit }
' "$GUARD_SOURCE")"
full_validation_line="$(grep -n -m1 '^validate_configuration$' "$GUARD_SOURCE" | cut -d: -f1)"
[ -n "$apply_close_line" ] && [ -n "$full_validation_line" ] && \
	[ "$apply_close_line" -lt "$full_validation_line" ] || \
	fail 'apply does not darken endpoint before full validation'
health_block="$(sed -n '/^if \[ "$mode" = health \]; then$/,/^fi$/p' "$GUARD_SOURCE")"
printf '%s\n' "$health_block" | grep -Fq 'load_route_owner' || fail 'health does not load route owner'
printf '%s\n' "$health_block" | grep -Fq 'build_wifi_elements' || fail 'health skips live APs'
printf '%s\n' "$health_block" | grep -Fq 'verify_rules' || fail 'health skips nft verification'
printf '%s\n' "$health_block" | grep -Fq 'verify_address' || fail 'health skips address verification'
printf '%s\n' "$health_block" | grep -Fq 'verify_route' || fail 'health skips route verification'
! printf '%s\n' "$health_block" | grep -Eq 'UCI_BIN|validate_configuration|uci_get' || \
	fail 'health performs a full UCI walk'
health_snapshot_line="$(printf '%s\n' "$health_block" | grep -n -m1 'verify_ruleset_snapshot' | cut -d: -f1)"
health_build_line="$(printf '%s\n' "$health_block" | grep -n -m1 'build_wifi_elements' | cut -d: -f1)"
[ "$health_snapshot_line" -lt "$health_build_line" ] || fail 'health snapshot is not checked before iw'
check_pre_snapshot_line="$(awk '
	/^if \[ "\$mode" = check \]; then$/ { in_check=1; next }
	in_check && /verify_ruleset_snapshot/ { print NR; exit }
' "$GUARD_SOURCE")"
check_validation_line="$(grep -n -m1 '^validate_configuration$' "$GUARD_SOURCE" | cut -d: -f1)"
check_post_snapshot_line="$(awk -v after="$check_validation_line" '
	NR > after && /verify_ruleset_snapshot/ { print NR; exit }
' "$GUARD_SOURCE")"
[ "$check_pre_snapshot_line" -lt "$check_validation_line" ] && \
	[ "$check_validation_line" -lt "$check_post_snapshot_line" ] || \
	fail 'full check does not bracket UCI validation with exact snapshots'

# Route ownership is an exact prefix/dev/src/scope/protocol tuple plus a
# root-only state file.  AP network disagreement is explicitly fail-closed.
grep -Fq "RESCUE_ROUTE_PROTO='221'" "$GUARD_SOURCE" || fail 'route protocol marker absent'
grep -Fq 'ROUTE_OWNER_FILE="$STATE_DIR/route-owner"' "$GUARD_SOURCE" || fail 'route owner state absent'
grep -Fq "chmod 0600 \"\$route_owner_tmp\"" "$GUARD_SOURCE" || fail 'route owner state permissions'
grep -Fq 'route_records_match_owner' "$GUARD_SOURCE" || fail 'exact route ownership check absent'
grep -Fq "fail_closed 'network:primary-ap-path-conflict'" "$GUARD_SOURCE" || \
	fail 'primary AP conflict is not fail-closed'
grep -Fq 'derive_primary_ap_path' "$GUARD_SOURCE" || fail 'primary AP path derivation absent'
owner_write_line="$(grep -n -m1 '^if ! write_route_owner; then$' "$GUARD_SOURCE" | cut -d: -f1)"
route_add_line="$(grep -n -m1 'route add "$RESCUE_CLIENT_SUBNET"' "$GUARD_SOURCE" | cut -d: -f1)"
[ "$route_add_line" -lt "$owner_write_line" ] || fail 'route state is published before route add succeeds'
grep -Fq "PRESERVE_ROUTE_ON_CLOSE='1'" "$GUARD_SOURCE" || \
	fail 'unpublished-route fail-closed preservation is absent'

# Neither close nor migration may interpret untrusted wlanrescue UCI through
# ifdown.  Migration reads only a validated bound device and two known IPs.
! grep -Fq 'ifdown wlanrescue' "$GUARD_SOURCE" || fail 'guard invokes unsafe ifdown'
! grep -Fq 'ifdown wlanrescue' "$MIGRATION" || fail 'migration invokes unsafe ifdown'
grep -Fq "LEGACY_RESCUE_IP='169.254.66.1'" "$MIGRATION" || fail 'legacy cleanup constant absent'
grep -Fq "RESCUE_IP='221.221.221.221'" "$MIGRATION" || fail 'current cleanup constant absent'
grep -Fq 'addr show dev "$old_rescue_device"' "$MIGRATION" || fail 'migration device-scoped address read absent'
! grep -Fq 'old_rescue_ip=' "$MIGRATION" || fail 'migration trusts arbitrary preserved ipaddr'
grep -Fq 'proto "$RESCUE_ROUTE_PROTO" dev "$old_rescue_device"' "$MIGRATION" || \
	fail 'migration exact protocol/device route lookup absent'
grep -Fq 'src "$RESCUE_IP" scope link proto "$RESCUE_ROUTE_PROTO"' "$MIGRATION" || \
	fail 'migration exact product route delete absent'
grep -Fq '"$RESCUE_GUARD" close' "$MIGRATION" || fail 'migration does not establish deny first'
! grep -Eq 'nft .*delete table|nft .*flush table' "$MIGRATION" || \
	fail 'migration removes rescue protection directly'

for legacy_target in "$NETWORK_CONFIG" "$FIREWALL_CONFIG" "$UHTTPD_CONFIG" \
	"$ROOT_DIR/files/usr/sbin/smartap-bootstrap" \
	"$ROOT_DIR/files/usr/sbin/cr6608-quicksettings-apply" \
	"$ROOT_DIR/files/www/cgi-bin/dashctl"; do
	! grep -Fq '169.254.66.1' "$legacy_target" || fail "legacy rescue address remains in $legacy_target"
	! grep -Eq "wlanrescue\.device=.*br-lan" "$legacy_target" || fail "bridge rescue writer remains in $legacy_target"
done
[ "$(grep -Fc '169.254.66.1' "$GUARD_SOURCE")" -eq 1 ] || \
	fail 'guard legacy address is not confined to its denial constant'
[ "$(grep -Fc '169.254.66.1' "$MIGRATION")" -eq 1 ] || fail 'legacy address has non-cleanup use'
! grep -Eq "wlanrescue\.device=.*br-lan" "$MIGRATION" || fail 'migration restores bridge rescue binding'
[ ! -e "$ROOT_DIR/files/etc/hotplug.d/iface/99-rescue221" ] || fail 'legacy rescue hotplug remains'
[ ! -e "$ROOT_DIR/files/etc/uci-defaults/99-rescue221" ] || fail 'legacy rescue defaults remain'

# BusyBox builds differ on fractional sleep support.  The watchdog grace
# helper must try the fast native path, fall back to ucode when present, and
# always retain a whole-second escape hatch without the old `! -x || cmd &&`
# precedence trap.
fast_grace_block="$(sed -n '/^run_limit_fast_grace() {/,/^}/p' "$GUARD_SOURCE")"
printf '%s\n' "$fast_grace_block" | grep -Fq 'sleep 0.1 9>&- 2>/dev/null && return 0' ||
	fail 'rescue guard fractional fast-grace probe absent'
printf '%s\n' "$fast_grace_block" | grep -Fq 'if [ -x /usr/bin/ucode ]; then' ||
	fail 'rescue guard does not explicitly guard the ucode fallback'
printf '%s\n' "$fast_grace_block" | grep -Fq "/usr/bin/ucode -e 'sleep(100)' 9>&- >/dev/null 2>&1 && return 0" ||
	fail 'rescue guard ucode millisecond fallback absent'
printf '%s\n' "$fast_grace_block" | grep -Fq 'sleep 1 9>&- 2>/dev/null || true' ||
	fail 'rescue guard whole-second fallback absent'
if printf '%s\n' "$fast_grace_block" | grep -Fq '[ ! -x /usr/bin/ucode ] ||'; then
	fail 'rescue guard ucode fallback has unsafe shell operator precedence'
fi

printf 'rescue_guard_contract=pass\n'
