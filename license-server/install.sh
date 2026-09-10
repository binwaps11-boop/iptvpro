#!/usr/bin/env bash
# Run on the owner's VPS from the private deployment bundle.
set -euo pipefail
umask 077
LICENSE_DOMAIN="${LICENSE_DOMAIN:?Set LICENSE_DOMAIN to your HTTPS hostname}"
[[ "$LICENSE_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] && [[ "$LICENSE_DOMAIN" == *.* ]] || exit 1
LICENSE_CERT="${LICENSE_CERT:-/etc/letsencrypt/live/$LICENSE_DOMAIN/fullchain.pem}"
LICENSE_TLS_KEY="${LICENSE_TLS_KEY:-/etc/letsencrypt/live/$LICENSE_DOMAIN/privkey.pem}"
LICENSE_PORT="${LICENSE_PORT:-8091}"
[[ "$LICENSE_PORT" =~ ^[0-9]{4,5}$ ]] && ((LICENSE_PORT >= 1024 && LICENSE_PORT <= 65535)) || exit 1
[[ "$(id -u)" == 0 ]] || { echo 'Run with sudo on your VPS' >&2; exit 1; }
command -v node >/dev/null
[[ "$(node -p 'Number(process.versions.node.split(".")[0]) >= 22')" == true ]] || { echo 'Node.js 22 or newer is required' >&2; exit 1; }
command -v nginx >/dev/null
[[ -f "$LICENSE_CERT" && -f "$LICENSE_TLS_KEY" ]] || { echo 'Install a valid TLS certificate first' >&2; exit 1; }
LICENSE_SOURCE="$(cd -- "$(dirname -- "$0")" && pwd)"
LICENSE_SIGNING_KEY="${LICENSE_SIGNING_KEY:-$LICENSE_SOURCE/signing-key.pem}"
[[ -f "$LICENSE_SIGNING_KEY" ]] || { echo 'The private provider key is missing' >&2; exit 1; }
node - "$LICENSE_SIGNING_KEY" "$LICENSE_SOURCE/provider-public-key.txt" <<'JS'
const fs = require('fs'), crypto = require('crypto');
const actual = crypto.createPublicKey(crypto.createPrivateKey(fs.readFileSync(process.argv[2])))
  .export({type:'spki',format:'der'}).toString('base64');
if (actual !== fs.readFileSync(process.argv[3], 'utf8').trim()) throw Error('Provider key does not match this APK');
JS
LICENSE_APP=/opt/cardmanager-license-v2
LICENSE_DATA=/var/lib/cardlicense-v2
LICENSE_SERVICE=cardlicense-v2
LICENSE_CONF=/etc/nginx/sites-available/cardlicense-v2
[[ -d /etc/nginx/sites-available && -d /etc/nginx/sites-enabled ]] || { echo 'Nginx sites directories are required' >&2; exit 1; }
if [[ -f "$LICENSE_DATA/signing-key.pem" ]]; then
  cmp -s "$LICENSE_DATA/signing-key.pem" "$LICENSE_SIGNING_KEY" || { echo 'Existing provider key differs; no files changed' >&2; exit 1; }
fi
id -u cardlicense-v2 >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin cardlicense-v2
install -d -m 755 "$LICENSE_APP"
install -d -o cardlicense-v2 -g cardlicense-v2 -m 700 "$LICENSE_DATA"
install -m 644 "$LICENSE_SOURCE/server.js" "$LICENSE_SOURCE/admin.html" "$LICENSE_APP/"
install -o cardlicense-v2 -g cardlicense-v2 -m 600 "$LICENSE_SIGNING_KEY" "$LICENSE_DATA/signing-key.pem"
if [[ ! -f /etc/cardlicense-v2.env ]]; then
  LICENSE_ADMIN_TOKEN="$(openssl rand -hex 32)"
  printf 'ADMIN_TOKEN=%s\n' "$LICENSE_ADMIN_TOKEN" > /etc/cardlicense-v2.env
  chmod 600 /etc/cardlicense-v2.env
fi
LICENSE_NODE="$(command -v node)"
cat > /etc/systemd/system/cardlicense-v2.service <<EOF
[Unit]
Description=Card Manager subscription authority
After=network.target
[Service]
Type=simple
User=cardlicense-v2
Group=cardlicense-v2
WorkingDirectory=$LICENSE_APP
EnvironmentFile=/etc/cardlicense-v2.env
Environment=PORT=$LICENSE_PORT
Environment=LISTEN_HOST=127.0.0.1
Environment=DATA_DIR=$LICENSE_DATA
Environment=TRUST_PROXY=1
Environment=REQUIRE_EXISTING_KEY=1
ExecStart=$LICENSE_NODE $LICENSE_APP/server.js
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=$LICENSE_DATA
UMask=0077
[Install]
WantedBy=multi-user.target
EOF
LICENSE_OLD_CONF="$(mktemp)"
LICENSE_HAD_CONF=0
if [[ -f "$LICENSE_CONF" ]]; then cp "$LICENSE_CONF" "$LICENSE_OLD_CONF"; LICENSE_HAD_CONF=1; fi
cat > "$LICENSE_CONF" <<EOF
server {
    listen 443 ssl;
    server_name $LICENSE_DOMAIN;
    ssl_certificate "$LICENSE_CERT";
    ssl_certificate_key "$LICENSE_TLS_KEY";
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 96k;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    location / {
        proxy_pass http://127.0.0.1:$LICENSE_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_read_timeout 15s;
    }
}
EOF
LICENSE_HAD_LINK=0
[[ -e /etc/nginx/sites-enabled/cardlicense-v2 ]] && LICENSE_HAD_LINK=1
ln -sf "$LICENSE_CONF" /etc/nginx/sites-enabled/cardlicense-v2
if ! nginx -t; then
  if [[ "$LICENSE_HAD_CONF" == 1 ]]; then cp "$LICENSE_OLD_CONF" "$LICENSE_CONF"; else rm -f "$LICENSE_CONF"; fi
  [[ "$LICENSE_HAD_LINK" == 1 ]] || rm -f /etc/nginx/sites-enabled/cardlicense-v2
  rm -f "$LICENSE_OLD_CONF"
  exit 1
fi
rm -f "$LICENSE_OLD_CONF"
systemctl daemon-reload
systemctl enable "$LICENSE_SERVICE"
systemctl restart "$LICENSE_SERVICE"
systemctl reload nginx
printf '\nService address for BOTH APKs: https://%s\n' "$LICENSE_DOMAIN"
printf 'Read your admin token privately: sudo cat /etc/cardlicense-v2.env\n'
printf 'Keep a private backup of %s and the APK signing materials.\n' "$LICENSE_DATA"
