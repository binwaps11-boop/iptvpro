#!/bin/sh
# quick-setup.sh — REAL quick modes with SAFE APPLY + auto-rollback.
# Every network change is protected: if you lose access, the router auto-restores
# the previous config and reboots after the timeout. You KEEP a change only by
# running:  /root/quick-setup.sh confirm
#
# Usage:
#   /root/quick-setup.sh                      # show menu
#   /root/quick-setup.sh router
#   /root/quick-setup.sh ap <mgmt_ip> <gateway>
#   /root/quick-setup.sh wan-dhcp
#   /root/quick-setup.sh wan-static <ip> <mask> <gw> <dns>
#   /root/quick-setup.sh pppoe <user> <pass> [mtu]
#   /root/quick-setup.sh vlan <id> <lanX[,lanY...]>     # access VLAN + DHCP
#   /root/quick-setup.sh mesh <meshid> <2g|5g> [key]
#   /root/quick-setup.sh backup                         # -> /tmp/qs-backup.tar.gz
#   /root/quick-setup.sh restore <file>
#   /root/quick-setup.sh confirm | revert | status
TIMEOUT=120
RB=/tmp/qs-rollback
FLAG=/tmp/qs-confirm

menu(){ cat <<EOF
==== CR6606 Quick Setup (safe apply) ====
  router                         Normal NAT router (LAN 192.168.100.1, WAN dhcp)
  ap <ip> <gw>                   AP / Bridge mode (dumb AP)
  wan-dhcp                       WAN = DHCP
  wan-static <ip> <mask> <gw> <dns>
  pppoe <user> <pass> [mtu]      Broadband PPPoE (+MSS clamp)
  vlan <id> <lan1,lan2>          Create access VLAN + DHCP + zone
  mesh <id> <2g|5g> [key]        802.11s mesh (if driver supports)
  backup | restore <file>
  confirm                        KEEP last change (cancels rollback)
  revert                         restore previous config now
  status
After any change: test your access, then run:  /root/quick-setup.sh confirm
(otherwise it auto-reverts in ${TIMEOUT}s)
EOF
}

