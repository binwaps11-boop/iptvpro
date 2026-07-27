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
    private const val KEY_SUSPENDED = "suspended_remote"

    const val TRIAL_DAYS = 7
    private const val DAY_MS = 86_400_000L

    private lateinit var appContext: Context

    private val _state = MutableStateFlow<LicenseState>(LicenseState.NeedsRegister)
    val state: StateFlow<LicenseState> get() = _state

    fun init(context: Context) {
        appContext = context.applicationContext
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
    fun register(email: String, name: String): String? {
        val e = email.trim()
        if (!e.contains("@") || !e.contains(".")) return "أدخل بريداً صحيحاً مثل name@gmail.com"
        val now = trustedNow()
        val edit = prefs().edit()
        edit.putString(KEY_EMAIL, e)
        if (name.isNotBlank()) edit.putString(KEY_NAME, name.trim())
        if (prefs().getLong(KEY_TRIAL_START, 0) <= 0) edit.putLong(KEY_TRIAL_START, now)
        edit.apply()
        refresh()
        return null
    }

    /**
     * وقت موثوق نسبياً: يمنع إرجاع ساعة الجهاز للخلف لتمديد التجربة.
     * نحفظ آخر وقت شوهد ونستخدم الأكبر بين الوقت الحالي وآخر وقت.
     */
    private fun trustedNow(): Long {
        val now = System.currentTimeMillis()
        val lastSeen = prefs().getLong(KEY_LAST_SEEN, 0)
        val trusted = maxOf(now, lastSeen)
        prefs().edit().putLong(KEY_LAST_SEEN, trusted).apply()
        return trusted
    }

    /**
     * إيقاف/استئناف عن بعد — قرار مزوّد الخدمة يُرجّح فوق كل شيء بما فيه
     * التجربة، ويُحفظ محلياً حتى لا يُتجاوز بإسقاط المفتاح.
     */
    fun setRemoteSuspended(suspended: Boolean) {
        prefs().edit().putBoolean(KEY_SUSPENDED, suspended).apply()
        refresh()
    }

    fun isRemoteSuspended(): Boolean = prefs().getBoolean(KEY_SUSPENDED, false)

    /** إعادة حساب الحالة */
    fun refresh() {
        // الإيقاف عن بعد يعلو كل شيء — حتى داخل أيام التجربة أو بلا مفتاح
        if (isRemoteSuspended()) {
            _state.value = LicenseState.Suspended
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
        val start = prefs().getLong(KEY_TRIAL_START, 0)
        val elapsedDays = if (start > 0) ((now - start) / DAY_MS).toInt() else 0
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
