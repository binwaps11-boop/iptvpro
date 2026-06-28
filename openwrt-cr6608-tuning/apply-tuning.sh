#!/bin/sh
# ============================================================================
#  ضبط أداء الواي-فاي + إصلاح مشاكل الجوال  |  Wi-Fi tuning for Xiaomi CR6608
#  Target : OpenWRT 24.10 - Xiaomi Mi Router CR6608 (AX1800, mt76)
#
#  شغّل هذا السكربت على الراوتر نفسه عبر SSH:
#    1) انسخ الملف للراوتر:   scp apply-tuning.sh root@192.168.1.1:/tmp/
#    2) ادخل بالـ SSH:        ssh root@192.168.1.1
#    3) شغّله:                sh /tmp/apply-tuning.sh
#
#  السكربت آمن وقابل لإعادة التشغيل (idempotent). يطبع نسخة احتياطية أولاً.
# ============================================================================

set -e

# ---------------------------------------------------------------------------
#  *** غيّر هذي القيمة لرمز دولتك ***  | SET YOUR COUNTRY CODE
#  رمز دولتك يفتح أعلى باور وأفضل قنوات مسموحة قانونياً.
#  أمثلة: SA السعودية - AE الإمارات - EG مصر - IQ العراق - 00 العالم(الأكثر تقييداً)
# ---------------------------------------------------------------------------
COUNTRY="SA"

echo "==> نسخة احتياطية من الإعدادات الحالية في /tmp/wireless.bak"
cp /etc/config/wireless /tmp/wireless.bak 2>/dev/null || true

# ---------------------------------------------------------------------------
#  اكتشاف الراديوهات تلقائياً (radio0 / radio1) وتحديد أيهما 2.4G وأيهما 5G
# ---------------------------------------------------------------------------
RADIO_24=""
RADIO_5=""
for r in $(uci show wireless | sed -n "s/^wireless\.\(radio[0-9]*\)=wifi-device/\1/p"); do
    band=$(uci -q get wireless.$r.band)
    hwmode=$(uci -q get wireless.$r.hwmode)
    if [ "$band" = "2g" ] || echo "$hwmode" | grep -q "g"; then
        RADIO_24="$r"
    elif [ "$band" = "5g" ] || echo "$hwmode" | grep -q "a"; then
        RADIO_5="$r"
    fi
done
echo "==> 2.4GHz = ${RADIO_24:-غير موجود} | 5GHz = ${RADIO_5:-غير موجود}"

# ---------------------------------------------------------------------------
#  راديو 5GHz : أقصى سرعة وثبات (هذا اللي يعطيك ~300 Mbit/s مع إشارة جيدة)
# ---------------------------------------------------------------------------
if [ -n "$RADIO_5" ]; then
    R=$RADIO_5
    uci set wireless.$R.country="$COUNTRY"
    uci set wireless.$R.htmode='HE80'        # عرض قناة 80MHz = أعلى تدفق (مفتاح الـ300)
    uci set wireless.$R.channel='auto'       # أو ضع قناة ثابتة نظيفة مثل 36 أو 149
    uci set wireless.$R.cell_density='0'      # لا تتجاهل العملاء البعيدين
    uci set wireless.$R.disabled='0'
    uci -q delete wireless.$R.legacy_rates   # لا rates قديمة بطيئة
    # خيارات mt76 لتحسين الأداء (تُتجاهل بأمان إن لم تُدعم)
    uci set wireless.$R.mu_beamformer='1' 2>/dev/null || true
    uci set wireless.$R.beamformer='1'    2>/dev/null || true
fi

# ---------------------------------------------------------------------------
#  راديو 2.4GHz : 20MHz لتقليل التداخل (شكوى الجوال) + ثبات أعلى
# ---------------------------------------------------------------------------
if [ -n "$RADIO_24" ]; then
    R=$RADIO_24
    uci set wireless.$R.country="$COUNTRY"
    uci set wireless.$R.htmode='HE20'        # 20MHz = أقل تداخل بالباند المزدحم
    uci set wireless.$R.channel='auto'       # أو ثبّت 1 / 6 / 11
    uci set wireless.$R.cell_density='0'
    uci set wireless.$R.disabled='0'
fi

