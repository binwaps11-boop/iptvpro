#!/bin/sh
# =====================================================================
# KT412 / Dongwon DW02-412H  —  FULL setup script (run on the device)
# Run this AFTER the device boots a WORKING OpenWrt (e.g. recovered via
# initramfs + official sysupgrade). It turns plain OpenWrt into the full
# light KT412 setup: Management 192.168.100.1, NAT+flow-offload, mwan3
# (ECMP/failover, health 1.1.1.1/8.8.8.8), light tuning, real command
# buttons, and /root/verify-*.sh. Idempotent & safe (keep serial open).
# =====================================================================
set -u
log(){ echo "[KT412] $*"; }

# 0) sanity check: correct board
BOARD="$(ubus call system board 2>/dev/null | grep -o 'dw02-412h[^\"]*' | head -1)"
log "board = ${BOARD:-UNKNOWN}"
case "$BOARD" in
  dw02-412h*) : ;;
  *) log "WARNING: this is not a DW02-412H. Aborting for safety."; exit 1 ;;
esac

# 1) install light packages IF internet is reachable on WAN
if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
  log "internet OK -> opkg update + install light packages"
  opkg update >/dev/null 2>&1
  opkg install luci luci-proto-ppp ppp-mod-pppoe luci-app-commands \
               mwan3 luci-app-mwan3 wpad-basic-mbedtls iwinfo \
               kmod-ath9k kmod-ath10k-ct ath10k-firmware-qca988x-ct \
    || log "WARN: some packages failed (continuing)"
else
  log "no internet on WAN -> skipping opkg (set up WAN, then re-run to add packages)"
fi

# 2) NETWORK — management IP + packet steering (swconfig layout already correct)
uci -q set network.lan.ipaddr='192.168.100.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q set network.@globals[0].packet_steering='1'
uci -q get network.wan >/dev/null 2>&1 || {
  uci set network.wan='interface'; uci set network.wan.ifname='eth0.2'; uci set network.wan.proto='dhcp'; }

# 3) FIREWALL — NAT + software flow offload + MSS clamp (helps PPPoE)
uci -q set firewall.@defaults[0].flow_offloading='1'
i=0
while uci -q get firewall.@zone[$i] >/dev/null 2>&1; do
  if [ "$(uci -q get firewall.@zone[$i].name)" = "wan" ]; then
    uci set firewall.@zone[$i].masq='1'
    uci set firewall.@zone[$i].mtu_fix='1'
  fi
  i=$((i+1))
done

# 4) dnsmasq — small cache for 128MB RAM
uci -q set dhcp.@dnsmasq[0].cachesize='300'

# 5) SYSTEM — hostname + bounded logs
uci -q set system.@system[0].hostname='KT412'
uci -q set system.@system[0].log_size='64'

# 6) SYSCTL tuning (light, 128MB-friendly)
cat > /etc/sysctl.d/99-kt412.conf <<'EOF'
net.netfilter.nf_conntrack_max=16384
net.netfilter.nf_conntrack_udp_timeout=60
net.core.default_qdisc=fq_codel
net.ipv4.tcp_fin_timeout=30
vm.min_free_kbytes=4096
EOF
sysctl -p /etc/sysctl.d/99-kt412.conf >/dev/null 2>&1

# 7) mwan3 — ECMP / Failover / Health (only if installed)
if command -v mwan3 >/dev/null 2>&1 || opkg list-installed 2>/dev/null | grep -q '^mwan3 '; then
  log "writing mwan3 template (ECMP/failover, health 1.1.1.1/8.8.8.8)"
  cat > /etc/config/mwan3 <<'EOF'
config globals 'globals'
	option mmx_mask '0x3F00'

config interface 'wan'
	option enabled '1'
	list track_ip '1.1.1.1'
	list track_ip '8.8.8.8'
	option family 'ipv4'
	option reliability '1'
	option count '1'
	option timeout '4'
	option interval '10'
	option down '3'
	option up '3'

config interface 'wan2'
	option enabled '0'
	list track_ip '1.1.1.1'
	list track_ip '8.8.8.8'
	option family 'ipv4'
	option reliability '1'
	option count '1'
	option timeout '4'
	option interval '10'
	option down '3'
	option up '3'

config member 'wan_m1_w3'
	option interface 'wan'
	option metric '1'
	option weight '3'
config member 'wan_m2_w1'
	option interface 'wan'
	option metric '2'
	option weight '1'
config member 'wan2_m1_w2'
	option interface 'wan2'
	option metric '1'
	option weight '2'
config member 'wan2_m2_w1'
	option interface 'wan2'
	option metric '2'
	option weight '1'

config policy 'balanced'
	list use_member 'wan_m1_w3'
	list use_member 'wan2_m1_w2'
	option last_resort 'unreachable'
