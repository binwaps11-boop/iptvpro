#!/usr/bin/env bash
#
# vpn-apply.sh — مساعد جذري يُشغّله التطبيق (عبر sudo) لتفعيل/إيقاف توجيه المكسيك
# من داخل لوحة الإدارة مباشرةً (بدون SSH). يوجّه حركة مستخدم التطبيق فقط عبر النفق.
#
# يُستدعى:  sudo vpn-apply.sh up|down|status
# يقرأ إعداد WireGuard من:  <APP_DIR>/mx.conf  (يكتبه التطبيق)
# ويُخرج JSON ليقرأه التطبيق.
#
set -uo pipefail
ACTION="${1:-status}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_CONF="$APP_DIR/mx.conf"
IFACE=mx
WG_CONF="/etc/wireguard/${IFACE}.conf"
APP_USER="${SERVICE_USER:-www-data}"
TABLE=51820
MARK=0x51820

j(){ printf '%s\n' "$1"; }

apply_routes(){
  ip route replace default dev "$IFACE" table $TABLE
  ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
  ip rule add fwmark $MARK table $TABLE
  iptables -t mangle -D OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK 2>/dev/null || true
  iptables -t mangle -A OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK
  sysctl -qw net.ipv4.conf.all.rp_filter=2 2>/dev/null || true
}

clear_routes(){
  iptables -t mangle -D OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK 2>/dev/null || true
  ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
  ip route flush table $TABLE 2>/dev/null || true
}

status(){
  if wg show "$IFACE" >/dev/null 2>&1; then
    C="$(sudo -u "$APP_USER" curl -s4 -m 8 https://ifconfig.co/country 2>/dev/null | tr -d '"\n')"
    I="$(sudo -u "$APP_USER" curl -s4 -m 8 https://ifconfig.co/ip 2>/dev/null | tr -d '"\n')"
    j "{\"ok\":true,\"active\":true,\"country\":\"${C:-?}\",\"ip\":\"${I:-?}\"}"
  else
    j '{"ok":true,"active":false}'
  fi
}

case "$ACTION" in
  up)
    [ -f "$SRC_CONF" ] || { j '{"ok":false,"error":"لا يوجد إعداد VPN"}'; exit 0; }
    command -v wg-quick >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard >/dev/null 2>&1
    mkdir -p /etc/wireguard
    sed '/^[[:space:]]*DNS[[:space:]]*=/d' "$SRC_CONF" > "$WG_CONF"
    grep -qi '^[[:space:]]*Table' "$WG_CONF" || sed -i '0,/^\[Interface\]/{s//\[Interface\]\nTable = off/}' "$WG_CONF"
    chmod 600 "$WG_CONF"
    wg-quick down "$IFACE" 2>/dev/null || true
    if ! wg-quick up "$IFACE" 2>/tmp/wgerr; then
      j "{\"ok\":false,\"error\":\"$(tr -d '"\n' </tmp/wgerr | head -c 180)\"}"; exit 0
    fi
    apply_routes
    systemctl restart iptvpro 2>/dev/null || true
    sleep 1
    status
    ;;
  down)
    clear_routes
    wg-quick down "$IFACE" 2>/dev/null || true
    systemctl restart iptvpro 2>/dev/null || true
    j '{"ok":true,"active":false}'
    ;;
  status) status;;
  *) j '{"ok":false,"error":"bad action"}';;
esac