# ---------------------------------------------------------------------------
#  كل شبكات الواي-فاي (wifi-iface): سلاسة + roaming أنعم للجوال
# ---------------------------------------------------------------------------
for IF in $(uci show wireless | sed -n "s/^wireless\.\(@wifi-iface\[[0-9]*\]\)=wifi-iface/\1/p"); do
    uci set wireless.$IF.wmm='1'             # جودة الخدمة (لازم للسرعة العالية)
    uci set wireless.$IF.ieee80211k='1'      # مساعدة الجوال يختار أفضل نقطة
    uci set wireless.$IF.ieee80211v='1'      # انتقال أنعم بين الباندات
    uci set wireless.$IF.disassoc_low_ack='0' 2>/dev/null || true  # لا يفصل عند ضعف لحظي
done

uci commit wireless

# ===========================================================================
#  إصلاح واجهة الإدارة LuCI : الصفحات + الواجهات + خانات الإدخال على الجوال
# ===========================================================================
HAVE_NET=0
if opkg update >/dev/null 2>&1; then HAVE_NET=1; fi
[ "$HAVE_NET" = 1 ] && echo "==> الإنترنت متاح، سيتم تثبيت/تحديث الحزم الناقصة" \
                    || echo "==> لا إنترنت: سيُطبّق ما أمكن بدون تثبيت حزم"

# --- 1) قالب خفيف ومتجاوب مع الجوال (يحل بطء/تكسّر الصفحات) ---
#     القالب الافتراضي ثقيل أحياناً على المتصفح بالجوال. material أخف وأوضح.
if [ "$HAVE_NET" = 1 ]; then
    if ! opkg list-installed | grep -q luci-theme-material; then
        opkg install luci-theme-material >/dev/null 2>&1 \
            && echo "    تم تثبيت قالب material" \
            || echo "    تعذّر تثبيت material - سيبقى القالب الحالي"
    fi
fi
# اجعله الافتراضي إن وُجد
if [ -d /www/luci-static/material ] || opkg list-installed 2>/dev/null | grep -q luci-theme-material; then
    uci -q set luci.themes.Material='/luci-static/material'
    uci -q set luci.main.mediaurlbase='/luci-static/material'
fi

# --- 2) حزم اللغة: إنجليزي (لا يتحول) + عربي إن رغبت ---
uci -q set luci.main.lang='en'      # غيّرها إلى 'ar' لو تبي الواجهة عربية
if [ "$HAVE_NET" = 1 ]; then
    for pkg in luci-i18n-base-en luci-i18n-base-ar; do
        opkg list-installed | grep -q "$pkg" || opkg install "$pkg" >/dev/null 2>&1 \
            && echo "    حزمة اللغة: $pkg جاهزة"
    done
fi
uci -q commit luci

# --- 3) خادم الويب uhttpd: تسريع التحميل + منع توقف خانات الإدخال ---
#     gzip يصغّر الصفحات، والمهلات الأطول تمنع فشل حفظ النماذج على اتصال بطيء.
uci -q set uhttpd.main.gzip='1'
uci -q set uhttpd.main.script_timeout='120'   # وقت كافٍ لتنفيذ صفحات الإعدادات الثقيلة
uci -q set uhttpd.main.network_timeout='60'    # لا يقطع أثناء كتابة/حفظ الإدخالات
uci -q set uhttpd.main.max_requests='5'        # طلبات متوازية أكثر = صفحات أسرع
uci -q set uhttpd.main.max_connections='100'
uci -q set uhttpd.main.http_keepalive='20'
uci -q commit uhttpd
/etc/init.d/uhttpd restart 2>/dev/null || true

# --- 4) مهلة جلسة أطول حتى لا تُطرد وأنت تعبّي الحقول على الجوال ---
#     الافتراضي 5 دقائق؛ نرفعها لساعة لتفادي "انتهت الجلسة" وضياع الإدخالات.
uci -q set rpcd.@login[0].timeout='3600' 2>/dev/null \
    && uci -q commit rpcd && /etc/init.d/rpcd restart 2>/dev/null || true

# --- 5) تنظيف الكاش حتى تظهر الواجهة الجديدة فوراً ---
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
echo "==> تم ضبط واجهة الإدارة (قالب + لغة + خادم + جلسة)"

# ---------------------------------------------------------------------------
#  تطبيق إعدادات الواي-فاي
# ---------------------------------------------------------------------------
echo "==> إعادة تشغيل الواي-فاي لتطبيق الإعدادات"
wifi reload

echo ""
echo "============================================================"
echo " تم التطبيق. تحقق من النتيجة بالأمر:"
echo "   iw dev | grep -A8 Interface ; iwinfo"
echo " لاستعادة القديم:  cp /tmp/wireless.bak /etc/config/wireless ; wifi reload"
echo "============================================================"
