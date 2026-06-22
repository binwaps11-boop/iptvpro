# CR6606 Custom OpenWrt Firmware — مشروع كامل

ملف firmware مخصص لـ **Xiaomi Mi Router CR6606 فقط**، مبني على OpenWrt الرسمي + LuCI
الرسمية، مع Dashboard، Quick Setup، Port Control، VLAN، Broadband، Mesh، Wi-Fi،
وسكربتات فحص. **بدون أزرار وهمية، وبدون تزوير أرقام.**

> ⚠️ **صدق تقني مهم:** هذا المستودع يبني الصورة عبر **OpenWrt ImageBuilder الرسمي**.
> لا يوجد أي ملف `.bin` مزيّف داخل git. ملف `.bin` الحقيقي يُنتَج من:
> - **GitHub Actions** (`.github/workflows/build-cr6606-firmware.yml`) — يعمل تلقائياً عند الدفع، أو
> - **محلياً**: `sh firmware/cr6606/build-local.sh` على أي جهاز Linux فيه إنترنت.
>
> سبب عدم بنائه داخل بيئة المحادثة: سياسة الشبكة هنا تحجب `downloads.openwrt.org`
> (مؤكد: `403 host_not_allowed`)، ومن المرفوض تسليمك `.bin` غير مبني فعلياً.

---

## أولاً: تحليل الجهاز (مؤكَّد من مصدر OpenWrt الرسمي على GitHub)

| البند | القيمة | المصدر |
|---|---|---|
| Target | `ramips` | `target/linux/ramips/image/mt7621.mk` |
| Subtarget | `mt7621` | نفسه |
| Profile | `xiaomi_mi-router-cr6606` (ليس cr6608/cr6609/ax1800/ax3200) | `TARGET_DEVICES +=` |
| اسم الصورة الخام | `openwrt-<ver>-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin` | اشتقاق قياسي |
| الاسم النهائي | `openwrt-cr6606-custom-sysupgrade.bin` | إعادة تسمية |
| SoC | MediaTek MT7621AT (dual-core MIPS 1004Kc) | DTSI |
| التبديل | **DSA** (mt7530) — وليس swconfig | `&switch0` |
| المنافذ | **3×LAN** (lan1/lan2/lan3) + **1×WAN** مخصص (gmac1/ethphy4) | DTSI |
| Wi-Fi | **MT7915** (Wi-Fi6، شريحة DBDC واحدة: 2.4G + 5G) | `wifi@0,0 "mediatek,mt76"` |
| الدرايفر | mt76 / mt7915e + `kmod-mt7915-firmware` | image def |
| الفلاش | NAND 128MB، قسم `ubi` ≈ 121MB، kernel 4MB | partitions |
| MAC | يُقرأ من قسم **Factory** (lan=3fff4، wan=3fffa) — **لا يُلمَس** | nvmem-cells |
| Mesh | **مدعوم فعلياً** (802.11s عبر mt76 + wpad-mesh-mt76) | قدرات mt76 |

**أقسام المصنع المحمية** (لن يكتب عليها sysupgrade ولا أي سكربت هنا):
`Bootloader` · `Nvram` · `Bdata` · `Factory (EEPROM/ART/Calibration/MAC)` · `crash`.
نكتب **فقط** في قسم `ubi`. ✅ متوافق 100% مع قواعد الأمان التي طلبتها.

**هل DSA أم swconfig؟** → **DSA** (mt7530). لذلك التحكم بالـ VLAN عبر *bridge VLAN
filtering* وليس عبر `swconfig`، والإثبات عبر `bridge vlan show`.

### المشاكل المعروفة لهذه العائلة وكيف عالجناها
- **mt76 / Wi-Fi crash:** سكربت Health Check يكتشف اختفاء iface ويعيد `wifi up`. لا reboot مجدول.
- **OOM/RAM:** Health Check يُسقط الكاش عند انخفاض الذاكرة (<24MB). 256MB RAM كافية لقائمة الحزم المُقلَّمة.
- **DSA/switch errors:** نستخدم تهيئة اللوحة الافتراضية كما هي (لا نكسر الجسر).
- **flash full:** Health Check ينبّه عند امتلاء `/overlay` ≥ 90%.
- **thermal:** Dashboard يعرض الحرارة إن توفّر `thermal_zone` (قد لا يوجد مستشعر على mt7621 — يُعرض `n/a` بصدق).
- **watchdog:** عتاد mt7621 (mtk-wdt) يديره procd تلقائياً — لا حاجة لباكج إضافي.

