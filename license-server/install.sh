#!/usr/bin/env bash
# تثبيت خادم تراخيص «مدير الكروت» بأمر واحد على أوبونتو/دبيان.
#
#   sudo bash install.sh
#
# يفعل كل شيء: يثبّت Node ٢٠، ينسخ الملفات، ينشئ خدمة تعمل بعد إعادة التشغيل،
# يولّد رمز الأدمن، ثم يطبع المفتاح العام لتضعه في التطبيق.

set -euo pipefail

APP_DIR=/opt/license-server
SERVICE=cardlicense
PORT="${PORT:-8090}"

if [ "$(id -u)" -ne 0 ]; then
  echo "✗ شغّله بصلاحية الجذر:  sudo bash install.sh" >&2
  exit 1
fi

echo "▸ تثبيت Node.js 20…"
# مستودع أوبونتو الافتراضي يعطي Node 12 وهو أقدم من أن يشغّل الخادم،
# فيفشل التثبيت برسالة syntax error محيّرة. نأخذه من NodeSource مباشرة.
if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 18 ]; then
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null
  apt-get install -y -qq nodejs
fi
echo "  Node $(node -v)"

echo "▸ نسخ الملفات إلى $APP_DIR…"
mkdir -p "$APP_DIR"
cp -f "$(dirname "$0")/server.js" "$APP_DIR/"
cp -f "$(dirname "$0")/admin.html" "$APP_DIR/"
cp -f "$(dirname "$0")/package.json" "$APP_DIR/" 2>/dev/null || true
mkdir -p "$APP_DIR/data"

# الرمز يُولَّد مرة واحدة ويبقى: إعادة التثبيت يجب ألا تُبطل لوحة الأدمن
TOKEN_FILE="$APP_DIR/data/admin-token"
if [ ! -f "$TOKEN_FILE" ]; then
  head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi
ADMIN_TOKEN="$(cat "$TOKEN_FILE")"

echo "▸ إنشاء الخدمة…"
cat > /etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=Card Manager License Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=PORT=$PORT
Environment=ADMIN_TOKEN=$ADMIN_TOKEN
ExecStart=/usr/bin/node $APP_DIR/server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now $SERVICE >/dev/null 2>&1
sleep 2

if ! systemctl is-active --quiet $SERVICE; then
  echo "✗ لم تبدأ الخدمة. السجل:" >&2
  journalctl -u $SERVICE -n 30 --no-pager >&2
  exit 1
fi

PUBKEY="$(curl -fsS "http://127.0.0.1:$PORT/api/pubkey" | sed 's/.*"publicKey":"\([^"]*\)".*/\1/')"
IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

cat <<EOF

════════════════════════════════════════════════════
✓ الخادم يعمل: http://$IP:$PORT

لوحة الأدمن (افتحها من جوالك):
  http://$IP:$PORT/

رمز لوحة الأدمن (احفظه):
  $ADMIN_TOKEN

المفتاح العام — ضعه في BackendConfig.kt:
  const val LICENSE_SERVER    = "http://$IP:$PORT"
  const val SERVER_PUBLIC_KEY = "$PUBKEY"

أوامر مفيدة:
  systemctl status $SERVICE      حالة الخادم
  journalctl -u $SERVICE -f      متابعة السجل
  systemctl restart $SERVICE     إعادة التشغيل

⚠ افتح المنفذ في الجدار الناري إن كان مفعّلاً:
  ufw allow $PORT/tcp
⚠ نسخة احتياطية إلزامية من:  $APP_DIR/data/
════════════════════════════════════════════════════
EOF
