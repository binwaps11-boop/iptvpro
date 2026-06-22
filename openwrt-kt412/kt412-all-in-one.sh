#!/bin/sh
# =====================================================================
# KT412 / Dongwon DW02-412H  —  ALL-IN-ONE: build custom firmware + flash
# Run on a Linux x86_64 PC WITH internet. Produces a CUSTOM factory.img
# (full KT412 config baked in) ready to flash via TFTP from U-Boot.
#
#   sh kt412-all-in-one.sh
#
# Your TFTP setup (edit if different):
#   Router (ipaddr)   = 192.168.0.3
#   Laptop/TFTP (srv) = 192.168.0.6
# =====================================================================
set -e

PROFILE="dongwon_dw02-412h-128m"      # 128M device. For 64M flash: -64m
VERSION="23.05.5"
ROUTER_IP="192.168.0.3"
TFTP_SRV_IP="192.168.0.6"

IB="openwrt-imagebuilder-${VERSION}-ath79-nand.Linux-x86_64"
W="$HOME/kt412-build"; rm -rf "$W"; mkdir -p "$W"; cd "$W"

echo "[1/5] dependencies"
sudo apt-get update
sudo apt-get install -y build-essential libncurses-dev zlib1g-dev gawk git \
  gettext libssl-dev xsltproc wget unzip python3 file

echo "[2/5] ImageBuilder"
wget -q --show-progress "https://downloads.openwrt.org/releases/${VERSION}/targets/ath79/nand/${IB}.tar.xz"
tar -xf "${IB}.tar.xz"

echo "[3/5] files/ overlay (KT412 design)"
F="$W/files"; mkdir -p "$F/etc/config" "$F/etc/sysctl.d" "$F/etc/uci-defaults" "$F/root"

cat > "$F/etc/config/network" <<'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'
config globals 'globals'
	option ula_prefix 'fd00:4120::/48'
	option packet_steering '1'
config interface 'lan'
	option type 'bridge'
	option ifname 'eth0.1'
	option proto 'static'
	option ipaddr '192.168.100.1'
	option netmask '255.255.255.0'
	option ip6assign '60'
config interface 'wan'
	option ifname 'eth0.2'
	option proto 'dhcp'
config interface 'wan6'
	option ifname 'eth0.2'
	option proto 'dhcpv6'
config switch
	option name 'switch0'
	option reset '1'
	option enable_vlan '1'
config switch_vlan
	option device 'switch0'
	option vlan '1'
	option ports '2 3 4 5 0t'
config switch_vlan
	option device 'switch0'
	option vlan '2'
	option ports '1 0t'
EOF

cat > "$F/etc/config/firewall" <<'EOF'
config defaults
	option syn_flood '1'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option flow_offloading '1'
config zone
	option name 'lan'
	list network 'lan'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'
config zone
	option name 'wan'
	list network 'wan'
	list network 'wan6'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option masq '1'
	option mtu_fix '1'
config forwarding
	option src 'lan'
	option dest 'wan'
EOF

cat > "$F/etc/config/dhcp" <<'EOF'
config dnsmasq
	option domainneeded '1'
	option boguspriv '1'
	option localise_queries '1'
	option rebind_protection '1'
	option local '/lan/'
	option domain 'lan'
	option expandhosts '1'
	option authoritative '1'
	option readethers '1'
	option leasefile '/tmp/dhcp.leases'
	option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
	option localservice '1'
	option cachesize '300'
config dhcp 'lan'
	option interface 'lan'
	option start '100'
	option limit '150'
	option leasetime '12h'
	option dhcpv4 'server'
	option ra 'server'
config dhcp 'wan'
	option interface 'wan'
	option ignore '1'
config odhcpd 'odhcpd'
	option maindhcp '0'
	option leasefile '/tmp/hosts/odhcpd'
	option leasetrigger '/usr/sbin/odhcpd-update'
EOF

cat > "$F/etc/config/mwan3" <<'EOF'
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

cat > "$F/etc/config/system" <<'EOF'
config system
	option hostname 'KT412'
	option timezone 'UTC'
	option log_size '64'
config timeserver 'ntp'
	option enabled '1'
	list server '0.openwrt.pool.ntp.org'
	list server '1.openwrt.pool.ntp.org'
EOF

cat > "$F/etc/sysctl.d/99-kt412.conf" <<'EOF'
net.netfilter.nf_conntrack_max=16384
net.netfilter.nf_conntrack_udp_timeout=60
net.core.default_qdisc=fq_codel
net.ipv4.tcp_fin_timeout=30
vm.min_free_kbytes=4096
EOF

