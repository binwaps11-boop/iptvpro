package com.binwaps.cardmanager.license

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** حالة الترخيص الحالية للتطبيق */
sealed interface LicenseState {
    data class Trial(val daysLeft: Int) : LicenseState
    data class Licensed(val plan: LicenseCore.Plan, val daysLeft: Int, val lifetime: Boolean) : LicenseState
    data object Expired : LicenseState
    data object TrialEnded : LicenseState
}

/**
 * يدير الفترة التجريبية (أسبوع) وحفظ الترخيص والتحقق منه عند كل تشغيل.
 */
object LicenseManager {
    private const val PREFS = "license_store"
    private const val KEY_TRIAL_START = "trial_start"
    private const val KEY_LAST_SEEN = "last_seen"
    private const val KEY_LICENSE = "license_key"

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

    private fun trialStart(): Long {
        val saved = prefs().getLong(KEY_TRIAL_START, 0)
        if (saved > 0) return saved
        val installTime = runCatching {
            appContext.packageManager.getPackageInfo(appContext.packageName, 0).firstInstallTime
        }.getOrDefault(System.currentTimeMillis())
        prefs().edit().putLong(KEY_TRIAL_START, installTime).apply()
        return installTime
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
                _state.value = if (daysLeft >= 0) {
                    LicenseState.Licensed(info.plan, daysLeft, false)
                } else {
                    LicenseState.Expired
                }
                return
            }
            // ترخيص غير صالح أو لجهاز آخر — نحذفه
            prefs().edit().remove(KEY_LICENSE).apply()
        }

        val elapsedDays = ((now - trialStart()) / DAY_MS).toInt()
        val left = TRIAL_DAYS - elapsedDays
        _state.value = if (left > 0) LicenseState.Trial(left) else LicenseState.TrialEnded
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