> القيم الفعلية لجهازك (RAM/Flash/أخطاء logread/dmesg) تظهر من `sh /root/verify-all.sh`
> بعد الفلاش. لم أختلق أي رقم هنا.

---

## ثانياً: كيف تحصل على ملف `.bin` الحقيقي

### الطريقة A — GitHub Actions (موصى بها، آلية بالكامل)
الدفع إلى الفرع يشغّل الـ workflow تلقائياً. بعد انتهائه:
1. افتح **Actions → Build CR6606 Custom Firmware → آخر تشغيل**.
2. نزّل artifact باسم **`cr6606-custom-firmware`**، يحوي:
   - `openwrt-cr6606-custom-sysupgrade.bin`
   - `openwrt-cr6606-custom-sysupgrade.bin.sha256`
   - `manifest.txt` (= قائمة الحزم الفعلية بإصداراتها)
   - `packages.list`
   - `build.log`
3. الـ workflow فيه **بوابة أمان** ترفض البناء إن لم يكن `xiaomi_mi-router-cr6606`
   موجوداً في الـ ImageBuilder — فيستحيل أن تحصل على صورة لجهاز آخر.

### الطريقة B — بناء محلي بأمر واحد
على أي Linux فيه إنترنت إلى downloads.openwrt.org:
```sh
git clone <repo> && cd <repo>/firmware/cr6606
sh build-local.sh                 # أو: VERSION=24.10.2 sh build-local.sh
ls dist/                          # bin + sha256 + manifest + build.log
```

> **التحقق من الإصدار:** الافتراضي `OPENWRT_VERSION=24.10.0` في `build/profile.env`.
> غيّره لأحدث إصدار مستقر إن رغبت (مثلاً 24.10.2).

---

## ثالثاً + رابعاً: الواجهة و Dashboard

نستخدم **LuCI الرسمية كما هي** (Network/Wireless/Firewall/System/Services لم تُحذف ولم
تُكسَر) ونضيف فوقها قسماً جديداً **CR6606** في القائمة، بصفحات client-side حقيقية
مدعومة بمحرّك `rpcd` يقرأ بيانات فعلية من `ubus/iwinfo/ethtool/sysfs`.

**القائمة الجديدة:** `CR6606 → Dashboard · Quick Setup · Port Control · Wi-Fi Channels & Power · Mesh`.

**Dashboard** (`view/cr6606/dashboard.js`) يعرض ويُحدّث كل 5 ثوانٍ:
- **System:** الموديل، إصدار OpenWrt، Uptime، Load، RAM%، Flash%، الحرارة، شارات حالة كل خدمة، آخر أخطاء logread/dmesg.
- **WAN:** الحالة، البروتوكول (DHCP/Static/PPPoE)، IP، Gateway، DNS، مدة الاتصال، إجمالي التنزيل/الرفع، **زر Reconnect حقيقي** (`ifup wan`).
- **Ports:** كل منفذ منفصل: link، السرعة/Duplex (من ethtool)، الدور، VLANs (من bridge)، RX/TX، errors/drops.
- **Wi-Fi:** لكل راديو: SSID، القناة/العرض، **txpower المطلوب ← الفعلي من iwinfo**، Noise، عدد العملاء، زر **Restart Wi-Fi** وزر فتح صفحة Scan/Config.

> الألوان والترتيب محسّنان (بطاقات، شارات، رؤوس زرقاء). لم نستبدل LuCI بنظام غريب.

---

## خامساً: Quick Setup (مع Safe Apply + rollback)

`view/cr6606/quicksetup.js` — كل زر يستخدم **`uci.apply()`** المدمج في OpenWrt، أي
**apply-with-rollback**: إن قطعك التغيير، لا تؤكّد خلال العدّاد فيرجع الراوتر تلقائياً.
يحتوي:
- **Normal Router Mode** / **AP–Bridge Mode**
- **WAN DHCP** / **WAN Static** (IP/Mask/GW/DNS/MTU) / **PPPoE** (user/pass/MTU + MSS clamp تلقائي على zone wan)
- روابط مباشرة لـ **VLAN/Interfaces**، **Wireless/Mesh**، **Port Control**
- **Backup/Restore** (الصفحة الرسمية) + تذكير أمر backup CLI.

---

## سادساً: Port Control (حقيقي، بلا أزرار وهمية)

`view/cr6606/portcontrol.js` + المحرّك `rpcd cr6606 port_action`:
- **Enable / Disable / Restart** لكل منفذ → تنفيذ فوري عبر `ip link set dev <port> up/down`
  (مدعوم فعلياً على DSA)، والحالة **تُحفظ في `/etc/config/cr6606`** ويعيد تطبيقها
  `/etc/init.d/cr6606-ports` بعد كل reboot.
