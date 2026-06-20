#!/usr/bin/env bash
#
# vpngate-apply.sh — VPN مجاني مدمج (VPN Gate) باختيار الدولة، يُدار من اللوحة.
# يختار خادماً مجانياً في الدولة المطلوبة (مثل المكسيك)، يتصل عبر OpenVPN،
# ويوجّه حركة التطبيق فقط عبره (لا يكسر SSH/الإدارة).
#
# يُستدعى عبر sudo:  vpngate-apply.sh up <CC> | down | status
#   <CC> = رمز الدولة بحرفين (MX للمكسيك، US، DE ...). الافتراضي MX.
#
set -uo pipefail
ACTION="${1:-status}"
COUNTRY="${2:-MX}"
APP_USER="${SERVICE_USER:-www-data}"
DEV=tunvpn
TABLE=51820
MARK=0x51820
CONF=/etc/openvpn/vpngate.conf
LOG=/var/log/vpngate.log
j(){ printf '%s\n' "$1"; }

ensure(){ command -v openvpn >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn curl >/dev/null 2>&1; }

routes_up(){
  ip route replace default dev "$DEV" table $TABLE
  ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
  ip rule add fwmark $MARK table $TABLE
  iptables -t mangle -D OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK 2>/dev/null || true
  iptables -t mangle -A OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK
  sysctl -qw net.ipv4.conf.all.rp_filter=2 2>/dev/null || true
}
routes_down(){
  iptables -t mangle -D OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK 2>/dev/null || true
  ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
  ip route flush table $TABLE 2>/dev/null || true
}
status(){
  if ip addr show "$DEV" 2>/dev/null | grep -q 'inet '; then
    C="$(sudo -u "$APP_USER" curl -s4 -m 8 https://ifconfig.co/country 2>/dev/null | tr -d '"\n')"
    I="$(sudo -u "$APP_USER" curl -s4 -m 8 https://ifconfig.co/ip 2>/dev/null | tr -d '"\n')"
    j "{\"ok\":true,\"active\":true,\"country\":\"${C:-?}\",\"ip\":\"${I:-?}\"}"
  else
    j '{"ok":true,"active":false}'
  fi
}

case "$ACTION" in
  up)
    [[ "$COUNTRY" =~ ^[A-Za-z]{2}$ ]] || { j '{"ok":false,"error":"رمز دولة غير صالح"}'; exit 0; }
    COUNTRY="${COUNTRY^^}"
    ensure
    CSV="$(curl -s4 -m 30 'https://www.vpngate.net/api/iphone/' 2>/dev/null)"
    [ -n "$CSV" ] || { j '{"ok":false,"error":"تعذّر جلب قائمة VPN Gate"}'; exit 0; }
    # الأعمدة: HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,...,Base64Config(الأخير)
    ROW="$(printf '%s\n' "$CSV" | awk -F, -v c="$COUNTRY" 'NF>14 && $7==c {print $5","$0}' | sort -t, -k1 -nr | head -1 | cut -d, -f2-)"
    [ -n "$ROW" ] || { j "{\"ok\":false,\"error\":\"لا يوجد خادم VPN مجاني في $COUNTRY الآن — جرّب لاحقاً أو دولة أخرى\"}"; exit 0; }
    printf '%s' "$ROW" | awk -F, '{print $NF}' | base64 -d > "$CONF" 2>/dev/null
    grep -q '^remote ' "$CONF" || { j '{"ok":false,"error":"إعداد OpenVPN غير صالح"}'; exit 0; }
    pkill -f "openvpn --config $CONF" 2>/dev/null || true
    sleep 1
    # route-nopull: لا يغيّر المسار الافتراضي (يحمي SSH)؛ نوجّه التطبيق فقط يدوياً
    openvpn --config "$CONF" --dev "$DEV" --route-nopull --daemon --log "$LOG" \
            --connect-timeout 15 --connect-retry-max 2 --resolv-retry 20 --auth-nocache 2>/dev/null
    for i in $(seq 1 35); do ip addr show "$DEV" 2>/dev/null | grep -q 'inet ' && break; sleep 1; done
    if ip addr show "$DEV" 2>/dev/null | grep -q 'inet '; then
      routes_up
      systemctl restart iptvpro 2>/dev/null || true
      sleep 1
      status
    else
      pkill -f "openvpn --config $CONF" 2>/dev/null || true
      j "{\"ok\":false,\"error\":\"تعذّر الاتصال بخادم $COUNTRY (جرّب مرة أخرى)\"}"
    fi
    ;;
  down)
    routes_down
    pkill -f "openvpn --config $CONF" 2>/dev/null || true
    systemctl restart iptvpro 2>/dev/null || true
    j '{"ok":true,"active":false}'
    ;;
  status) status;;
  *) j '{"ok":false,"error":"bad action"}';;
esac
