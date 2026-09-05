#!/usr/bin/env bash
# يثبّت ويُفعّل خدمة VPN Egress (تعمل بعد الإقلاع تلقائياً).
#   sudo bash vpn/install-vpn.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "شغّله بـ sudo"; exit 1; }
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "▶ تثبيت الأدوات (wireguard + openvpn + iproute2 + iptables)"
DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard openvpn iproute2 iptables curl >/dev/null 2>&1 || true

# تجهيز .env إن لم يوجد
[ -f "$APP_DIR/.env" ] || { cp "$APP_DIR/.env.example" "$APP_DIR/.env"; echo "▶ أُنشئ .env — عدّله ثم أعد التشغيل"; }

# مجلد ملفات إعداد الـ VPN (هنا تضع MX.conf)
CONF_DIR="$(grep -E '^VPN_CONF_DIR=' "$APP_DIR/.env" | cut -d= -f2)"; CONF_DIR="${CONF_DIR:-/etc/iptvpro/vpn}"
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
echo "▶ ضع ملف الـ WireGuard المكسيكي في:  $CONF_DIR/MX.conf"

chmod +x "$APP_DIR/vpn/vpnctl.sh" "$APP_DIR/vpn/verify.sh" 2>/dev/null || true

echo "▶ تثبيت خدمة systemd"
sed "s#__APP_DIR__#$APP_DIR#g" "$APP_DIR/vpn/iptvpro-vpn.service" > /etc/systemd/system/iptvpro-vpn.service
systemctl daemon-reload
systemctl enable iptvpro-vpn >/dev/null 2>&1 || true

echo
echo "✅ تم التثبيت. الخطوات:"
echo "   1) ضع ملف WireGuard المكسيكي:   nano $CONF_DIR/MX.conf"
echo "   2) عدّل الأسرار إن لزم:          nano $APP_DIR/.env"
echo "   3) شغّل الخدمة:                  systemctl restart iptvpro-vpn"
echo "   4) افحص النتيجة:                bash $APP_DIR/vpn/verify.sh"