config policy 'failover'
	list use_member 'wan_m1_w3'
	list use_member 'wan2_m2_w1'
	option last_resort 'unreachable'
config policy 'wan_only'
	list use_member 'wan_m1_w3'
	option last_resort 'unreachable'

config rule 'default_rule'
	option dest_ip '0.0.0.0/0'
	option use_policy 'wan_only'
	option family 'ipv4'
EOF
fi

# 8) Real working buttons via luci-app-commands (if installed)
if opkg list-installed 2>/dev/null | grep -q '^luci-app-commands '; then
  add_cmd(){ uci -q batch <<-EOF
		set luci.$1=command
		set luci.$1.name='$2'
		set luci.$1.command='$3'
		set luci.$1.public='0'
	EOF
  }
  add_cmd kt412_reconnect   'WAN: Reconnect'    'ifup wan'
  add_cmd kt412_wifi        'Wi-Fi: Restart'    'wifi'
  add_cmd kt412_mwan        'Multi-WAN: Status' 'mwan3 status'
  add_cmd kt412_verifyall   'Verify: All'       '/root/verify-all.sh'
  add_cmd kt412_verifyports 'Verify: Ports'     '/root/verify-ports.sh'
  add_cmd kt412_verifywan   'Verify: WAN'       '/root/verify-wan.sh'
  add_cmd kt412_verifysvc   'Verify: Services'  '/root/verify-services.sh'
  add_cmd kt412_verifywifi  'Verify: Wi-Fi'     '/root/verify-wifi.sh'
fi

# 9) verify scripts
cat > /root/verify-all.sh <<'EOF'
#!/bin/sh
echo "== BOARD =="; ubus call system board
echo "== RELEASE =="; cat /etc/openwrt_release
echo "== RAM =="; free -m
echo "== STORAGE =="; df -h
echo "== IP =="; ip addr; ip route
echo "== SWITCH =="; swconfig dev switch0 show 2>/dev/null
echo "== WIFI =="; iwinfo 2>/dev/null; iw reg get 2>/dev/null
echo "== SERVICES =="
for s in network firewall dnsmasq uhttpd dropbear odhcpd mwan3; do
  printf "%-9s: " "$s"; /etc/init.d/$s enabled 2>/dev/null && echo enabled || echo off
done
echo "== LOG TAIL =="; logread | tail -200
EOF
cat > /root/verify-ports.sh <<'EOF'
#!/bin/sh
echo "== switch0 =="; swconfig dev switch0 show 2>/dev/null
echo "== /proc/net/dev =="; cat /proc/net/dev
echo "== vlan map =="; uci show network | grep -i 'switch_vlan\|ifname\|ports'
EOF
cat > /root/verify-wan.sh <<'EOF'
#!/bin/sh
for i in wan wan2; do
  echo "== $i =="; ubus call network.interface.$i status 2>/dev/null | grep -E '"up"|"proto"|"address"|"nexthop"'
done
echo "== routes =="; ip route | grep default
for t in 1.1.1.1 8.8.8.8; do printf "%-9s: " "$t"; ping -c2 -W2 "$t" >/dev/null 2>&1 && echo OK || echo FAIL; done
mwan3 status 2>/dev/null
EOF
cat > /root/verify-services.sh <<'EOF'
#!/bin/sh
for s in network firewall dnsmasq uhttpd dropbear odhcpd mwan3; do
  echo "== $s =="; /etc/init.d/$s enabled 2>/dev/null && echo boot:on || echo boot:off
  /etc/init.d/$s status 2>/dev/null
done
[ -e /dev/watchdog ] && echo "watchdog: present" || echo "watchdog: none"
logread | grep -iE 'error|fail|panic|oom|reset' | tail -30
EOF
cat > /root/verify-wifi.sh <<'EOF'
#!/bin/sh
wifi status 2>/dev/null; iw reg get 2>/dev/null
for d in $(iwinfo 2>/dev/null | grep -oE '^[a-z0-9]+' | sort -u); do
  echo "== $d =="; iwinfo "$d" info 2>/dev/null
done
cat /etc/config/wireless 2>/dev/null
EOF
chmod 0755 /root/verify-*.sh

# 10) uhttpd light
uci -q set uhttpd.main.max_requests='3'
uci -q set uhttpd.main.max_connections='30'

# 11) COMMIT + APPLY
uci commit
log "reloading services (LAN becomes 192.168.100.1) ..."
/etc/init.d/dnsmasq reload 2>/dev/null
/etc/init.d/firewall reload 2>/dev/null
command -v mwan3 >/dev/null 2>&1 && /etc/init.d/mwan3 enable 2>/dev/null
/etc/init.d/network reload
log "DONE. LuCI -> http://192.168.100.1   | run /root/verify-all.sh to check"
