#!/bin/sh
# KT412 — Quick Settings buttons. Run once on the device. Adds real one-click
# buttons under  LuCI -> System -> Custom Commands.  Needs luci-app-commands.
add() {
	uci -q batch <<-EOF
		set luci.$1=command
		set luci.$1.name='$2'
		set luci.$1.command='$3'
		set luci.$1.public='0'
	EOF
}
addarg() { add "$1" "$2" "$3"; uci -q set luci.$1.legacy='1'; }

# --- Dashboard / status ---
add qs_status   'Dashboard: full status' 'ubus call system board; echo; free -m; echo; df -h /; echo; iwinfo | grep -iE "ESSID|Tx-Power"; echo; mwan3 status 2>/dev/null'
add qs_ports    'Ports: show (VLAN+link)' 'swconfig dev switch0 show'
add qs_traffic  'Traffic: per interface'  'cat /proc/net/dev'

# --- WAN / Broadband (buttons that actually change config) ---
add    qs_wan_dhcp    'WAN: DHCP'              'uci set network.wan.proto=dhcp; uci -q delete network.wan.username; uci -q delete network.wan.password; uci commit network; ifup wan; echo "WAN -> DHCP OK"'
addarg qs_wan_pppoe   'WAN: PPPoE  (user pass)' 'set -- $1; uci set network.wan.proto=pppoe; uci set network.wan.username="$1"; uci set network.wan.password="$2"; uci set network.wan.ipv6=auto; uci commit network; ifup wan; echo "WAN -> PPPoE OK ($1)"'
addarg qs_wan_static  'WAN: Static (ip mask gw dns)' 'set -- $1; uci set network.wan.proto=static; uci set network.wan.ipaddr="$1"; uci set network.wan.netmask="$2"; uci set network.wan.gateway="$3"; uci set network.wan.dns="$4"; uci commit network; ifup wan; echo "WAN -> Static OK"'
add    qs_wan_reco    'WAN: Reconnect'         'ifup wan; echo reconnected'

# --- Wi-Fi ---
add qs_wifi_restart 'Wi-Fi: Restart'   'wifi; echo wifi-restarted'
add qs_wifi_power   'Wi-Fi: real power' 'iwinfo | grep -iE "ESSID|Tx-Power"'

# --- QoS / SQM ---
addarg qs_sqm_on 'SQM: ON  (down up kbit)' 'set -- $1; uci set sqm.wan.download="$1"; uci set sqm.wan.upload="$2"; uci set sqm.wan.enabled=1; uci commit sqm; /etc/init.d/sqm enable; /etc/init.d/sqm restart; echo "SQM ON $1/$2 kbit"'
add    qs_sqm_off 'SQM: OFF'              '/etc/init.d/sqm stop; /etc/init.d/sqm disable; echo "SQM OFF"'

# --- Services / system ---
add qs_net_restart 'Network: Restart'  '/etc/init.d/network restart; echo net-restarted'
add qs_fw_restart  'Firewall: Restart' '/etc/init.d/firewall restart; echo fw-restarted'
add qs_reboot      'System: Reboot'    'reboot'

# --- Verify scripts (if present) ---
add qs_verify_all  'Verify: All'   '/root/verify-all.sh'
add qs_verify_wan  'Verify: WAN'   '/root/verify-wan.sh'
add qs_verify_port 'Verify: Ports' '/root/verify-ports.sh'

uci -q commit luci
echo "DONE. Open LuCI -> System -> Custom Commands. (refresh the page)"
echo "Buttons with (args) accept input, e.g. PPPoE: type  myuser mypass  then Run."
