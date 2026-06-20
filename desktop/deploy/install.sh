#!/usr/bin/env bash
#
# مثبّت IPTV Pro التلقائي — يُشغَّل على VPS (Ubuntu/Debian) بصلاحية root.
# يثبّت Node.js، ويُعدّ النظام كخدمة دائمة (systemd) على منفذين:
#   - العملاء  USER_PORT  (افتراضي 221)
#   - الإدارة  ADMIN_PORT (افتراضي 331)
# اختيارياً: Nginx + HTTPS عبر Let's Encrypt إذا مرّرت DOMAIN.
#
# الاستخدام (من داخل مجلد المشروع desktop/):
#   sudo ADMIN_PASSWORD='كلمة-قوية' bash deploy/install.sh
#   # تخصيص المنافذ:
#   sudo ADMIN_PASSWORD='قوية' USER_PORT=221 ADMIN_PORT=331 bash deploy/install.sh
#   # مع دومين و HTTPS:
#   sudo ADMIN_PASSWORD='قوية' DOMAIN=tv.example.com EMAIL=you@mail.com bash deploy/install.sh
#
set -euo pipefail

USER_PORT="${USER_PORT:-221}"
ADMIN_PORT="${ADMIN_PORT:-331}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
SERVICE_USER="${SERVICE_USER:-www-data}"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { echo -e "\n\033[1;36m▶ $*\033[0m"; }
need_root() { [ "$(id -u)" -eq 0 ] || { echo "شغّله بصلاحية root (sudo)"; exit 1; }; }
need_root

[ -z "$ADMIN_PASSWORD" ] && echo "⚠️  لم تحدّد ADMIN_PASSWORD — سيُستخدم 'admin' (غيّرها فوراً من اللوحة)."

say "تثبيت Node.js إن لزم"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node --version

say "إعداد خدمة systemd (منفذان: عملاء $USER_PORT / إدارة $ADMIN_PORT)"
cat > /etc/systemd/system/iptvpro.service <<UNIT
[Unit]
Description=IPTV Pro Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=USER_PORT=$USER_PORT
Environment=ADMIN_PORT=$ADMIN_PORT
Environment=ADMIN_USER=$ADMIN_USER
Environment=ADMIN_PASSWORD=$ADMIN_PASSWORD
ExecStart=$(command -v node) server.js
Restart=always
RestartSec=3
User=$SERVICE_USER
# السماح بالاستماع على منافذ أقل من 1024 (221/331)
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ReadWritePaths=$APP_DIR

[Install]
WantedBy=multi-user.target
UNIT

chown -R "$SERVICE_USER":"$SERVICE_USER" "$APP_DIR" 2>/dev/null || true
systemctl daemon-reload
systemctl enable iptvpro
systemctl restart iptvpro
sleep 2
systemctl --no-pager status iptvpro | head -n 9 || true

say "فتح المنافذ في الجدار الناري (ufw إن وُجد)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$USER_PORT"/tcp || true
  ufw allow "$ADMIN_PORT"/tcp || true
fi

PUBIP="$(curl -fsSL https://api.ipify.org 2>/dev/null || echo 'SERVER_IP')"

if [ -n "$DOMAIN" ]; then
  say "إعداد Nginx + HTTPS للدومين $DOMAIN"
  apt-get install -y nginx
  cat > /etc/nginx/sites-available/iptvpro <<NGINX
server {
  listen 80;
  server_name $DOMAIN;
  # لوحة الإدارة تمرّ لمنفذ الإدارة
  location /admin { proxy_pass http://127.0.0.1:$ADMIN_PORT; include proxy_params; proxy_buffering off; proxy_read_timeout 3600s; }
  # كل ما عدا ذلك (العملاء + API + البث) لمنفذ العملاء
  location / {
    proxy_pass http://127.0.0.1:$USER_PORT;
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
  command -v ufw >/dev/null 2>&1 && { ufw allow 80/tcp || true; ufw allow 443/tcp || true; }
  if [ -n "$EMAIL" ]; then
    apt-get install -y certbot python3-certbot-nginx
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || \
      echo "⚠️ تعذّر إصدار الشهادة — راجع توجيه الدومين (A record)."
  fi
  echo -e "\n\033[1;32m✅ تم! العملاء: https://$DOMAIN/   الإدارة: https://$DOMAIN/admin\033[0m\n"
else
  echo -e "\n\033[1;32m✅ تم!\033[0m"
  echo -e "   👥 بوابة العملاء:  http://$PUBIP:$USER_PORT/"
  echo -e "   🔐 لوحة الإدارة:   http://$PUBIP:$ADMIN_PORT/admin"
  echo -e "   الدخول للإدارة: المستخدم=$ADMIN_USER  كلمة المرور=${ADMIN_PASSWORD:-admin}\n"
fi

echo "أوامر مفيدة:"
echo "  السجل:        journalctl -u iptvpro -f"
echo "  إعادة تشغيل:  systemctl restart iptvpro"
echo "  تحديث:        cd $APP_DIR && git pull && systemctl restart iptvpro"
echo
echo "⚠️ تأكد من فتح المنفذين $USER_PORT و $ADMIN_PORT في جدار مزوّد VPS أيضاً."
