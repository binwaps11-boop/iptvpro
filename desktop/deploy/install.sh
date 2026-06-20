#!/usr/bin/env bash
#
# مثبّت IPTV Pro التلقائي — يُشغَّل على VPS (Ubuntu/Debian) بصلاحية root.
# يثبّت Node.js، ويُعدّ النظام كخدمة دائمة (systemd)، ويفتح المنفذ.
# اختيارياً: Nginx كوسيط عكسي + شهادة HTTPS عبر Let's Encrypt إذا مرّرت DOMAIN.
#
# الاستخدام (من داخل مجلد المشروع desktop/):
#   sudo ADMIN_PASSWORD='كلمة-قوية' bash deploy/install.sh
#   # أو مع دومين و HTTPS:
#   sudo ADMIN_PASSWORD='كلمة-قوية' DOMAIN=tv.example.com EMAIL=you@mail.com bash deploy/install.sh
#
set -euo pipefail

PORT="${PORT:-8787}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
SERVICE_USER="${SERVICE_USER:-www-data}"

# مجلد المشروع = المجلد الأب لهذا السكربت (desktop/)
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { echo -e "\n\033[1;36m▶ $*\033[0m"; }
need_root() { [ "$(id -u)" -eq 0 ] || { echo "شغّله بصلاحية root (sudo)"; exit 1; }; }
need_root

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "⚠️  لم تحدّد ADMIN_PASSWORD — سيُستخدم 'admin' افتراضياً (غيّرها فوراً من اللوحة)."
fi

say "تثبيت Node.js إن لزم"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node --version

say "إعداد خدمة systemd"
cat > /etc/systemd/system/iptvpro.service <<UNIT
[Unit]
Description=IPTV Pro Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=PORT=$PORT
Environment=ADMIN_USER=$ADMIN_USER
Environment=ADMIN_PASSWORD=$ADMIN_PASSWORD
ExecStart=$(command -v node) server.js
Restart=always
RestartSec=3
User=$SERVICE_USER
# السماح للخدمة بكتابة config.json داخل مجلد المشروع
ReadWritePaths=$APP_DIR

[Install]
WantedBy=multi-user.target
UNIT

# تأكد أن مستخدم الخدمة يملك صلاحية الكتابة في مجلد المشروع
chown -R "$SERVICE_USER":"$SERVICE_USER" "$APP_DIR" 2>/dev/null || true

systemctl daemon-reload
systemctl enable iptvpro
systemctl restart iptvpro
sleep 2
systemctl --no-pager status iptvpro | head -n 8 || true

say "فتح المنفذ في الجدار الناري (إن وُجد ufw)"
if command -v ufw >/dev/null 2>&1; then ufw allow "$PORT"/tcp || true; fi

PUBIP="$(curl -fsSL https://api.ipify.org 2>/dev/null || echo 'SERVER_IP')"

if [ -n "$DOMAIN" ]; then
  say "إعداد Nginx + HTTPS للدومين $DOMAIN"
  apt-get install -y nginx
  cat > /etc/nginx/sites-available/iptvpro <<NGINX
server {
  listen 80;
  server_name $DOMAIN;
  location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_buffering off;
    proxy_read_timeout 3600s;
  }
}
NGINX
  ln -sf /etc/nginx/sites-available/iptvpro /etc/nginx/sites-enabled/iptvpro
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl restart nginx
  if command -v ufw >/dev/null 2>&1; then ufw allow 80/tcp || true; ufw allow 443/tcp || true; fi
  if [ -n "$EMAIL" ]; then
    apt-get install -y certbot python3-certbot-nginx
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || \
      echo "⚠️ تعذّر إصدار الشهادة تلقائياً — راجع توجيه الدومين (A record) ثم أعد المحاولة."
  fi
  echo -e "\n\033[1;32m✅ تم! افتح:  https://$DOMAIN/  (الإدارة: /admin)\033[0m\n"
else
  echo -e "\n\033[1;32m✅ تم! افتح:  http://$PUBIP:$PORT/   (الإدارة: http://$PUBIP:$PORT/admin)\033[0m"
  echo -e "   الدخول للإدارة: المستخدم=$ADMIN_USER  كلمة المرور=${ADMIN_PASSWORD:-admin}\n"
fi

echo "أوامر مفيدة:"
echo "  سجل التشغيل:  journalctl -u iptvpro -f"
echo "  إعادة تشغيل:  systemctl restart iptvpro"
echo "  تحديث الكود:  cd $APP_DIR && git pull && systemctl restart iptvpro"
