package com.binwaps.cardmanager.license

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** حالة الترخيص الحالية للتطبيق */
sealed interface LicenseState {
    /** لم يُسجّل بريده بعد — يُطلب منه التسجيل لتبدأ التجربة */
    data object NeedsRegister : LicenseState
    /** التجربة المجانية جارية */
    data class Trial(val daysLeft: Int) : LicenseState
    data class Licensed(val plan: LicenseCore.Plan, val daysLeft: Int, val lifetime: Boolean) : LicenseState
    data object Expired : LicenseState
    /** انتهت التجربة — يطلب ترخيصاً */
    data object TrialEnded : LicenseState
    /** أوقفه مزوّد الخدمة عن بعد — يُرجّح فوق كل شيء بما فيه التجربة */
    data object Suspended : LicenseState
    /** ساعة الجهاز مُرجَعة للخلف — لا نمنح وقتاً حتى تُصحَّح */
    data object ClockInvalid : LicenseState
}

/**
 * يدير التسجيل والتجربة (أسبوع) والترخيص، والتحقق منه عند كل تشغيل.
 *
 * التدفق: المشترك يسجّل بريده (جيميل) ← تبدأ تجربة أسبوع تلقائياً ← بعد
 * الأسبوع تُقفل ويُطلب ترخيص عبر واتساب مزوّد الخدمة.
 *
 * التجربة مقيّدة بوقت موثوق (يمنع إرجاع الساعة). حذف التطبيق وإعادة تثبيته
 * يمسح التخزين المحلي، لذا القفل النهائي هو الترخيص المقفول على بصمة الجهاز
 * الذي يصدره مزوّد الخدمة — والبصمة لا تتغير بإعادة التثبيت.
 */
object LicenseManager {
    private const val PREFS = "license_store"
    private const val KEY_LAST_SEEN = "last_seen"
    private const val KEY_LICENSE = "license_key"
    private const val KEY_NAME = "customer_name"
    private const val KEY_PHONE = "customer_phone"
    private const val KEY_EMAIL = "customer_email"
    private const val KEY_TRIAL_START = "trial_start"
    // مصدرا إيقاف مستقلان — الأدمن عبر Firestore، وخادم التراخيص. لا يتشاركان
    // مفتاحاً واحداً: كان أي رد `active` من الخادم يمسح إيقافاً أصدره الأدمن.
    private const val KEY_SUSPENDED = "suspended_remote"
    private const val KEY_SUSPENDED_SERVER = "suspended_server"

    // حالة الحساب كما قررها خادم التراخيص (القرار الأعلى بعد الإيقاف)
    private const val KEY_ON_STATUS = "online_status"
    private const val KEY_ON_VALID = "online_valid"
    private const val KEY_ON_PLAN = "online_plan"
    private const val KEY_ON_DAYS = "online_days"
    private const val KEY_ON_REASON = "online_reason"
    private const val KEY_ON_AT = "online_at"
    private const val KEY_ON_GRACE = "online_grace_h"

    const val TRIAL_DAYS = 7
    private const val DAY_MS = 86_400_000L
    /** تسامح مع فروق ضبط الساعة الطبيعية قبل اعتبارها إرجاعاً متعمّداً */
    private const val CLOCK_SLACK_MS = 6 * 3600_000L

    private lateinit var appContext: Context

    private val _state = MutableStateFlow<LicenseState>(LicenseState.NeedsRegister)
    val state: StateFlow<LicenseState> get() = _state

    /** آخر رسالة سبب وصلت من الخادم — تُعرض للمستخدم كما هي */
    private val _reason = MutableStateFlow("")
    val reason: StateFlow<String> get() = _reason

    /** هل يجري تحقق أونلاين الآن؟ للواجهة فقط */
    private val _syncing = MutableStateFlow(false)
    val syncing: StateFlow<Boolean> get() = _syncing

    fun init(context: Context) {
        appContext = context.applicationContext
        LicenseServer.init(appContext)
        refresh()
    }

    private fun prefs() = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun deviceCode(): String = LicenseCore.deviceCode(appContext)

    fun savedLicense(): String = prefs().getString(KEY_LICENSE, "").orEmpty()

    fun customerName(): String = prefs().getString(KEY_NAME, "").orEmpty()

    fun setCustomerName(value: String) {
        prefs().edit().putString(KEY_NAME, value).apply()
    }

    fun customerPhone(): String = prefs().getString(KEY_PHONE, "").orEmpty()

    fun setCustomerPhone(value: String) {
        prefs().edit().putString(KEY_PHONE, value).apply()
    }

    fun customerEmail(): String = prefs().getString(KEY_EMAIL, "").orEmpty()

