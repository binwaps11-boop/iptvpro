package com.binwaps.cardmanager.data

/**
 * إعدادات الربط السحابي (Firebase) — تُملأ مرة واحدة.
 *
 * كيف تحصل على القيم (مجاناً، ٥ دقائق):
 * 1) افتح https://console.firebase.google.com وأنشئ مشروعاً جديداً.
 * 2) داخل المشروع: Build ← Firestore Database ← Create database (ابدأ بوضع الاختبار Test mode).
 * 3) Build ← Authentication ← Sign-in method ← فعّل "Anonymous".
 * 4) Project settings (أيقونة الترس) ← تبويب General ← Your apps ← أضف تطبيق ويب (</>).
 *    ستظهر لك قيم firebaseConfig — انسخها هنا:
 *      apiKey, appId, projectId  (والبقية اختيارية).
 * 5) الصق القيم بدل الفراغات أدناه وابنِ التطبيق. بمجرد امتلاء apiKey و projectId
 *    يعمل الربط الحي والدردشة والمزامنة تلقائياً على تطبيقَي المشترك والأدمن معاً.
 *
 * ملاحظة: التطبيق نفس المشروع للاثنين — لا حاجة لمشروعين. اترك القيم فارغة
 * ليعمل التطبيق دون سحابة (بالطريقة القديمة عبر الروابط).
 */
object BackendConfig {
    const val API_KEY = ""
    const val APP_ID = ""
    const val PROJECT_ID = ""
    // اختيارية — تُملأ إن ظهرت في إعدادات مشروعك
    const val SENDER_ID = ""      // messagingSenderId
    const val STORAGE_BUCKET = "" // storageBucket

    /** هل الربط السحابي مُهيَّأ؟ */
    val enabled: Boolean get() = API_KEY.isNotBlank() && PROJECT_ID.isNotBlank() && APP_ID.isNotBlank()

    /**
     * خادم التراخيص (مجلد license-server في المستودع).
     * هو قاعدة البيانات التي تربط الحساب + رقم الجوال + بصمة الجهاز بالترخيص.
     * اتركه فارغاً ليعمل التطبيق بالترخيص المحلي فقط.
     */
    // خادم التراخيص معطّل مؤقتاً: التطبيق يجب أن يفتح ويعمل (جلب/رفع/طباعة)
    // بلا أي اعتماد على خادم خارجي. لتفعيل الترخيص أونلاين لاحقاً ضع عنوان
    // الخادم هنا (مثل http://IP:8090). فارغ = وضع محلي كامل بلا حجب.
    const val LICENSE_SERVER = ""

    /**
     * المفتاح العام للخادم — يطبعه `install.sh` جاهزاً للصق هنا.
     *
     * **املأه.** تركه فارغاً يعني أن التطبيق يجلب المفتاح من الخادم عند أول
     * اتصال ويثبّته (TOFU)، وفوق HTTP هذه لحظة يستطيع فيها وسيط على الشبكة
     * زرع مفتاحه فتُقبل تراخيصه المزوّرة بعدها. ملؤه هنا يُغلق الباب لأن
     * المفتاح لا يمرّ بالشبكة أصلاً.
     */
    const val SERVER_PUBLIC_KEY =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEgN+H22nSKhPPMdaHak5Uvx3D/9SMjNeBzHcl5Gk6UtpSIHger3U3snwahjDoyl+750plA2LwinXcX4PjbxufvQ=="

    val licenseServerEnabled: Boolean get() = LICENSE_SERVER.isNotBlank()
}
