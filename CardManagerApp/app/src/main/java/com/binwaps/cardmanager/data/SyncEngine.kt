package com.binwaps.cardmanager.data

import com.binwaps.cardmanager.mikrotik.MikrotikClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * محرك المزامنة التلقائية — لا زر «جلب» ولا انتظار: من لحظة فتح التطبيق
 * يتصل بالراوتر المحفوظ ويجلب كل شيء ويبقيه محدثاً باستمرار.
 *
 * الإيقاع:
 *  - كل دورة (15 ثانية): حالة النظام + عدادات الكروت (count-only فوري) + المتصلون
 *  - الباقات: فوراً إن كانت فارغة، وإلا كل 5 دورات
 *  - الكروت نفسها: فور أول اتصال ثم كل 8 دورات (بحقول مختصرة)، مع دمجٍ
 *    يحافظ على الكروت المحلية التي لم تُرفع بعد فلا يضيع شيء
 *
 * كل الجلب على الجلسة الدائمة نفسها — سريع حتى على دومين بعيد.
 */
object SyncEngine {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var loop: Job? = null

    private val _lastSyncAt = MutableStateFlow(0L)
    val lastSyncAt: StateFlow<Long> get() = _lastSyncAt

    private val _cardsSyncing = MutableStateFlow(false)
    val cardsSyncing: StateFlow<Boolean> get() = _cardsSyncing

    /** يوقف المزامنة — عند قطع الاتصال يدوياً؛ يُستأنف بـ [start] عند الاتصال */
    fun stop() {
        loop?.cancel()
        loop = null
        Store.setConnected(false)
    }

    /** يبدأ حلقة المزامنة — آمن استدعاؤه أكثر من مرة */
    fun start() {
        if (loop?.isActive == true) return
        loop = scope.launch {
            var round = 0
            var cardsFetchedForRouter: Long? = null
            // بصمة رخيصة لحالة الكروت (إجمالي + مستعمَل) — لا نُجري النقل الكامل
            // الحاجز للقفل إلا إذا تغيّرت، فتندر مصادفته لعملية المستخدم الأمامية
            var lastCardsSig: Long? = null
            while (isActive) {
                // عملية أمامية جارية (رفع/توليد بضغطة المستخدم): نتنحّى تماماً
                // عن القفل ونعيد الفحص قريباً. دورة المزامنة كانت تحتجز القفل
                // بجلب كل الكروت فيقف رفع المستخدم بلا نبضة تقدّم على «0 من N»
                if (MikrotikClient.foregroundActive()) {
                    delay(2_000)
                    continue
                }
                val r = Store.activeRouter()
                // فشل دورة عابر لا يوقف المزامنة للأبد — تعاود المحاولة في
                // الدورة التالية. والمحرك أصلاً لا يبدأ إلا بعد نجاح اتصال.
                if (r != null) {
                    val connected = MikrotikClient.connect(r)
                        .onSuccess { Store.setStatus(it); Store.setConnected(true) }
                        // لا نُعلن الانقطاع إن كانت عملية أمامية (رفع/جلب بضغطة)
                        // تحتجز القفل: فشل الاكتساب هنا «مشغول» عابر لا انقطاع
                        // فعلي. إعلانه كان يقلب المؤشر إلى «غير متصل» طوال رفعٍ
                        // طويل مشروع ثم لا يعود حتى ينتهي الرفع.
                        .onFailure { if (!MikrotikClient.foregroundActive()) Store.setConnected(false) }
                        .isSuccess

                    if (connected) {
                        val stats = MikrotikClient.fetchCardStats(r).getOrNull()?.also { Store.setStatus(it) }
                        MikrotikClient.fetchActiveUsers(r).onSuccess { Store.setActiveUsers(it) }

                        if (Store.profiles.value.isEmpty() || round % 5 == 0) {
                            MikrotikClient.fetchProfiles(r).onSuccess { Store.setProfiles(it) }
                        }

                        // بوابة تغيّر رخيصة: النقل الكامل (يحبس القفل طوال جلب كل
                        // الكروت) لا يُجرى إلا عند تغيّر الإجمالي/المستعمَل، أو أول
                        // مرة للراوتر، أو احتياطياً كل ٤٠ دورة (~١٠ دقائق) لالتقاط
                        // انتهاء اليوزر منجر بالتاريخ الذي لا يغيّر أي عدّاد.
                        val sig = stats?.let {
                            it.hotspotUsers.toLong() * 1_000_003L +
                                it.userManagerUsers.toLong() * 31L + it.usedUsers.toLong()
                        }
                        val firstForRouter = cardsFetchedForRouter != r.id
                        val changed = sig == null || sig != lastCardsSig
                        val backstop = round % 40 == 0
                        // إعادة فحص foreground مباشرة قبل النقل الطويل: عملية المستخدم
                        // قد تكون بدأت بعد فحص رأس الحلقة خلال connect/stats/profiles،
                        // فنُفسح لها القفل بدل حبسه بنقلٍ يمتد عشرات الثواني
                        val needCards = firstForRouter || changed || backstop
                        if (needCards && !_cardsSyncing.value && !MikrotikClient.foregroundActive()) {
                            _cardsSyncing.value = true
                            try {
                                MikrotikClient.fetchAllCards(r)
                                    .onSuccess {
                                        Store.mergeRouterCards(it)
                                        cardsFetchedForRouter = r.id
                                        lastCardsSig = sig
                                    }
                            } finally {
                                // إلغاء الحلقة أثناء الجلب كان يترك العلم true للأبد فتتجمد المزامنة
                                _cardsSyncing.value = false
                            }
                        }
                        _lastSyncAt.value = System.currentTimeMillis()
                    }
                }
                round++
                delay(15_000)
            }
        }
    }

    /**
     * مزامنة فورية الآن (بعد رفع أو توليد) دون انتظار الدورة القادمة.
     * تشمل **الكروت** أيضاً: كانت لا تُجلب هنا، فبعد الرفع تبقى القائمة قديمة
     * حتى الدورة الدورية (حتى دقيقتين). ننتظر انتهاء العملية الأمامية (الرفع)
     * كي لا نزاحمها على قفل الجلسة، ونحمي بعلم الجلب نفسه ضد تداخل جلبين.
     */
    fun syncNow() {
        scope.launch {
            val r = Store.activeRouter() ?: return@launch
            MikrotikClient.fetchCardStats(r).onSuccess { Store.setStatus(it) }
            MikrotikClient.fetchProfiles(r).onSuccess { Store.setProfiles(it) }

            // نتنحّى حتى ينتهي الرفع الجاري (لو استُدعيت أثناءه)، بسقف أمان
            var waited = 0
            while (MikrotikClient.foregroundActive() && waited < 60) {
                delay(1_000); waited++
            }
            if (!_cardsSyncing.value) {
                _cardsSyncing.value = true
                try {
                    MikrotikClient.fetchAllCards(r).onSuccess { Store.mergeRouterCards(it) }
                } finally {
                    _cardsSyncing.value = false
                }
            }
        }
    }
}