cat > "$F/etc/uci-defaults/99-kt412" <<'EOF'
#!/bin/sh
add_cmd(){ uci -q batch <<-X
	set luci.$1=command
	set luci.$1.name='$2'
	set luci.$1.command='$3'
	set luci.$1.public='0'
X
}
add_cmd kt412_reconnect 'WAN: Reconnect' 'ifup wan'
add_cmd kt412_wifi 'Wi-Fi: Restart' 'wifi'
add_cmd kt412_mwan 'Multi-WAN: Status' 'mwan3 status'
add_cmd kt412_va 'Verify: All' '/root/verify-all.sh'
add_cmd kt412_vw 'Verify: WAN' '/root/verify-wan.sh'
add_cmd kt412_vp 'Verify: Ports' '/root/verify-ports.sh'
uci -q commit luci
chmod 0755 /root/verify-*.sh 2>/dev/null
uci -q set uhttpd.main.max_requests='3'; uci -q commit uhttpd
exit 0
EOF

cat > "$F/root/verify-all.sh" <<'EOF'
#!/bin/sh
echo "== BOARD =="; ubus call system board
echo "== RAM =="; free -m; echo "== DISK =="; df -h
echo "== IP =="; ip addr; ip route
echo "== SWITCH =="; swconfig dev switch0 show 2>/dev/null
echo "== WIFI =="; iwinfo 2>/dev/null; iw reg get 2>/dev/null
echo "== SERVICES =="; for s in network firewall dnsmasq uhttpd dropbear mwan3; do printf "%-9s: " "$s"; /etc/init.d/$s enabled 2>/dev/null && echo on || echo off; done
echo "== LOG =="; logread | tail -200
EOF
cat > "$F/root/verify-wan.sh" <<'EOF'
#!/bin/sh
for i in wan wan2; do echo "== $i =="; ubus call network.interface.$i status 2>/dev/null | grep -E '"up"|"proto"|"address"|"nexthop"'; done
ip route | grep default
for t in 1.1.1.1 8.8.8.8; do printf "%-9s: " "$t"; ping -c2 -W2 "$t" >/dev/null 2>&1 && echo OK || echo FAIL; done
mwan3 status 2>/dev/null
EOF
cat > "$F/root/verify-ports.sh" <<'EOF'
#!/bin/sh
swconfig dev switch0 show 2>/dev/null
cat /proc/net/dev
EOF
chmod 0755 "$F"/root/*.sh "$F/etc/uci-defaults/99-kt412"

echo "[4/5] build"
cd "$W/$IB"
# COMPLETE package list (base system + wifi + luci + KT412 extras).
# NEVER put a '#' on the same line as a package: it truncates 'opkg install'
# and produces a rootfs with NO /sbin/init (unbootable).
PKGS="base-files busybox procd procd-ujail procd-seccomp dropbear netifd fstools ubox ubus ubusd uci mtd ubi-utils uboot-envtools fwtool getrandom urngd urandom-seed logd opkg ca-bundle openwrt-keyring usign kmod-gpio-button-hotplug \
dnsmasq odhcpd-ipv6only odhcp6c firewall4 nftables ppp ppp-mod-pppoe kmod-pppoe \
kmod-ath9k kmod-ath10k-ct ath10k-firmware-qca988x-ct wpad-basic-mbedtls hostapd-common iw iwinfo wireless-regdb px5g-mbedtls libustream-mbedtls20201210 \
kmod-usb2 swconfig \
luci luci-ssl luci-app-firewall luci-app-opkg luci-mod-admin-full luci-proto-ppp luci-proto-ipv6 \
mwan3 luci-app-mwan3 luci-app-commands ip-full"
make image PROFILE="$PROFILE" PACKAGES="$PKGS" FILES="$F" EXTRA_IMAGE_NAME="kt412-custom"

echo "[5/5] collect"
OUT="$W/out"; mkdir -p "$OUT"
cp bin/targets/ath79/nand/*${PROFILE}*factory.img    "$OUT/kt412-custom-factory.img"
cp bin/targets/ath79/nand/*${PROFILE}*sysupgrade.bin "$OUT/kt412-custom-sysupgrade.bin"
# sanity: refuse to ship a rootfs without an init
unsquashfs -l "$W/$IB/build_dir/target-mips_24kc_musl/linux-ath79_nand/root.squashfs" 2>/dev/null \
  | grep -q 'squashfs-root/sbin/init' || { echo "FATAL: /sbin/init missing"; exit 1; }
cd "$OUT"; sha256sum kt412-custom-* | tee SHA256SUMS

cat <<FLASH

============================================================
 BUILD DONE -> $OUT
   kt412-custom-factory.img      (flash this via TFTP/U-Boot)
   kt412-custom-sysupgrade.bin   (only via 'sysupgrade' from a running system)

 UPLOAD / FLASH (copy factory.img into your TFTP server folder first):

   # on the PC: serve $OUT via TFTP, set PC IP = $TFTP_SRV_IP
   # then in U-Boot:
   setenv ipaddr $ROUTER_IP
   setenv serverip $TFTP_SRV_IP
   tftpboot 0x81000000 kt412-custom-factory.img
   nand erase 0x01000000 0x07000000
   nand write 0x81000000 0x01000000 \${filesize}
   reset

 After reset: router boots on 192.168.100.1  (LuCI there).
============================================================
FLASH