- عرض: Admin، Link، Speed/Duplex، Role، VLANs، RX/TX، Errors/Drops — كلها فعلية.

**تغيير LAN↔WAN: صراحةً غير مدعوم مباشرة على CR6606** — منفذ WAN عتاد منفصل (gmac1)
وأطراف LAN على سويتش mt7530، فلا يمكن لمنفذ LAN أن يصبح WAN عتادياً. **لم نضع زراً
وهمياً**؛ البديل المدعوم = VLAN + firewall zone (صفحة VLAN/Interfaces). مشروح داخل الصفحة.

---

## سابعاً: الخدمات والباكجات (مُقلَّمة، كلها تعمل)

القائمة في `build/packages.txt` (مبرّرة سطراً سطراً، بلا حشو):
LuCI+SSL، ترجمات ar/en، `wpad-mesh-mt76` (يستبدل wpad-basic ويفعّل mesh)،
`kmod-mt7915e`+firmware، PPPoE (`luci-proto-ppp ppp ppp-mod-pppoe`)، `luci-proto-ipv6`،
`ip-full` + `ip-bridge` (أمر `bridge` للإثبات) + `ethtool`، `nlbwmon`+luci (إجمالي
الاستهلاك)، `luci-app-firewall`. صفحات CR6606 تُشحن كملفات (بلا أي .ipk إضافي).

---

## ثامناً–عاشراً: Broadband / VLAN / Mesh

- **Broadband:** DHCP/Static/PPPoE من Quick Setup أو صفحة Interfaces الرسمية (MTU/MSS/NAT/zone)، إثبات: `ifstatus wan`.
- **VLAN (DSA / bridge VLAN filtering):** إنشاء/حذف/تعديل من Network→Interfaces→Devices→Bridge VLAN، Access/Trunk، DHCP وzone لكل VLAN، إثبات: `bridge vlan show`. (لا نكسر منفذ الإدارة لأننا لا نعيد بناء الجسر في الإعدادات الافتراضية.)
- **Mesh:** مدعوم فعلياً (mt7915 + wpad-mesh-mt76). صفحة Mesh تعرض الدعم والـ peers. التفعيل من Network→Wireless (Mode=802.11s، Mesh ID، SAE).

---

## الحادي عشر: Wi-Fi و txpower (الصدق الكامل)

الإعداد المطبَّق في `files/etc/uci-defaults/99-cr6606-custom` على **كل** راديو:
```
option country 'US'
option txpower '30'
```
**القيمة الفعلية = min(30، حد US التنظيمي، حد لوحة mt7915)** وتُقرأ حيّة من `iwinfo`.
لن نكتب "30 فعلي" إلا إذا أظهرته iwinfo عندك. **الإثبات الكامل لكل قناة:**
```sh
sh /root/verify-wifi-channels.sh
```
يطبع: القنوات التي بلغت 30، التي لم تبلغ، أعلى قيمة فعلية لكل قناة، وأفضل قناة للثبات.
5GHz **غير محصور على 149** (افتراضياً ch36 UNII-1، وكل القنوات تطلب 30).

---

## الثاني عشر: الإعدادات الافتراضية بعد الفلاش
LAN `192.168.100.1` · Hostname `CR6606-Custom` · DHCP server مفعّل · WAN DHCP · قوالب
PPPoE/Static جاهزة في Quick Setup · Firewall/NAT + software flow-offload · LuCI(HTTPS) ·
SSH(Dropbear) · Wi-Fi 2.4G+5G مفعّل (SSID: `CR6606-Custom` / `CR6606-Custom-5G`) ·
country US · txpower 30(مطلوب) · Watchdog عتاد · Health Check مفعّل.

> 🔐 **مهم:** كلمة مرور Wi-Fi الافتراضية `Cr6606-Change-Me` — **غيّرها فوراً** من
> Network→Wireless أو Quick Setup. وكلمة مرور root تُضبط عند أول دخول LuCI.

---

## الثالث عشر: تحليل التعليق/الـ reboot (وحلولها هنا)
| العَرَض | المعالجة في هذا البناء |
|---|---|
| kernel panic | قسم `crash`/`crash_log` يحفظ الأثر؛ راجع `dmesg`/logread عبر verify-all |
| OOM | Health Check يُسقط caches؛ حزم مُقلَّمة |
| Wi-Fi/mt76 crash | Health Check يكتشف ويعيد `wifi up` |
| switch/DSA errors | إبقاء تهيئة اللوحة؛ عدم كسر الجسر |
| watchdog reset | watchdog عتاد يديره procd |
| storage full | تنبيه Health Check عند ≥90% |
| bad config | Safe Apply + rollback في كل تغيير شبكي |
| broken packages | قائمة حزم رسمية مثبّتة من ImageBuilder |

