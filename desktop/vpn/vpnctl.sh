#!/usr/bin/env bash
# ============================================================================
# vpnctl.sh — تحكّم VPN Egress إنتاجي للمشروع
#   - WireGuard أو OpenVPN حسب .env
#   - Split-tunnel: يوجّه ترافيك مستخدم التطبيق فقط عبر VPN (SSH/الإدارة تبقى)
#   - Kill Switch: لا تسريب من IP السيرفر إذا انقطع VPN
#   - Watchdog: فحص صحة + إعادة اتصال + fallback لدولة ثانية
# الأوامر:  up [CC] | down | status | health | run | test
# ============================================================================
set -uo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=/var/log/iptvpro-vpn.log

# تحميل الأسرار من .env
load_env() {
  set -a
  [ -f "$APP_DIR/.env" ] && . "$APP_DIR/.env"
  set +a
  : "${VPN_ENABLED:=true}"
  : "${VPN_TYPE:=wireguard}"
  : "${VPN_COUNTRY:=MX}"
  : "${VPN_FALLBACK_COUNTRY:=}"
  : "${VPN_CONF_DIR:=/etc/iptvpro/vpn}"
  : "${VPN_APP_USER:=www-data}"
  : "${VPN_KILL_SWITCH:=true}"
  : "${VPN_HEALTH_INTERVAL:=60}"
  : "${VPN_HEALTH_URL:=https://ifconfig.co/json}"
  : "${VPN_TEST_URL:=}"
  : "${VPN_TABLE:=51820}"
  : "${VPN_FWMARK:=0x51820}"
  : "${VPN_IFACE:=ipvpn}"
}

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG" >&2; }
as_app() { sudo -u "$VPN_APP_USER" "$@"; }
iface_up() { ip -o addr show "$VPN_IFACE" 2>/dev/null | grep -q 'inet '; }
detect_ip() { as_app curl -s4 -m 10 https://ifconfig.co/ip 2>/dev/null | tr -d '"\n '; }
detect_country() { as_app curl -s4 -m 10 https://ifconfig.co/country 2>/dev/null | tr -d '"\n'; }

# ----- رفع النفق حسب النوع -----
wg_up() {
  local cc="$1" src="$VPN_CONF_DIR/$cc.conf" dst="/etc/wireguard/$VPN_IFACE.conf"
  [ -f "$src" ] || { log "✗ لا يوجد ملف WireGuard: $src"; return 1; }
  command -v wg-quick >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard >/dev/null 2>&1
  mkdir -p /etc/wireguard
  sed '/^[[:space:]]*DNS[[:space:]]*=/d' "$src" > "$dst"
  grep -qi '^[[:space:]]*Table' "$dst" || sed -i '0,/^\[Interface\]/{s//\[Interface\]\nTable = off/}' "$dst"
  chmod 600 "$dst"
  wg-quick down "$VPN_IFACE" 2>/dev/null || true
  wg-quick up "$VPN_IFACE" 2>>"$LOG" || return 1
}
ovpn_up() {
  local cc="$1" src="$VPN_CONF_DIR/$cc.ovpn"
  [ -f "$src" ] || { log "✗ لا يوجد ملف OpenVPN: $src"; return 1; }
  command -v openvpn >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn >/dev/null 2>&1
  pkill -f "openvpn .*--dev $VPN_IFACE" 2>/dev/null || true; sleep 1
  openvpn --config "$src" --dev "$VPN_IFACE" --route-nopull --daemon \
          --log /var/log/iptvpro-vpn-ovpn.log --auth-nocache --connect-timeout 15 2>>"$LOG"
  for _ in $(seq 1 30); do iface_up && return 0; sleep 1; done
  return 1
}

# ----- التوجيه الانتقائي + Kill Switch -----
setup_routing() {
  ip route replace default dev "$VPN_IFACE" table "$VPN_TABLE" metric 50 2>>"$LOG"
  if [ "$VPN_KILL_SWITCH" = "true" ]; then
    # مسار blackhole احتياطي: إن سقط نفق VPN تُحجب الحزم (لا تعود لجدول main)
    ip route replace blackhole default table "$VPN_TABLE" metric 1000 2>>"$LOG"
  else
    ip route del blackhole default table "$VPN_TABLE" 2>/dev/null || true
  fi
  ip rule add fwmark "$VPN_FWMARK" table "$VPN_TABLE" 2>/dev/null || true
  iptables -t mangle -C OUTPUT -m owner --uid-owner "$VPN_APP_USER" -j MARK --set-mark "$VPN_FWMARK" 2>/dev/null \
    || iptables -t mangle -A OUTPUT -m owner --uid-owner "$VPN_APP_USER" -j MARK --set-mark "$VPN_FWMARK"
  sysctl -qw net.ipv4.conf.all.rp_filter=2 2>/dev/null || true
}
teardown_routing() {
  iptables -t mangle -D OUTPUT -m owner --uid-owner "$VPN_APP_USER" -j MARK --set-mark "$VPN_FWMARK" 2>/dev/null || true
  ip rule del fwmark "$VPN_FWMARK" table "$VPN_TABLE" 2>/dev/null || true
  ip route flush table "$VPN_TABLE" 2>/dev/null || true
}

up() {
  local cc="${1:-$VPN_COUNTRY}"
  if [ "$VPN_TYPE" = "openvpn" ]; then ovpn_up "$cc" || return 1; else wg_up "$cc" || return 1; fi
  iface_up || { log "✗ لم تحصل الواجهة على IP"; return 1; }
  setup_routing
  systemctl restart iptvpro 2>/dev/null || true
  log "✓ VPN مرفوع عبر $cc ($VPN_TYPE)"
}
down() {
  teardown_routing
  wg-quick down "$VPN_IFACE" 2>/dev/null || true
  pkill -f "openvpn .*--dev $VPN_IFACE" 2>/dev/null || true
  systemctl restart iptvpro 2>/dev/null || true
  log "VPN موقوف"
}

healthy() { iface_up && [ -n "$(detect_ip)" ]; }

up_with_fallback() {
  up "$VPN_COUNTRY" && healthy && return 0
  if [ -n "$VPN_FALLBACK_COUNTRY" ]; then
    log "⚠️ تعذّر $VPN_COUNTRY — تجربة الاحتياطي $VPN_FALLBACK_COUNTRY"
    up "$VPN_FALLBACK_COUNTRY" && healthy && return 0
  fi
  log "✗ فشل رفع VPN — Kill Switch يمنع التسريب"
  return 1
}

status_json() {
  local active=false ip="" country=""
  if iface_up; then active=true; ip="$(detect_ip)"; country="$(detect_country)"; fi
  printf '{"ok":true,"active":%s,"type":"%s","iface":"%s","country":"%s","ip":"%s","killSwitch":%s}\n' \
    "$active" "$VPN_TYPE" "$VPN_IFACE" "${country:-?}" "${ip:-?}" "$VPN_KILL_SWITCH"
}

run() {  # حلقة الـ watchdog (تُشغَّل من systemd)
  if [ "$VPN_ENABLED" != "true" ]; then log "VPN معطّل (VPN_ENABLED=false)"; exec sleep infinity; fi
  up_with_fallback || true
  while true; do
    sleep "$VPN_HEALTH_INTERVAL"
    if ! healthy; then log "فحص الصحة فشل — إعادة الاتصال"; up_with_fallback || true; fi
  done
}

load_env
case "${1:-status}" in
  up) up "${2:-}";;
  down) down;;
  status) status_json;;
  health) healthy && echo "healthy" || { echo "unhealthy"; exit 1; };;
  run) run;;
  test) exec bash "$APP_DIR/vpn/verify.sh";;
  *) echo "usage: vpnctl.sh up [CC]|down|status|health|run|test"; exit 1;;
esac
