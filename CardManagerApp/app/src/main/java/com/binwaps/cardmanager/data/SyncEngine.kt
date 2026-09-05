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
 *  - الباقات (جدولان صغيران): أول اتصال ثم كل ٤٠ دورة، وفوراً بعد كل رفع
 *  - الكروت نفسها: فور أول اتصال، ثم عند تغيّر العدّادات (بفاصل لا يقل عن
 *    دقيقتين)، واحتياطياً كل ٤٠ دورة — مع دمجٍ يحافظ على الكروت المحلية التي
 *    لم تُرفع بعد فلا يضيع شيء
 *  - فشل جلب الكروت (مهلة على راوتر ضخم/بعيد) يتراجع أُسّياً بدل إعادة
 *    المحاولة كل دورة وحبس قفل الجلسة نصف الوقت
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

    /** آخر سبب لفشل جلب الكروت — يُعرض للمستخدم بدل الصمت */
    private val _lastCardsError = MutableStateFlow<String?>(null)
    val lastCardsError: StateFlow<String?> get() = _lastCardsError

    /** آخر سبب لفشل الاتصال بالراوتر في المزامنة — تعرضه اللوحة بدل «غير متصل» الصامتة */
    private val _connectError = MutableStateFlow<String?>(null)
    val connectError: StateFlow<String?> get() = _connectError

    /** هل حلقة المزامنة تعمل (اتصال تلقائي جارٍ أو قائم)؟ */
    fun isRunning(): Boolean = loop?.isActive == true

    private const val ROUND_MS = 15_000L
    private const val PROFILES_EVERY = 40
    private const val BACKSTOP_EVERY = 40
    /** أقل فاصل بين جلبَي كروت كاملَين بسبب تغيّر العدّادات — كل دخول زبون يغيّر «المستعمَل» */
    private const val MIN_FULL_FETCH_GAP_MS = 120_000L

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
            var profilesFetchedForRouter: Long? = null
            // بصمة رخيصة لحالة الكروت (إجمالي + مستعمَل) — لا نُجري النقل الكامل
            // الحاجز للقفل إلا إذا تغيّرت، فتندر مصادفته لعملية المستخدم الأمامية
            var lastCardsSig: Long? = null
            var lastFullFetchAt = 0L
            // تراجع أُسّي بعد فشل جلب الكروت: 15ث، 30ث، 60ث… حتى 5 دقائق
            var cardFailures = 0
            var nextCardsAttemptAt = 0L
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
                        .onSuccess { Store.setStatus(it); Store.setConnected(true); _connectError.value = null }
                        // لا نُعلن الانقطاع إن كانت عملية أمامية (رفع/جلب بضغطة)
                        // تحتجز القفل: فشل الاكتساب هنا «مشغول» عابر لا انقطاع
                        // فعلي. إعلانه كان يقلب المؤشر إلى «غير متصل» طوال رفعٍ
                        // طويل مشروع ثم لا يعود حتى ينتهي الرفع.
                        .onFailure {
                            if (!MikrotikClient.foregroundActive()) {
                                Store.setConnected(false)
                                _connectError.value = it.message?.take(160)
                            }
                        }
                        .isSuccess

                    if (connected) {
                        val stats = MikrotikClient.fetchCardStats(r).getOrNull()?.also { Store.setStatus(it) }
                        MikrotikClient.fetchActiveUsers(r).onSuccess { Store.setActiveUsers(it) }

                        // الباقات جدولان صغيران؛ عدد كروت كل باقة يُحسب محلياً من
                        // القائمة (كان يُنقل حقل الباقة لكل مستخدم كل ٧٥ ثانية)
                        val needProfiles = profilesFetchedForRouter != r.id ||
                            Store.profiles.value.isEmpty() || round % PROFILES_EVERY == 0
                        if (needProfiles) {
                            MikrotikClient.fetchProfiles(r).onSuccess {
                                Store.setProfiles(it)
                                profilesFetchedForRouter = r.id
                            }
                        }

                        // بوابة تغيّر رخيصة: النقل الكامل (يحبس القفل طوال جلب كل
                        // الكروت) لا يُجرى إلا عند تغيّر الإجمالي/المستعمَل (بفاصل
                        // دقيقتين على الأقل)، أو أول مرة للراوتر، أو احتياطياً كل ٤٠
                        // دورة (~١٠ دقائق) لالتقاط انتهاء اليوزر منجر بالتاريخ الذي
                        // لا يغيّر أي عدّاد. عدّادات مجهولة (فشل count) لا تُجبر جلباً.
                        val sig = stats?.let {
                            it.hotspotUsers.toLong() * 1_000_003L +
                                it.userManagerUsers.toLong() * 31L + it.usedUsers.toLong()
                        }
                        val now = System.currentTimeMillis()
                        val firstForRouter = cardsFetchedForRouter != r.id
                        val changed = sig != null && sig != lastCardsSig &&
                            now - lastFullFetchAt >= MIN_FULL_FETCH_GAP_MS
                        val backstop = round % BACKSTOP_EVERY == 0 && round > 0
                        // إعادة فحص foreground مباشرة قبل النقل الطويل: عملية المستخدم
                        // قد تكون بدأت بعد فحص رأس الحلقة خلال connect/stats/profiles،
                        // فنُفسح لها القفل بدل حبسه بنقلٍ يمتد عشرات الثواني
                        val needCards = (firstForRouter || changed || backstop) && now >= nextCardsAttemptAt
                        if (needCards && !_cardsSyncing.value && !MikrotikClient.foregroundActive()) {
                            _cardsSyncing.value = true
                            try {
                                // أول جلب للراوتر بمهلة الأمر الطويلة (٩٠ث): راوتر ضخم
                                // أو بعيد كان يفشل بمهلة الخلفية (٣٠ث) ثم يُعاد كل
                                // دورة إلى ما لا نهاية — القفل محبوس نصف الوقت والقائمة
                                // فارغة أبداً، وهذا هو «ثقل المزامنة» الذي يشعر به المستخدم
                                MikrotikClient.fetchAllCardsDetailed(r, foreground = firstForRouter)
                                    .onSuccess {
                                        Store.mergeRouterCards(it.cards, it.sources)
                                        cardsFetchedForRouter = r.id
                                        lastCardsSig = sig
                                        lastFullFetchAt = System.currentTimeMillis()
                                        cardFailures = 0
                                        nextCardsAttemptAt = 0L
                                        _lastCardsError.value = null
                                    }
                                    .onFailure { e ->
                                        cardFailures++
                                        val backoff = (ROUND_MS shl minOf(cardFailures, 4)).coerceAtMost(300_000L)
                                        nextCardsAttemptAt = System.currentTimeMillis() + backoff
                                        val reason = e.message?.take(140) ?: "سبب غير معروف"
                                        _lastCardsError.value = reason
                                        EventLog.log(
                                            "مزامنة",
                                            "فشل جلب الكروت (${cardFailures}): $reason — المحاولة التالية بعد ${backoff / 1000}ث",
                                            ok = false,
                                        )
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
                delay(ROUND_MS)
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
            // نتنحّى حتى ينتهي الرفع الجاري (لو استُدعيت أثناءه)، بسقف أمان
            var waited = 0
            while (MikrotikClient.foregroundActive() && waited < 60) {
                delay(1_000); waited++
            }
            MikrotikClient.fetchCardStats(r).onSuccess { Store.setStatus(it) }
            MikrotikClient.fetchProfiles(r, foreground = true).onSuccess { Store.setProfiles(it) }
            if (!_cardsSyncing.value) {
                _cardsSyncing.value = true
                try {
                    // foreground=true: تحديث ما بعد الرفع يأخذ مهلة الأمر الطويلة
                    // (٩٠ث) فيُكمل نقل قائمة كبيرة بدل أن يفشل فتبقى القائمة قديمة
                    // ويظنّ المستخدم أن الرفع فشل فيعيده (وهم «التكرار»).
                    MikrotikClient.fetchAllCardsDetailed(r, foreground = true)
                        .onSuccess { Store.mergeRouterCards(it.cards, it.sources); _lastCardsError.value = null }
                        .onFailure { _lastCardsError.value = it.message?.take(140) }
                } finally {
                    _cardsSyncing.value = false
                }
            }
        }
    }
}
