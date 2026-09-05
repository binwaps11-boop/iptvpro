#!/usr/bin/env bash
# ============================================================================
# warp-setup.sh — تثبيت Cloudflare WARP بوضع البروكسي (split-tunnel) واختباره.
# يخرج التطبيق عبر شبكة Cloudflare (ليس المكسيك). مفيد كاختبار سريع لـ«هل الـ VPN يغيّر IP».
#   sudo bash vpn/warp-setup.sh
#   sudo bash vpn/warp-setup.sh --off   (إيقاف وإلغاء الربط)
# ============================================================================
set -uo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${WARP_PROXY_PORT:-40000}"
[ "$(id -u)" -eq 0 ] || { echo "شغّله بـ sudo"; exit 1; }
W() { warp-cli --accept-tos "$@" 2>/dev/null || warp-cli "$@" 2>/dev/null; }

if [ "${1:-}" = "--off" ]; then
  W disconnect; W mode warp 2>/dev/null || true
  [ -f "$APP_DIR/config.json" ] && node -e 'const fs=require("fs"),p=process.argv[1];try{const c=JSON.parse(fs.readFileSync(p));if(c.settings&&c.settings.upstream){c.settings.upstream.enabled=false;fs.writeFileSync(p,JSON.stringify(c,null,2));}}catch{}' "$APP_DIR/config.json"
  systemctl restart iptvpro 2>/dev/null || true
  echo "تم إيقاف WARP وإلغاء ربط التطبيق."
  exit 0
fi

echo "▶ تثبيت Cloudflare WARP"
apt-get install -y curl gpg lsb-release >/dev/null 2>&1 || true
if ! command -v warp-cli >/dev/null 2>&1; then
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list
  apt-get update -y >/dev/null 2>&1
  apt-get install -y cloudflare-warp >/dev/null 2>&1
fi

echo "▶ تسجيل + وضع البروكسي (يخرج التطبيق فقط عبر WARP، SSH يبقى)"
W registration new || true
W mode proxy || W set-mode proxy || true
W proxy port "$PORT" || true
W connect || true
sleep 3
echo "▶ حالة WARP:"; W status

echo "▶ ربط التطبيق بـ SOCKS5 127.0.0.1:$PORT"
CFG="$APP_DIR/config.json"
if [ -f "$CFG" ]; then
  node -e 'const fs=require("fs"),p=process.argv[1],port=+process.argv[2];const c=JSON.parse(fs.readFileSync(p));c.settings=c.settings||{};c.settings.upstream={enabled:true,type:"socks5",host:"127.0.0.1",port,username:"",password:""};fs.writeFileSync(p,JSON.stringify(c,null,2));' "$CFG" "$PORT" \
    && echo "  ✓ ضُبط البروكسي في config.json"
  systemctl restart iptvpro 2>/dev/null || true
else
  echo "  ⚠️ config.json غير موجود بعد — اضبط البروكسي من اللوحة: SOCKS5 / 127.0.0.1 / $PORT"
fi

echo
echo "════════ اختبار قبل/بعد ════════"
echo -n "IP السيرفر مباشرة:   "; curl -s4 -m 10 https://ifconfig.co/ip
echo -n "دولة السيرفر:         "; curl -s4 -m 10 https://ifconfig.co/country
echo -n "IP عبر WARP:          "; curl -s4 -m 12 -x socks5h://127.0.0.1:$PORT https://ifconfig.co/ip
echo -n "دولة عبر WARP:        "; curl -s4 -m 12 -x socks5h://127.0.0.1:$PORT https://ifconfig.co/country
if [ -n "${VPN_TEST_URL:-}" ]; then
  echo -n "كود المزوّد عبر WARP: "; curl -s4 -o /dev/null -w "%{http_code}\n" -m 15 -x socks5h://127.0.0.1:$PORT "$VPN_TEST_URL"
fi
echo "⚠️ WARP لا يدعم اختيار المكسيك — للمكسيك استخدم Proton Plus/Mullvad WireGuard في نظام vpnctl."
echo "للإيقاف:  sudo bash vpn/warp-setup.sh --off"
