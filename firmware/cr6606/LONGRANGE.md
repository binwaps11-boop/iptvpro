# CR6606 — نسختان لتحسين المدى وقوة الإشارة وسرعة الربط

مبني على OpenWrt stable الرسمي، target `ramips/mt7621`، درايفر `mt76/mt7915`،
لجهاز **Xiaomi CR6606 فقط**. بدون لمس MAC / EEPROM / caldata، وبدون reghack خطير.

## ⚠️ الحقيقة عن الباور والمدى (اقرأها أولاً)
- العتاد **2×2** على البندين (MT7905DAN + MT7975DN، فئة AX1800). **2×2 هو الحد العتادي** —
  لا يوجد chain مخفي إضافي. النسختان تستخدمان كل السلاسل افتراضياً (لا قناع antenna).
- `txpower` المطلوب (30 أو 35) **يقصّه الدرايفر** إلى `min(المطلوب، حد الدولة، حد caldata)`.
  بما أننا لا نلمس caldata، فالقيمة الفعلية لن تتجاوز سقف اللوحة. **`iwinfo` يقول الحقيقة.**
- السوفت الرسمي يعطي ~20 dBm غالباً لأن regdomain مقيّد. ضبط **country=US + طلب الحد الأقصى**
  يرفع الفعلي إلى سقف caldata (عادةً أعلى من 20) = **تحسّن حقيقي**، وليس رقماً وهمياً.
- مصادر التحسّن الحقيقية: **country صحيح + HE20 على 2.4 (مدى أفضل) + أفضل قناة +
  149/UNII-3 على 5 + 2×2 + flow offload (sw+hw)**.

## النسختان

### 1) `openwrt-cr6606-clean-stable-longrange-sysupgrade.bin` — اليومية
| | |
|---|---|
| country | US |
| txpower | 30 (طلب الحد الأقصى؛ الفعلي = سقف caldata) |
| 2.4GHz | AX/N، **HE20**، قناة **auto (ACS بين 1/6/11)**، SSID `Xiaomi-2G` |
| 5GHz | **AX/HE80**، قناة **149** (UNII-3، بلا DFS، أعلى باور)، SSID `Xiaomi-5G` |
| السلاسل | 2×2 كاملة (بلا قناع) |
| التعجيل | flow offloading **sw + hw** |
| تشفير | WPA2 (psk2) — الأكثر توافقاً/ثباتاً |
| LuCI/SSH | مفعّلان |

### 2) `openwrt-cr6606-power-test-sysupgrade.bin` — للاختبار فقط
- نفس إعداد النسخة النظيفة، لكن **txpower = 35** (طلب System/Driver فوق الحد) **لقياس**
  هل يتغيّر شيء — وغالباً لا يتجاوز سقف caldata (الدرايفر يقصّه).
- **System/Driver وليس RF حقيقي.** لا كتابة على caldata/EEPROM/MAC.
- يضيف marker في dmesg: `CR6606-POWER-TEST` (تأكيد أنك على هذه النسخة فقط).
- استخدمها لتقارن `iwinfo` و`wifi-perf.sh` مع النسخة النظيفة. إن لم يتحسّن
  signal/bitrate/retries فعلياً → ابقَ على النظيفة (هذا هو الصدق الذي طلبته).

## كلاهما يحتوي
- Dashboard / Quick Setup / Port Control / Wi-Fi pages (من المشروع الأساسي).
- سكربتات الفحص: `/root/wifi-perf.sh`، `/root/wifi-scan.sh`، و`verify-*.sh`.

## أوامر الفحص بعد التفليش
```sh
sh /root/wifi-scan.sh        # iwinfo + iw phy + station/survey dump + dmesg(mt76|power|cal|CR6606)
sh /root/wifi-perf.sh        # signal / tx-rx bitrate / retries / failed / channel-busy / clients / DL-UL لكل عميل
# أو يدوياً:
iwinfo ; iw phy
iw dev wlan0 station dump ; iw dev wlan1 station dump
iw dev wlan0 survey dump   ; iw dev wlan1 survey dump
dmesg | grep -Ei "mt76|mt7915|wifi|power|eeprom|cal|CR6606"
```
على power-test تأكد من: `dmesg | grep CR6606` → يظهر `CR6606-POWER-TEST`.

## التفليش
```sh
sysupgrade -b /tmp/backup-cr6606.tar.gz                                   # backup أولاً
sha256sum -c openwrt-cr6606-clean-stable-longrange-sysupgrade.bin.sha256  # تحقق
sysupgrade -v -n /tmp/openwrt-cr6606-clean-stable-longrange-sysupgrade.bin
# أو نسخة الاختبار:
sysupgrade -v -n /tmp/openwrt-cr6606-power-test-sysupgrade.bin
```

## Rollback / Recovery
- لديك backup: `sysupgrade -r /tmp/backup-cr6606.tar.gz && reboot`.
- للرجوع للنسخة الأخرى: افلش الـ `.bin` الآخر بنفس أمر sysupgrade.
- فشل التفليش: OpenWrt failsafe (زر reset عند الإقلاع → telnet 192.168.1.1 → `firstboot`/إعادة sysupgrade). **لا تلمس Bootloader/Factory.**

## الفرق باختصار
| | clean-stable-longrange | power-test |
|---|---|---|
| الاستخدام | يومي مستقر | اختبار فقط |
| txpower المطلوب | 30 | 35 |
| الفعلي (RF) | سقف caldata | **نفسه غالباً** (يُقصّ) |
| marker dmesg | لا | `CR6606-POWER-TEST` |
| caldata/EEPROM/MAC | لا يُلمس | لا يُلمس |
