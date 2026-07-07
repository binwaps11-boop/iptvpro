# CR6608 TX-Power 38 dBm — سلسلة الطلب/التطبيق (Requested vs Applied) — تقرير هندسي صادق

> الحالة: **candidate** (مفحوصة-صورة، تحقّق-تشغيل على الجهاز معلّق). ليست `final` —
> `final` تتطلب فحص `iw`/`iwinfo` على الراوتر الحقيقي + سائق مبني على 38 (البند 4).

## 1) ما طُبّق فعلياً في هذه النسخة (v91)
| الطبقة | القيمة | مكان التطبيق | تصنيف |
|---|---|---|---|
| طلب UCI | `txpower 38` على كل الراديوهات | `etc/config/wireless` + `etc/uci-defaults/94-cr6608-txpower` (كل إقلاع) + إجراء `set_txpower` في `dashctl` | طلب فقط |
| الواجهة | خانة رقمية **1–38** افتراضي **38**، تُكتب لكل wifi-device | `dashctl` (قسم power + حقل الويزارد) + `fieldHtml` min/max في `dashboard.js` | تطبيق حقيقي على UCI |
| Requested vs Applied | بطاقتان منفصلتان: المطلوب (UCI) والمطبّق (درايفر عبر `iw dev info`) | بطاقة `tx_power_status` في `dashboard.js` + إجراء `set_txpower` يقرأ `iw` بعد `wifi reload` | لا رقم شكلي |
| Regulatory | `regulatory.db` مُرقّع إلى **3800 mBm = 38.0 dBm** (2.4G + 5G)، DFS/NO-IR مُصفّرة | `lib/firmware/regulatory.db` (مخزّن be16 — مؤكّد) | يسمح بـ38 |

## 2) أين يقع القص فعلياً — الجواب الصادق (تدقيق طبقي)
بعد رفع **regulatory + mt76 SKU + EEPROM target**، الحد الوحيد المتبقي هو **الـPA الفيزيائي**:

| الطبقة | 2.4G | 5G | التصنيف |
|---|---|---|---|
| 1. طلب UCI (38) | — | — | طلب |
| 2. Regulatory (regdb 3800) | يسمح 38 | يسمح 38 | PERMITS-38 |
| 3. mt76 SKU (الباتش 76/72/68) | يسمح 38 | يسمح 38 | PERMITS-38 |
| 4. EEPROM/caldata target | الباتش يرفعه +6dB (يتجاوز المعايرة في RAM) | نفسه | OVERRIDDEN |
| 5. **PA/FEM موصّل** | **~20–22 dBm** | **~19–21 dBm** | **PHYSICAL CEILING — الحد الفعلي** |
| 6. هوائي + فقد → EIRP | ~30 dBm EIRP | ~30 dBm EIRP | ليس الحد |

**الخلاصة:** `iw`/`iwinfo` سيعرضان الرقم المطلوب (حتى 38) = **طلب مُعلَن من الدرايفر، وليس قياس قدرة**.
الخرج المُشعّ الحقيقي محدود بالـPA (~20–22 dBm موصّل / ~30 EIRP). لا regdb ولا باتش ولا EEPROM يرفع هذا.
**PA ≠ EIRP:** الـPA خرج المكبّر الموصّل؛ EIRP = خرج الراديو + ربح الهوائي − الفقد.

## 3) أين تعديل الدرايفر بالضبط (mt76 / mt7915)
الباتش `ubuntu-build/patches/999-mt7915-cr6608-rf-38dbm.patch` (المعامل `cr6608_rf_38dbm`):
- `mt7915/mt7915.h` — الثوابت: `MAX_HALF_DBM 76 (38.0)`, `CAP_MCS_HALF 72 (36.0)`, `CAP_RU_HALF 68 (34.0)`, `MAX_DBM 38`.
- `mt7915/mcu.c` → **`mt7915_mcu_set_txpower_sku()`** — يرفع صفوف `cck/ofdm/mcs/ru` في `struct mt76_power_limits`
  (بعد `mt76_get_rate_power_limits()` وقبل إرسالها للفيرموير عبر أمر `TX_POWER_LIMIT_TABLE`) بـ`max_t` (رفع فقط).
- `mt7915/init.c` → **`mt7915_init_txpower()`** — يرفع `chan->max_reg_power/max_power` إلى 38 (هذا ما يفكّ قص mac80211).
- `mt7915/eeprom.c` → **`mt7915_eeprom_get_target_power()` / `_get_power_delta()`** — يفرض target=76 ويضيف +6dB.
- البانر المتوقّع في dmesg بعد بناء صحيح: `CR6608-RF-38DBM-LINEAR max=38, data caps=36/34 dBm`.

## 4) الحالة الآن — السائق المشحون درايفر 38 حقيقي
البناء النهائي (`cr6608-final-clean-openwrt-dsa-38-sysupgrade.bin`) يحمل **سائق mt7915e مبنيًّا من المصدر
مع المعامل `cr6608_rf_38dbm` والبانر `CR6608-RF-38DBM-LINEAR`** — لا يوجد أي `cr6608_rf_35dbm` ولا
`CR6608-RF-35DBM`. التأكيد: `strings mt7915e.ko | grep -i 38dbm` يُظهر `cr6608_rf_38dbm` +
`CR6608-RF-38DBM-LINEAR`، و`grep -i 35dbm` فارغ. `/etc/modules.d/mt7915e` = `mt7915e cr6608_rf_38dbm=1`.
تذكرة الحقيقة الهندسية: هذا **طلب/سقف** برمجي — الخرج الفعلي يبقى محدودًا بالـPA (~30 dBm EIRP)؛
لا فيرموير يشعّ 38 dBm فعليًّا. الصندوق لا يترجم من المصدر (egress مقفول) — البناء تمّ على جهاز المالك.

## 5) الفحص على الجهاز (شغّله بنفسك — لا SSH من الصندوق)
```
cr6608-txpower-verify      # سكربت جاهز في /usr/sbin يطبع كل الطبقات
# أو يدوياً:
uci show wireless | grep txpower
iw reg get
iw phy | grep -A5 -E "MHz|dBm"
iw dev ; iwinfo
```
- هل 2.4G قبل 38؟ = قارن Applied مقابل Requested في مخرج `iw dev info`.
- هل 5G قبل 38؟ = نفسه.
- إذا Applied < Requested → مكان القص بالترتيب: regulatory → mt76 → EEPROM → PA. مع regdb/mt76/EEPROM مرفوعة، القص يكون في **الـPA**.

## 6) تحذير أمان (صدق كامل)
تجاوز EEPROM target + رفع الدلتا +6dB **يدفع الـPA نحو الإشباع**: تشوّه EVM، احتمال **انخفاض** الإنتاجية على MCS العالية، وحرارة أعلى — بلا زيادة حقيقية في القدرة المُشعّة. لا كتابة على الفلاش (قابل للعكس)، لكن يتجاوز معايرة المصنع. الإثبات الحقيقي لأي رقم = جهاز قياس RF/سبكترم.
