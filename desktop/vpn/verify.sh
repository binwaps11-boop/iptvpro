#!/usr/bin/env bash
# ============================================================================
# verify.sh — يفحص فعلياً أن VPN متصل ويوجّه الترافيك، ويطبع النتائج.
#   sudo bash vpn/verify.sh
# ============================================================================
set -uo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; [ -f "$APP_DIR/.env" ] && . "$APP_DIR/.env"; set +a
: "${VPN_APP_USER:=www-data}"; : "${VPN_IFACE:=ipvpn}"; : "${VPN_TABLE:=51820}"
: "${VPN_FWMARK:=0x51820}"; : "${VPN_HEALTH_URL:=https://ifconfig.co/json}"; : "${VPN_TEST_URL:=}"
as_app() { sudo -u "$VPN_APP_USER" "$@"; }
H() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

H "1) حالة خدمة VPN"
systemctl is-active iptvpro-vpn 2>/dev/null || echo "(الخدمة غير نشطة)"
bash "$APP_DIR/vpn/vpnctl.sh" status

H "2) IP السيرفر الأصلي (root) مقابل IP التطبيق (عبر VPN)"
echo -n "IP السيرفر  (root):     "; curl -s4 -m 10 https://ifconfig.co/ip 2>/dev/null;
echo -n "دولة السيرفر:           "; curl -s4 -m 10 https://ifconfig.co/country 2>/dev/null
echo -n "IP التطبيق (VPN):       "; as_app curl -s4 -m 10 https://ifconfig.co/ip 2>/dev/null
echo -n "دولة التطبيق (VPN):     "; as_app curl -s4 -m 10 https://ifconfig.co/country 2>/dev/null

SRV=$(curl -s4 -m 10 https://ifconfig.co/ip 2>/dev/null)
APPIP=$(as_app curl -s4 -m 10 https://ifconfig.co/ip 2>/dev/null)
if [ -n "$APPIP" ] && [ "$APPIP" != "$SRV" ]; then
  echo "✅ تغيّر IP الخروج فعلياً: التطبيق يخرج من $APPIP (≠ $SRV)"
else
  echo "⚠️ لم يتغيّر IP — VPN غير فعّال (راجع المنطق أدناه)"
fi

H "3) جدول التوجيه و القاعدة (split-tunnel)"
ip rule show | grep -i "$VPN_FWMARK" || echo "(لا توجد قاعدة fwmark)"
ip route show table "$VPN_TABLE" 2>/dev/null || echo "(جدول $VPN_TABLE فارغ)"
echo -n "مسار حزمة التطبيق (مع mark): "; ip route get 1.1.1.1 mark "$VPN_FWMARK" 2>/dev/null | head -1

if [ -n "$VPN_TEST_URL" ]; then
  H "4) اختبار مزوّد IPTV عبر VPN (HTTP status)"
  echo -n "السيرفر مباشرة:  "; curl -s4 -o /dev/null -w "%{http_code}\n" -m 15 "$VPN_TEST_URL" 2>/dev/null
  echo -n "عبر VPN:        "; as_app curl -s4 -o /dev/null -w "%{http_code}\n" -m 15 "$VPN_TEST_URL" 2>/dev/null
  echo "  (200 = نجاح · 403/1020 = حجب Cloudflare · 429 = طلبات كثيرة)"
fi

H "5) اختبار Kill Switch (يجب أن يُحجب ترافيك التطبيق عند فصل VPN)"
if ip -o addr show "$VPN_IFACE" >/dev/null 2>&1; then
  echo "إسقاط الواجهة مؤقتاً…"; ip link set "$VPN_IFACE" down 2>/dev/null || wg-quick down "$VPN_IFACE" 2>/dev/null || true
  sleep 2
  CODE=$(as_app curl -s4 -o /dev/null -w "%{http_code}" -m 8 "$VPN_HEALTH_URL" 2>/dev/null || echo 000)
  if [ "$CODE" = "000" ]; then echo "✅ Kill Switch يعمل: التطبيق محجوب (لا تسريب من IP السيرفر)";
  else echo "⚠️ تسرّب محتمل: التطبيق وصل بكود $CODE رغم فصل VPN"; fi
  echo "إعادة رفع VPN…"; bash "$APP_DIR/vpn/vpnctl.sh" up >/dev/null 2>&1 || systemctl restart iptvpro-vpn 2>/dev/null || true
else
  echo "(الواجهة $VPN_IFACE غير موجودة — VPN غير مرفوع، فلا اختبار)"
fi

H "النتيجة النهائية"
bash "$APP_DIR/vpn/vpnctl.sh" status
echo "للسجل الحيّ:  journalctl -u iptvpro-vpn -f   |   tail -f /var/log/iptvpro-vpn.log"
