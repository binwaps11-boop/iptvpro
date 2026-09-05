#!/usr/bin/env bash
#
# setup-mexico-vpn.sh — يوجّه حركة التطبيق فقط عبر VPN مكسيكي (WireGuard)
# بحيث يخرج سيرفرك من IP مكسيكي عند جلب القنوات، بينما يبقى SSH وكل شيء آخر على IP السيرفر.
# (توجيه انتقائي بحسب مستخدم الخدمة www-data — لا يكسر اتصالك.)
#
# المتطلب الوحيد منك: ملف إعداد WireGuard لخادم مكسيكي من مزوّد VPN
# (Mullvad / ProtonVPN / Windscribe / IVPN ... اختر خادم Mexico، صيغة WireGuard).
#
# الاستخدام:
#   1) ضع ملف الـ WireGuard المكسيكي في:  /etc/wireguard/mx.conf
#   2) sudo bash deploy/setup-mexico-vpn.sh
#   للإلغاء:  sudo bash deploy/setup-mexico-vpn.sh --down
#
set -uo pipefail
IFACE=mx
CONF="/etc/wireguard/${IFACE}.conf"
APP_USER="${SERVICE_USER:-www-data}"
TABLE=51820
MARK=0x51820
[ "$(id -u)" -eq 0 ] || { echo "شغّله بصلاحية root (sudo)"; exit 1; }
line(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# ---- وضع الإلغاء ----
if [ "${1:-}" = "--down" ]; then
  line "إلغاء توجيه المكسيك"
  iptables -t mangle -D OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK 2>/dev/null || true
  ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
  ip route flush table $TABLE 2>/dev/null || true
  systemctl stop "wg-quick@${IFACE}" 2>/dev/null || wg-quick down "$IFACE" 2>/dev/null || true
  systemctl disable "wg-quick@${IFACE}" 2>/dev/null || true
  netfilter-persistent save 2>/dev/null || true
  echo "تم الإلغاء. التطبيق عاد يخرج من IP السيرفر."
  exit 0
fi

[ -f "$CONF" ] || {
  echo "✗ لم أجد $CONF"
  echo "  ضع ملف WireGuard المكسيكي هناك أولاً. مثال:"
  echo "    nano $CONF   # ثم الصق محتوى الإعداد من مزوّد VPN (خادم Mexico)"
  exit 1
}

line "تثبيت WireGuard"
apt-get update -y >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iptables-persistent >/dev/null 2>&1 || true

line "تجهيز الإعداد (توجيه انتقائي بلا كسر للنظام)"
# نزيل أي DNS عام و نضيف Table=off حتى لا يلتقط WireGuard كل المسار
sed -i '/^[[:space:]]*DNS[[:space:]]*=/d' "$CONF"
grep -qi '^[[:space:]]*Table' "$CONF" || sed -i '0,/^\[Interface\]/{s//\[Interface\]\nTable = off/}' "$CONF"
# تأكد أن AllowedIPs تشمل كل الإنترنت (مطلوب للتوجيه)
grep -qi 'AllowedIPs' "$CONF" || echo "⚠️ تأكد أن قسم [Peer] فيه AllowedIPs = 0.0.0.0/0"

line "رفع نفق WireGuard المكسيكي"
systemctl enable "wg-quick@${IFACE}" >/dev/null 2>&1 || true
wg-quick down "$IFACE" 2>/dev/null || true
wg-quick up "$IFACE"

line "توجيه حركة التطبيق ($APP_USER) فقط عبر النفق"
# جدول توجيه خاص يخرج عبر النفق
ip route replace default dev "$IFACE" table $TABLE
ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
ip rule add fwmark $MARK table $TABLE
# علّم فقط حركة مستخدم التطبيق (www-data) — SSH (root) لا يُعلَّم فيبقى طبيعياً
iptables -t mangle -D OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK 2>/dev/null || true
iptables -t mangle -A OUTPUT -m owner --uid-owner "$APP_USER" -j MARK --set-mark $MARK
# اسمح بالتوجيه غير المتماثل
sysctl -qw net.ipv4.conf.all.rp_filter=2
sysctl -qw "net.ipv4.conf.${IFACE}.rp_filter=2" 2>/dev/null || true
netfilter-persistent save >/dev/null 2>&1 || true

line "إعادة تشغيل التطبيق"
systemctl restart iptvpro 2>/dev/null || true
sleep 2

line "التحقّق (يجب أن يختلف خروج التطبيق عن خروج السيرفر)"
SRV_IP="$(curl -s4 -m 12 https://ifconfig.co/ip 2>/dev/null || echo '?')"
APP_IP="$(sudo -u "$APP_USER" curl -s4 -m 12 https://ifconfig.co/country 2>/dev/null || echo '?')"
APP_IPADDR="$(sudo -u "$APP_USER" curl -s4 -m 12 https://ifconfig.co/ip 2>/dev/null || echo '?')"
echo "خروج السيرفر (SSH/الإدارة): $SRV_IP"
echo "خروج التطبيق (جلب القنوات): $APP_IPADDR  /  الدولة: $APP_IP"
echo
if echo "$APP_IP" | grep -qiE 'mexico|méxico|MX'; then
  printf '\033[1;32m✅ ممتاز! التطبيق يخرج الآن من المكسيك. ارجع للوحة → مصادر IPTV → استورد من جديد.\033[0m\n'
else
  printf '\033[1;33m⚠️ خروج التطبيق ليس من المكسيك بعد.\033[0m\n'
  echo "  تأكد أن ملف $CONF لخادم Mexico وفيه AllowedIPs = 0.0.0.0/0، ثم أعد تشغيل السكربت."
fi
echo
echo "للإلغاء لاحقاً:  sudo bash deploy/setup-mexico-vpn.sh --down"
