# مدير الكروت — CardManagerApp

نظام أندرويد متكامل لإنشاء وطباعة وإدارة كروت هوتسبوت/يوزر منجر ميكروتك،
بواجهة عربية RTL، مع لوحة تراخيص منفصلة للمطوّر.

## الحزمة التقنية
- Kotlin 1.9.22 + Jetpack Compose (Material 3)، minSdk 26، compileSdk 34
- نكهتان في تطبيق واحد: `subscriber` (مدير الكروت) و `admin` (لوحة التراخيص)
  تتشاركان `src/main`؛ كود كل نكهة في `src/subscriber` و `src/admin`
- RouterOS API عبر `me.legrange:mikrotik:3.0.7`
- Firebase Firestore + Auth (مُهيأ يدوياً في `data/Backend.kt`، معطّل حتى تُملأ
  `data/BackendConfig.kt`)
- طباعة PDF عبر `android.graphics.pdf` (رسم متجهات مباشر)، حرارية عبر
  DantSu ESCPOS 3.3.0

## البنية
- `mikrotik/MikrotikClient.kt` — كل أوامر الراوتر (جلسة دائمة + pipeline + count-only)
- `data/Store.kt` — الحالة والتخزين (json ذري tmp+rename مع نسخة .bak)
- `data/SyncEngine.kt` — المزامنة التلقائية الدورية (لا أزرار جلب)
- `data/Backend.kt` — الربط السحابي الحي أدمن↔مشترك
- `license/` — ترخيص ECDSA P-256 مقفول على بصمة الجهاز، رموز Base32
- `print/` — PrintEngine الصامد (يستأنف ولا يفشل)، PdfExporter، ThermalPrinter
- `render/CardRenderer.kt` — رسم الكرت (نصوص/جدول/QR)
- `ui/screens/` — الشاشات؛ `ui/theme` و `ui/components` — نظام التصميم

## الأوامر
- لا يوجد gradlew محلي ولا Android SDK في بيئة التطوير — **التحقق عبر CI فقط**:
  ادفع إلى الفرع، وGitHub Actions (`.github/workflows/build-card-app.yml`)
  يبني `assembleSubscriberDebug assembleAdminDebug` وينشر APK في إصدار
  `card-manager-latest` (~5 دقائق، وأول بناء بعد تغيير التبعيات ~15 دقيقة)
- افحص النتيجة عبر mcp__github__actions_* وتحديث `updated_at` في الإصدار
  (ردود GitHub API تُخزّن مؤقتاً — لا تثق بحالة "in_progress" قديمة)

## قواعد ميكروتك الحرجة (مصدر أخطاء متكرر)
- صيغة أوامر المكتبة `key=value` وليس `=key=value`
- كل قيمة تُلف بـ `q()` — المحلل يقطع عند المسافة ويرفض الأسطر الجديدة
- `count-only` يعيد العدد في حقل `ret` (متزامن فقط — المستمع غير المتزامن لا يستلمه)
- القيم المنطقية في الاستعلامات `true/false` وليست `yes/no`
- **v6 يوزر منجر**: المسار `/tool/user-manager/...`، حقل الدخول `username`
  (وليس `name`)، الباقة بعد التفعيل في `actual-profile` (لا يوجد `group`)،
  و`customer` يُقرأ من جدول العملاء لا يُفترض `admin`
- v7: `/user-manager/...`، الحقل `name`، وربط الباقة في جدول `user-profile`
- فحص v7 بـ `print count-only` وليس بجلب القائمة كاملة
- كل عملية عبر `onRouter` (جلسة دائمة + قفل) — لا تفتح اتصالات خاصة

## قواعد المنتج
- عربي RTL في كل واجهة؛ رسائل الأخطاء عربية مفهومة تشرح ماذا يفعل المستخدم
- **المزامنة تلقائية** — أي ميزة جديدة تعتمد بيانات الراوتر تنتظر SyncEngine
  ولا تضيف زر جلب إجباري
- الطباعة لا تقول «فشل» ولا تعيد من البداية — أي خلل يُستأنف من نقطة التوقف
- الرفع بالدفعات عبر `pipeline` (نافذة 128 + جولتا إعادة صامتة) — لا حلقات
  أمرٍ-بعد-أمر
- الكروت المحلية غير المرفوعة لا تضيع أبداً (mergeRouterCards) ولا تُرفع مرتين
  (حقل uploaded)
- المطوّر: «المهندس علي واقص» وواتساب 776831921 — لا تغيّرهما

## قواعد الترخيص
- المفتاح Base32 بأبجدية `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` — **لا تعبث بدالة
  normalize**: استبدالات الأحرف الملتبسة سبق أن أسقطت حرف L وأفشلت 97% من المفاتيح
- رمز الجهاز `XXXX-XXXX`؛ أي إدخال يمر عبر `LicenseLink.extractDeviceCode`
- حساب واحد = جوال واحد (فحص boundDevice قبل الإصدار)

## تعريف الإنجاز
1. الترجمة تنجح لكلا النكهتين في CI
2. الإصدار `card-manager-latest` تحدّث فعلاً (تحقق من updated_at)
3. لا رجوع في متطلبات المستخدم المثبتة في docs/REQUIREMENTS-TRACEABILITY.md
4. أي إصلاح لعطل أبلغ عنه المستخدم يُذكر له مع رابط التنزيل

## ممنوعات
- لا تدّعِ نجاح بناء لم تتحقق منه من CI
- لا أزرار وهمية أو شاشات فارغة «قيد الإنشاء»
- لا تسجّل كلمات مرور الراوتر أو مفاتيح الترخيص في السجلات
- لا تدفع لفرع غير `claude/user-card-management-app-6nhwlj`