لا نستخدم **إعادة تشغيل مجدولة** كحل (حسب طلبك) — المعالجة موضعية.

---

## الرابع عشر: سكربتات الفحص (داخل `/root/`)
`verify-all.sh` · `verify-ports.sh` · `verify-wifi.sh` · `verify-wifi-channels.sh` · `verify-services.sh`
— كلها تُشحن وتُضبط تنفيذية، وتطبع حقائق جهازك فقط.

---

## الخامس عشر–العشرون: التسليم، الفلاش، Recovery، Checklist

### Backup قبل الفلاش (إلزامي)
```sh
sysupgrade -b /tmp/backup-cr6606.tar.gz
# انسخه لجهازك:  scp root@192.168.100.1:/tmp/backup-cr6606.tar.gz .
```

### الفلاش (تحقق من اسم/SHA256 أولاً)
```sh
sha256sum /tmp/openwrt-cr6606-custom-sysupgrade.bin   # طابقه مع ملف .sha256
sysupgrade -v -n /tmp/openwrt-cr6606-custom-sysupgrade.bin
```
> `-n` = بدون الاحتفاظ بالإعدادات (تثبيت نظيف). لإبقاء إعداداتك احذف `-n`.
> ⚠️ **أمر خطر:** `sysupgrade` يعيد كتابة قسم النظام — لا تقطع الكهرباء أثناءه.

### Recovery إذا فشل الفلاش (CR6606)
1. **OpenWrt failsafe:** عند الإقلاع اضغط زر reset عند وميض LED، ادخل `192.168.1.1`
   عبر telnet، ثم `firstboot` أو أعد الفلاش.
2. **MTD recovery من failsafe/SSH:** أعد `sysupgrade` للصورة الصحيحة (CR6606 فقط).
3. **استرجاع الإعدادات:** `sysupgrade -r /tmp/backup-cr6606.tar.gz` ثم `reboot`.
4. **TFTP/uart (ملاذ أخير):** Xiaomi stock recovery أو uart؛ **لا تلمس Bootloader/Factory**.

### Checklist بعد الفلاش
```sh
sh /root/verify-all.sh            # board/release/ram/flash/services/logs
sh /root/verify-services.sh       # uhttpd/dropbear/dnsmasq/firewall/network/odhcpd/watchdog
sh /root/verify-ports.sh          # حالة/سرعة/RX-TX/errors/VLAN لكل منفذ
sh /root/verify-wifi.sh           # iwinfo/reg/iw dev/wifi status
sh /root/verify-wifi-channels.sh  # المطلوب مقابل الفعلي 30 لكل قناة
bridge vlan show                  # إثبات VLAN
ifstatus wan                      # إثبات Broadband
```
- [ ] دخول LuCI على `https://192.168.100.1`
- [ ] غُيِّرت كلمة مرور root وكلمة مرور Wi-Fi
- [ ] WAN متصل (`ifstatus wan`)
- [ ] الراديوهان يعملان وتظهر قيمة txpower الفعلية في iwinfo
- [ ] `verify-services` كلها up
- [ ] backup محفوظ خارج الراوتر

---

### بنية الملفات
```
firmware/cr6606/
├── build/profile.env            # target/subtarget/profile (CR6606 only)
├── build/packages.txt           # قائمة الحزم المُقلَّمة
├── build-local.sh               # بناء محلي بأمر واحد
├── files/                       # overlay يُدمج في الـ rootfs
│   ├── etc/uci-defaults/99-cr6606-custom
│   ├── etc/config/cr6606
│   ├── etc/init.d/{cr6606-health,cr6606-ports}
│   ├── root/{verify-all,verify-ports,verify-wifi,verify-wifi-channels,verify-services,cr6606-healthcheck}.sh
│   ├── usr/libexec/rpcd/cr6606                 # محرّك الواجهة (بيانات/أوامر حقيقية)
│   ├── usr/share/rpcd/acl.d/luci-app-cr6606.json
│   ├── usr/share/luci/menu.d/luci-app-cr6606.json
│   └── www/luci-static/resources/view/cr6606/*.js   # Dashboard/QuickSetup/PortControl/WifiChannels/Mesh
└── README.md
.github/workflows/build-cr6606-firmware.yml          # يبني الـ .bin الحقيقي
```