arm(){
  rm -rf "$RB"; mkdir -p "$RB"; rm -f "$FLAG"
  cp /etc/config/network "$RB/" 2>/dev/null
  cp /etc/config/wireless "$RB/" 2>/dev/null
  cp /etc/config/firewall "$RB/" 2>/dev/null
  cp /etc/config/dhcp "$RB/" 2>/dev/null
  # background watcher
  ( sleep "$TIMEOUT"
    [ -f "$FLAG" ] && exit 0
    logger -t quick-setup "no confirm -> rolling back + reboot"
    cp "$RB"/* /etc/config/ 2>/dev/null
    sync; reboot ) &
  echo $! > "$RB/pid"
  echo ">> SAFE APPLY armed. You have ${TIMEOUT}s. If all OK run: /root/quick-setup.sh confirm"
}
apply(){ /etc/init.d/network reload; /etc/init.d/dnsmasq restart 2>/dev/null; /etc/init.d/firewall restart 2>/dev/null; }
confirm(){ touch "$FLAG"; [ -f "$RB/pid" ] && kill "$(cat $RB/pid)" 2>/dev/null; echo "KEPT. rollback cancelled."; }
revert(){ [ -d "$RB" ] && cp "$RB"/* /etc/config/ 2>/dev/null; apply; echo "reverted previous config."; }

case "$1" in
 router)
   arm
   uci -q set network.lan.proto='static'; uci -q set network.lan.ipaddr='192.168.100.1'
   uci -q set network.lan.netmask='255.255.255.0'; uci -q delete network.lan.gateway
   uci -q set network.wan.proto='dhcp'; uci -q delete network.wan.username; uci -q delete network.wan.password
   uci -q set dhcp.lan.ignore='0'; uci commit; /etc/init.d/firewall enable; apply ;;
 ap)
   [ -n "$3" ] || { echo "usage: ap <mgmt_ip> <gateway>"; exit 1; }; arm
   uci -q add_list network.@device[0].ports='wan' 2>/dev/null
   uci -q set network.lan.proto='static'; uci -q set network.lan.ipaddr="$2"
   uci -q set network.lan.netmask='255.255.255.0'; uci -q set network.lan.gateway="$3"; uci -q set network.lan.dns="$3"
   uci -q delete network.wan; uci -q delete network.wan6
   uci -q set dhcp.lan.ignore='1'; uci commit
   /etc/init.d/firewall stop; /etc/init.d/firewall disable; apply ;;
 wan-dhcp)
   arm; uci -q set network.wan.proto='dhcp'
   for k in username password ipaddr netmask gateway; do uci -q delete network.wan.$k; done
   uci commit network; apply ;;
 wan-static)
   [ -n "$5" ] || { echo "usage: wan-static <ip> <mask> <gw> <dns>"; exit 1; }; arm
   uci -q set network.wan.proto='static'; uci -q set network.wan.ipaddr="$2"
   uci -q set network.wan.netmask="$3"; uci -q set network.wan.gateway="$4"; uci -q set network.wan.dns="$5"
   uci commit network; apply ;;
 pppoe)
   [ -n "$3" ] || { echo "usage: pppoe <user> <pass> [mtu]"; exit 1; }; arm
   uci -q set network.wan.proto='pppoe'; uci -q set network.wan.username="$2"; uci -q set network.wan.password="$3"
   uci -q set network.wan.mtu="${4:-1492}"; uci -q set network.wan.peerdns='1'
   # MSS clamp for PPPoE
   uci -q set firewall.@zone[1].mtu_fix='1'
   uci commit; apply ;;
 vlan)
   [ -n "$3" ] || { echo "usage: vlan <id> <lan1,lan2>"; exit 1; }; arm
   id="$2"; ports=$(echo "$3" | tr ',' ' ')
   sec=$(uci add network bridge-vlan); uci -q set network.$sec.device='br-lan'; uci -q set network.$sec.vlan="$id"
   for p in $ports; do uci -q add_list network.$sec.ports="${p}:u*"; done
   uci -q set network.vlan$id=interface; uci -q set network.vlan$id.device="br-lan.$id"
   uci -q set network.vlan$id.proto='static'; uci -q set network.vlan$id.ipaddr="192.168.$id.1"; uci -q set network.vlan$id.netmask='255.255.255.0'
   uci -q set dhcp.vlan$id=dhcp; uci -q set dhcp.vlan$id.interface="vlan$id"; uci -q set dhcp.vlan$id.start='100'; uci -q set dhcp.vlan$id.limit='150'; uci -q set dhcp.vlan$id.leasetime='12h'
   z=$(uci add firewall zone); uci -q set firewall.$z.name="vlan$id"; uci -q add_list firewall.$z.network="vlan$id"
   uci -q set firewall.$z.input='REJECT'; uci -q set firewall.$z.output='ACCEPT'; uci -q set firewall.$z.forward='REJECT'
   f=$(uci add firewall forwarding); uci -q set firewall.$f.src="vlan$id"; uci -q set firewall.$f.dest='wan'
   uci commit; apply
   echo "VLAN $id on ports: $ports  (subnet 192.168.$id.1). Verify: bridge vlan show" ;;
 mesh)
   [ -n "$3" ] || { echo "usage: mesh <meshid> <2g|5g> [key]"; exit 1; }; arm
   case "$3" in 2g) r=radio0;; 5g) r=radio1;; *) echo "band must be 2g|5g"; exit 1;; esac
   m=$(uci add wireless wifi-iface); uci -q set wireless.$m.device="$r"; uci -q set wireless.$m.mode='mesh'
   uci -q set wireless.$m.mesh_id="$2"; uci -q set wireless.$m.network='lan'; uci -q set wireless.$m.disabled='0'
   if [ -n "$4" ]; then uci -q set wireless.$m.encryption='sae'; uci -q set wireless.$m.key="$4"; else uci -q set wireless.$m.encryption='none'; fi
   uci commit wireless; wifi reload
   echo "mesh '$2' on $r. peers: iw dev | grep -A2 mesh ; then 'iw dev <mesh-if> station dump'"
   echo "NOTE: encrypted mesh (sae) needs a wpad build with mesh support; if peers don't"
   echo "      link, install wpad-mesh-mbedtls and retry." ;;
 backup) sysupgrade -b /tmp/qs-backup.tar.gz; echo "saved /tmp/qs-backup.tar.gz" ;;
 restore) [ -f "$2" ] || { echo "usage: restore <file>"; exit 1; }; sysupgrade -r "$2"; echo "restored $2 (reboot to apply)" ;;
 confirm) confirm ;;
 revert)  revert ;;
 status)
   echo "WAN:"; ifstatus wan 2>/dev/null | grep -E '"up"|"proto"|"address"'
   echo "rollback armed:"; [ -f "$RB/pid" ] && kill -0 "$(cat $RB/pid)" 2>/dev/null && echo "  YES (run confirm!)" || echo "  no" ;;
 *) menu ;;
esac
