# خادم تراخيص «مدير الكروت»

قاعدة بيانات حقيقية تربط **الحسابات وأرقام الجوالات** بنظام الترخيص، مع تحقق
أونلاين دوري. القرار كله على الخادم — التطبيق لا يستطيع منح نفسه ترخيصاً.

- **بلا أي تبعيات**: Node.js وحده (لا npm install)
- **ملف واحد**: `server.js`
- **قاعدة بيانات**: ملف JSON بكتابة ذرّية (كافٍ لآلاف الحسابات)

---

## ما يفرضه الخادم (مُختبَر فعلياً)

| القاعدة | السلوك |
|---|---|
| حساب واحد = جهاز واحد | تسجيل نفس البريد من جهاز آخر → **رفض** مع ذكر الجهاز المربوط |
| التجربة مرة واحدة لكل جهاز | مسح بيانات التطبيق أو بريد جديد على نفس الجهاز → **لا تجربة جديدة** |
| البريد والجوال إلزاميان | تحقق من الصيغة، والرفض برسالة عربية |
| نسخ الحساب لجهاز آخر | التحقق الدوري يرد `wrong_device` → التطبيق يُقفل |
| إيقاف عن بعد | الأدمن يوقف الحساب → التطبيق يُقفل عند أول تحقق |
| منع إعادة التشغيل | نفس `nonce` لا يُقبل مرتين |
| مسارات الأدمن | تتطلب رمزاً سرياً، ومقارنته ثابتة الزمن |
| تحديد المعدل | 60 طلباً/دقيقة لكل عنوان |

كل رد يُوقَّع بـ **ECDSA P-256**؛ المفتاح الخاص لا يغادر الخادم، والتطبيق
يحمل العام فقط ويتحقق من التوقيع قبل الوثوق بأي حالة.

---

## النشر على VPS أوبونتو (٣ أوامر)

```bash
# 1) ثبّت Node (مرة واحدة)
sudo apt update && sudo apt install -y nodejs

# 2) انسخ المجلد license-server إلى الخادم ثم:
cd license-server
export ADMIN_TOKEN="$(openssl rand -hex 24)"   # احفظه — رمز لوحة الأدمن
echo "رمز الأدمن: $ADMIN_TOKEN"

# 3) شغّله
node server.js
```

عند أول تشغيل يطبع **المفتاح العام** — انسخه وضعه في التطبيق (انظر أدناه).

### تشغيل دائم (يعيد نفسه بعد إعادة التشغيل)

```bash
sudo tee /etc/systemd/system/cardlicense.service > /dev/null <<'EOF'
[Unit]
Description=Card Manager License Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/license-server
Environment=PORT=8090
Environment=ADMIN_TOKEN=ضع_الرمز_هنا
ExecStart=/usr/bin/node /opt/license-server/server.js
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cardlicense
sudo systemctl status cardlicense
```

### HTTPS (موصى به بشدة)

الخادم يعمل على HTTP محلياً؛ ضع خلفه Nginx بشهادة مجانية:

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo tee /etc/nginx/sites-available/license > /dev/null <<'EOF'
server {
    server_name license.example.com;
    location / { proxy_pass http://127.0.0.1:8090; }
}
EOF
sudo ln -sf /etc/nginx/sites-available/license /etc/nginx/sites-enabled/
sudo certbot --nginx -d license.example.com
```

---

## ربطه بالتطبيق

في `CardManagerApp/app/src/main/java/com/binwaps/cardmanager/data/BackendConfig.kt`:

```kotlin
const val LICENSE_SERVER = "https://license.example.com"   // عنوان خادمك
const val SERVER_PUBLIC_KEY = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcD..."  // المفتاح المطبوع
```

ثم ابنِ التطبيق. بمجرد امتلاء هذين الحقلين يتحول الترخيص من محلي إلى أونلاين.

---

## واجهة API

### للتطبيق

| المسار | الغرض |
|---|---|
| `POST /api/register` | تسجيل حساب وبدء التجربة. الحقول: `email, phone, name, device` |
| `POST /api/check` | التحقق الدوري. الحقول: `email, device, nonce` |
| `POST /api/request` | طلب ترخيص/تجديد. الحقول: `email, device, renewal, note` |
| `GET /api/pubkey` | المفتاح العام |
| `GET /api/health` | فحص الحياة |

### للأدمن (ترويسة `x-admin-token`)

| المسار | الغرض |
|---|---|
| `GET /api/admin/accounts` | كل الحسابات وحالاتها |
| `POST /api/admin/approve` | منح خطة: `{id, plan}` حيث plan ∈ trial/month/quarter/year/lifetime |
| `POST /api/admin/block` | إيقاف/استئناف: `{id, blocked}` |
| `POST /api/admin/rebind` | نقل الحساب لجهاز جديد: `{id, device}` |
| `GET /api/admin/events` | سجل العمليات |

**التجديد يضيف للمتبقي ولا يلغيه** — من وافقتَ له وبقي أسبوع ثم منحته شهراً يصير لديه 37 يوماً.

---

## النسخ الاحتياطي

كل البيانات في `data/licenses.json`. انسخه دورياً:

```bash
0 3 * * * cp /opt/license-server/data/licenses.json /backup/licenses-$(date +\%F).json
```

⚠️ **`data/signing-key.pem` هو مفتاحك الخاص** — احتفظ بنسخة آمنة منه. فقدانه
يعني أن كل التراخيص الصادرة لن يقبلها التطبيق بعد إعادة توليد مفتاح جديد.
