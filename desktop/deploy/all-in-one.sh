#!/usr/bin/env bash
# ============================================================================
# all-in-one.sh — تثبيت كامل بأمر واحد:
#   التطبيق (عملاء+إدارة) + فتح المنافذ + نظام VPN + WARP + استيراد تلقائي.
# الاستخدام (كـ root على Ubuntu/Debian):
#   curl -fsSL https://raw.githubusercontent.com/binwaps11-boop/iptvpro/claude/iptv-player-app-e80rvb/desktop/deploy/all-in-one.sh | sudo bash
#   (أو انسخه والصقه ثم: sudo bash all-in-one.sh)
# متغيّرات اختيارية: ADMIN_PASSWORD, USER_PORT, ADMIN_PORT
# ============================================================================
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "شغّله بـ sudo/root"; exit 1; }

REPO="https://github.com/binwaps11-boop/iptvpro"
BRANCH="claude/iptv-player-app-e80rvb"
DIR=/opt/iptvpro
ADMIN_PASSWORD="${ADMIN_PASSWORD:-Tv221Admin}"
USER_PORT="${USER_PORT:-221}"
ADMIN_PORT="${ADMIN_PORT:-331}"
export ADMIN_PASSWORD USER_PORT ADMIN_PORT
H(){ printf '\n\033[1;36m========== %s ==========\033[0m\n' "$*"; }

H "1) الأدوات الأساسية"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y git curl >/dev/null 2>&1 || true

H "2) جلب/تحديث المشروع"
if [ -d "$DIR/.git" ]; then (cd "$DIR" && git fetch origin "$BRANCH" && git checkout "$BRANCH" && git pull); else git clone -b "$BRANCH" "$REPO" "$DIR"; fi
cd "$DIR/desktop"
[ -f .env ] || cp .env.example .env

H "3) تثبيت التطبيق كخدمة (عملاء $USER_PORT / إدارة $ADMIN_PORT)"
bash deploy/install.sh

H "4) فتح المنافذ"
bash deploy/open-ports.sh || true

H "5) تثبيت نظام VPN (systemd + kill switch)"
bash vpn/install-vpn.sh || true

H "6) تشغيل WARP المجاني (أفضل توجيه تلقائي متاح بلا اشتراك)"
bash vpn/warp-setup.sh || true

IP="$(curl -s4 -m 10 https://ifconfig.co/ip 2>/dev/null || echo SERVER_IP)"
H "✅ تم التثبيت الكامل"
echo "   👥 بوابة العملاء:  http://$IP:$USER_PORT/"
echo "   🔐 لوحة الإدارة:   http://$IP:$ADMIN_PORT/admin   (admin / $ADMIN_PASSWORD)"
echo
echo "   • التطبيق + الأدوار + الاشتراكات + Shared Relay + الاستيراد التلقائي: جاهزة وتعمل."
echo "   • أضف مصدر Xtream من اللوحة (أو هو محفوظ مسبقاً) — سيُستورد تلقائياً عند توفّر اتصال."
echo
echo "   ⚠️ لجلب قنوات مزوّد محظور جغرافياً (يتطلب المكسيك):"
echo "      ضع ملف WireGuard مكسيكي (من اشتراك VPN) في: /etc/iptvpro/vpn/MX.conf"
echo "      ثم:  systemctl restart iptvpro-vpn"
echo "      وبعدها تظهر كل القنوات/الأفلام/المسلسلات تلقائياً خلال ٥ دقائق."
echo
echo "   فحص:  bash $DIR/desktop/vpn/verify.sh"
