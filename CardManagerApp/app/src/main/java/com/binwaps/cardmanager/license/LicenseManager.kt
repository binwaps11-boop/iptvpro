package com.binwaps.cardmanager.license

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** حالة الترخيص الحالية للتطبيق */
sealed interface LicenseState {
    /** تجربة مفعّلة بمفتاح تجريبي صادر من لوحة التراخيص */
    data class Trial(val daysLeft: Int) : LicenseState
    data class Licensed(val plan: LicenseCore.Plan, val daysLeft: Int, val lifetime: Boolean) : LicenseState
    data object Expired : LicenseState
    /** لا مفتاح — يطلب تجربة أو اشتراكاً من مزوّد الخدمة */
    data object TrialEnded : LicenseState
}

/**
 * يدير الترخيص والتحقق منه عند كل تشغيل.
 *
 * التجربة المجانية لم تعد ذاتية داخل التطبيق: كانت تتجدد بحذف التطبيق
 * وإعادة تثبيته. صارت مفتاحاً تجريبياً يصدر من لوحة التراخيص مقفولاً على
 * بصمة الجهاز — والبصمة لا تتغير بإعادة التثبيت، ولوحة التراخيص تسجّل كل
 * جهاز أخذ تجربة فلا يحصل عليها مرتين.
 */
object LicenseManager {
    private const val PREFS = "license_store"
    private const val KEY_LAST_SEEN = "last_seen"
    private const val KEY_LICENSE = "license_key"
    private const val KEY_NAME = "customer_name"
    private const val KEY_PHONE = "customer_phone"

    const val TRIAL_DAYS = 7
    private const val DAY_MS = 86_400_000L

    private lateinit var appContext: Context

    private val _state = MutableStateFlow<LicenseState>(LicenseState.Trial(TRIAL_DAYS))
    val state: StateFlow<LicenseState> get() = _state

    fun init(context: Context) {
        appContext = context.applicationContext
        refresh()
    }

    private fun prefs() = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun deviceCode(): String = LicenseCore.deviceCode(appContext)

    fun savedLicense(): String = prefs().getString(KEY_LICENSE, "").orEmpty()

    /** اسم المشترك — يُرسل مع طلب التفعيل ليظهر في لوحة التراخيص */
    fun customerName(): String = prefs().getString(KEY_NAME, "").orEmpty()

    fun setCustomerName(value: String) {
        prefs().edit().putString(KEY_NAME, value).apply()
    }

    fun customerPhone(): String = prefs().getString(KEY_PHONE, "").orEmpty()

    fun setCustomerPhone(value: String) {
        prefs().edit().putString(KEY_PHONE, value).apply()
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

    /** إعادة حساب الحالة */
    fun refresh() {
        val now = trustedNow()
        val license = savedLicense()

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
            // ترخيص غير صالح أو لجهاز آخر — نحذفه
            prefs().edit().remove(KEY_LICENSE).apply()
        }

        // لا مفتاح إطلاقاً — التجربة تُطلب من مزوّد الخدمة، لا تبدأ من نفسها
        _state.value = LicenseState.TrialEnded
    }

    /** محاولة تفعيل ترخيص. يعيد رسالة الخطأ أو null عند النجاح */
    fun activate(licenseText: String): String? {
        val info = LicenseCore.verify(appContext, licenseText)
            ?: return "مفتاح غير صالح، أو صادر لجهاز آخر"
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