    /** هل سجّل بريده؟ */
    fun isRegistered(): Boolean = customerEmail().isNotBlank()

    /**
     * تسجيل البريد وبدء التجربة. يعيد رسالة خطأ أو null عند النجاح.
     * التجربة تبدأ مرة واحدة — لا تُصفَّر بإعادة إدخال بريد آخر.
     */
    fun register(email: String, name: String, phone: String = ""): String? {
        localValidation(email, name, phone)?.let { return it }
        saveIdentity(email, name, phone)
        refresh()
        return null
    }

    /** تحقق الحقول الثلاثة — يعيد رسالة الخطأ أو null */
    fun localValidation(email: String, name: String, phone: String): String? {
        if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$").matches(email.trim())) {
            return "أدخل بريداً صحيحاً مثل name@gmail.com"
        }
        if (name.trim().length < 3) return "أدخل اسمك كاملاً (٣ أحرف على الأقل)"
        // الجوال إلزامي: بدونه لا يمكن الوصول إليك لتسليم الترخيص أو دعمك
        if (phone.filter { it.isDigit() }.length !in 9..15) {
            return "أدخل رقم جوال صحيح (٩ إلى ١٥ رقماً)"
        }
        return null
    }

    private fun saveIdentity(email: String, name: String, phone: String) {
        val now = trustedNow()
        prefs().edit()
            .putString(KEY_EMAIL, email.trim())
            .putString(KEY_NAME, name.trim())
            .putString(KEY_PHONE, phone.filter { it.isDigit() })
            .apply()
        // التجربة تبدأ مرة واحدة — لا تُصفَّر بإعادة إدخال بريد آخر
        if (prefs().getLong(KEY_TRIAL_START, 0) <= 0) {
            prefs().edit().putLong(KEY_TRIAL_START, now).apply()
        }
    }

    /**
     * وقت موثوق: لا نقبل أبداً وقتاً أقدم مما رأيناه.
     *
     * المحاولة السابقة كانت تتجاهل الانحراف الكبير «حتى لا يقفل التطبيق بعد
     * قفزة خاطئة» — وهذا بالضبط ما يفتح الباب: إرجاع الساعة سنةً كان يُقبل
     * فتصير التجربة بلا نهاية. الآن الإرجاع الكبير يُعلَن كخلل ساعة
     * (ClockInvalid) ومخرجه اتصال واحد بالإنترنت يعيد ضبط المرجع من الخادم.
     */
    private fun trustedNow(): Long {
        val now = System.currentTimeMillis()
        val lastSeen = prefs().getLong(KEY_LAST_SEEN, 0)
        val trusted = maxOf(now, lastSeen)
        if (trusted > lastSeen) prefs().edit().putLong(KEY_LAST_SEEN, trusted).apply()
        return trusted
    }

    /** هل أُرجعت ساعة الجهاز للخلف بما يفسد حساب المدة؟ */
    private fun clockRolledBack(): Boolean =
        rolledBack(System.currentTimeMillis(), prefs().getLong(KEY_LAST_SEEN, 0))

    /** منطق كشف إرجاع الساعة — نقي ليُختبر بلا جهاز */
    internal fun rolledBack(now: Long, lastSeen: Long, slack: Long = CLOCK_SLACK_MS): Boolean =
        lastSeen > 0 && now < lastSeen - slack

    /**
     * ترجمة قرار الخادم إلى حالة التطبيق — نقية لتُختبر وحدها.
     * تعيد null إذا لم يكن للخادم قرار نافذ فيُكمَل بالحساب المحلي.
     *
     * الرفض (انتهاء التجربة/الاشتراك) نافذ بلا مهلة سماح، وإلا صار قطع
     * الإنترنت وسيلة لاستعادة الصلاحية. أما القبول فتنتهي صلاحيته بالمهلة.
     */
    internal fun fromOnline(status: String, fresh: Boolean, plan: String, days: Int): LicenseState? =
        when (status) {
            "trial_ended" -> LicenseState.TrialEnded
            "expired" -> LicenseState.Expired
            "blocked", "wrong_device" -> LicenseState.Suspended
            "trial", "active" -> if (!fresh) null else {
                val p = LicenseCore.Plan.entries.firstOrNull { it.name.equals(plan, true) }
                when (p) {
                    null, LicenseCore.Plan.TRIAL -> LicenseState.Trial(days)
                    LicenseCore.Plan.LIFETIME -> LicenseState.Licensed(p, Int.MAX_VALUE, true)
                    else -> LicenseState.Licensed(p, days, false)
                }
            }
            else -> null
        }

    /**
     * وقت الخادم هو المرجع الصحيح — يصلح ساعة مضبوطة خطأً للأمام أو للخلف.
     * بدون هذا يبقى المرجع المحلي عالقاً على قفزة خاطئة إلى الأبد.
     */
    private fun noteServerTime(issuedAt: Long) {
        if (issuedAt <= 0) return
        prefs().edit().putLong(KEY_LAST_SEEN, issuedAt).apply()
    }

    /**
     * إيقاف/استئناف عن بعد — قرار مزوّد الخدمة يُرجّح فوق كل شيء بما فيه
     * التجربة، ويُحفظ محلياً حتى لا يُتجاوز بإسقاط المفتاح.
     */
    fun setRemoteSuspended(suspended: Boolean) {
        prefs().edit().putBoolean(KEY_SUSPENDED, suspended).apply()
        refresh()
    }

    /** موقوف إن أوقفه أيٌّ من المصدرين — رفع الإيقاف يلزم من أوقفه */
    fun isRemoteSuspended(): Boolean =
        prefs().getBoolean(KEY_SUSPENDED, false) || prefs().getBoolean(KEY_SUSPENDED_SERVER, false)

    // ==================== طبقة الخادم ====================

    private fun storeOnline(s: LicenseServer.ServerState) {
        prefs().edit()
            .putString(KEY_ON_STATUS, s.status)
            .putBoolean(KEY_ON_VALID, s.valid)
            .putString(KEY_ON_PLAN, s.plan)
            .putInt(KEY_ON_DAYS, s.daysLeft)
            .putString(KEY_ON_REASON, s.reason)
            .putLong(KEY_ON_AT, System.currentTimeMillis())
            .putInt(KEY_ON_GRACE, s.graceHours)
            .apply()
        noteServerTime(s.issuedAt)
        // قرار الإيقاف يُثبَّت محلياً فلا يُتجاوز بقطع الإنترنت — في مفتاح
        // خاص بالخادم حتى لا يمسح قرار الأدمن القادم من Firestore
        prefs().edit()
            .putBoolean(KEY_SUSPENDED_SERVER, s.status == "blocked" || s.status == "wrong_device")
            .apply()
        _reason.value = s.reason
    }

    private fun onlineStatus(): String = prefs().getString(KEY_ON_STATUS, "").orEmpty()

    /** هل ما زالت الحالة المخزّنة ضمن مهلة السماح بلا إنترنت؟ */
    private fun onlineFresh(): Boolean {
        val at = prefs().getLong(KEY_ON_AT, 0)
        if (at <= 0) return false
        val grace = prefs().getInt(KEY_ON_GRACE, 72).coerceIn(1, 720) * 3600_000L
        return System.currentTimeMillis() - at <= grace
    }

    /**
     * تحقق أونلاين. لا يقفل المستخدم عند تعذّر الوصول للخادم — الانقطاع ليس
     * ذنبه — لكن الحالة المخزّنة تنتهي صلاحيتها بعد مهلة السماح فيلزم اتصال.
     * يعيد رسالة الخطأ أو null عند النجاح.
     */
    suspend fun syncOnline(userInitiated: Boolean = false): String? {
        if (!LicenseServer.configured || !isRegistered()) return null
        _syncing.value = true
        try {
            val res = LicenseServer.check(customerEmail(), deviceCode(), userInitiated)
            val s = res.getOrElse {
                return it.message ?: "تعذّر الوصول لخادم التراخيص"
            }
            // «غير مسجّل على الخادم»: نحاول تسجيله بصمت بدل معاقبة المستخدم
            if (s.status == "unknown") {
                val re = LicenseServer.register(
                    customerEmail(), customerName(), customerPhone(), deviceCode(),
                )
                re.getOrNull()?.let { storeOnline(it); refresh(); return null }
                return re.exceptionOrNull()?.message ?: "الحساب غير مسجّل على الخادم"
            }
            storeOnline(s)
            refresh()
            return null
        } finally {
            _syncing.value = false
        }
    }

    /**
     * التسجيل الكامل: تحقق محلي ← تسجيل على الخادم ← بدء التجربة.
     *
     * الخادم أولاً لأنه صاحب القرار: لو رفض (الجهاز مربوط بحساب آخر، أو استُهلكت
     * تجربته) لا نمنح تجربة محلية ونعرض سببه. أما انقطاع الشبكة فليس ذنب
     * المستخدم — نمنح التجربة محلياً ونعيد المحاولة في كل تحقق دوري.
     *
     * يعيد رسالة الخطأ أو null عند النجاح.
     */
    suspend fun registerFull(email: String, name: String, phone: String): String? {
        localValidation(email, name, phone)?.let { return it }
        if (LicenseServer.configured) {
            val res = LicenseServer.register(
                email.trim().lowercase(), name.trim(), phone.filter { it.isDigit() }, deviceCode(),
            )
            res.fold(
                onSuccess = { s ->
                    saveIdentity(email, name, phone)
                    storeOnline(s)
                    refresh()
                    return null
                },
                onFailure = { e ->
                    // رفض صريح: قرار الخادم نافذ ولا تجربة محلية تلتفّ عليه
                    if (e is LicenseServer.Rejected) return e.message ?: "تعذّر التسجيل"
                },
            )
        }
        return register(email, name, phone)
    }

    /** إرسال طلب ترخيص/تجديد إلى الخادم */
    suspend fun requestOnline(renewal: Boolean, note: String = ""): String? {
        if (!LicenseServer.configured) return "الربط بالخادم غير مُهيَّأ"
        return LicenseServer.requestLicense(customerEmail(), deviceCode(), renewal, note)
            .fold({ null }, { it.message ?: "تعذّر إرسال الطلب" })
    }

    /** إعادة حساب الحالة */
    fun refresh() {
        // الإيقاف عن بعد يعلو كل شيء — حتى داخل أيام التجربة أو بلا مفتاح
        if (isRemoteSuspended()) {
            _state.value = LicenseState.Suspended
            return
        }
        // ساعة مُرجَعة للخلف: لا نمنح وقتاً، ومخرجها اتصال واحد بالإنترنت.
        //
        // مقصور على المسجَّلين عمداً — وهم وحدهم من يملك `syncOnline` مخرجاً لهم.
        // لا يشمل حامل مفتاح مدفوع بلا بريد: `syncOnline` ترفض العمل بلا تسجيل
        // فيبقى مقفولاً بلا مخرج، وهو أصلاً غير معرَّض للخطر لأن مدة المفتاح
        // تُقاس بـ trustedNow() التصاعدية فلا يمدّدها إرجاع الساعة.
        if (isRegistered() && clockRolledBack()) {
            _state.value = LicenseState.ClockInvalid
            return
        }
        val now = trustedNow()
        val license = savedLicense()

        // الترخيص المدفوع له الأولوية دائماً
        if (license.isNotBlank()) {
            val info = LicenseCore.verify(appContext, license)
            if (info != null) {
                if (info.lifetime) {
                    _state.value = LicenseState.Licensed(info.plan, Int.MAX_VALUE, true)
                    return
                }
                val daysLeft = ((info.expiryMillis - now) / DAY_MS).toInt()
                _state.value = when {
                    daysLeft < 0 -> LicenseState.Expired
                    info.plan == LicenseCore.Plan.TRIAL -> LicenseState.Trial(daysLeft)
                    else -> LicenseState.Licensed(info.plan, daysLeft, false)
                }
                return
            }
            prefs().edit().remove(KEY_LICENSE).apply()
        }

        // لا ترخيص — الحالة تتبع التسجيل والتجربة
        if (!isRegistered()) {
            _state.value = LicenseState.NeedsRegister
            return
        }

        // قرار الخادم يسبق الحساب المحلي متى وُجد؛ و"unknown" أو خادم غير
        // مُهيَّأ يعيد null فنكمل بالحساب المحلي بلا معاقبة المستخدم
        fromOnline(
            status = onlineStatus(),
            fresh = onlineFresh(),
            plan = prefs().getString(KEY_ON_PLAN, "").orEmpty(),
            days = prefs().getInt(KEY_ON_DAYS, 0),
        )?.let { _state.value = it; return }

        val start = prefs().getLong(KEY_TRIAL_START, 0)
        val elapsedDays = if (start > 0) ((now - start) / DAY_MS).toInt().coerceAtLeast(0) else 0
        val left = TRIAL_DAYS - elapsedDays
        _state.value = if (left > 0) LicenseState.Trial(left) else LicenseState.TrialEnded
    }

    /** محاولة تفعيل ترخيص. يعيد رسالة الخطأ أو null عند النجاح */
    fun activate(licenseText: String): String? {
        val info = LicenseCore.verify(appContext, licenseText)
            ?: return LicenseCore.diagnose(appContext, licenseText)
        if (!info.lifetime && info.expiryMillis < trustedNow()) {
            return "هذا المفتاح منتهي الصلاحية"
        }
        prefs().edit().putString(KEY_LICENSE, licenseText.trim()).apply()
        refresh()
        return null
    }

    fun deactivate() {
        prefs().edit().remove(KEY_LICENSE).apply()
        refresh()
    }

    /** هل يُسمح باستخدام التطبيق الآن؟ */
    fun isUsable(): Boolean = when (_state.value) {
        is LicenseState.Trial, is LicenseState.Licensed -> true
        else -> false
    }
}
