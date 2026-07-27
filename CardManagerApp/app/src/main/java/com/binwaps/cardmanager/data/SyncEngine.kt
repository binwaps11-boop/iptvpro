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
            while (isActive) {
                val r = Store.activeRouter()
                // فشل دورة عابر لا يوقف المزامنة للأبد — تعاود المحاولة في
                // الدورة التالية. والمحرك أصلاً لا يبدأ إلا بعد نجاح اتصال.
                if (r != null) {
                    val connected = MikrotikClient.connect(r)
                        .onSuccess { Store.setStatus(it); Store.setConnected(true) }
                        .onFailure { Store.setConnected(false) }
                        .isSuccess

                    if (connected) {
                        MikrotikClient.fetchCardStats(r).onSuccess { Store.setStatus(it) }
                        MikrotikClient.fetchActiveUsers(r).onSuccess { Store.setActiveUsers(it) }

                        if (Store.profiles.value.isEmpty() || round % 5 == 0) {
                            MikrotikClient.fetchProfiles(r).onSuccess { Store.setProfiles(it) }
                        }

                        val needCards = cardsFetchedForRouter != r.id || round % 8 == 0
                        if (needCards && !_cardsSyncing.value) {
                            _cardsSyncing.value = true
                            try {
                                MikrotikClient.fetchAllCards(r)
                                    .onSuccess {
                                        Store.mergeRouterCards(it)
                                        cardsFetchedForRouter = r.id
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

    /** مزامنة فورية الآن (بعد رفع أو توليد) دون انتظار الدورة القادمة */
    fun syncNow() {
        scope.launch {
            val r = Store.activeRouter() ?: return@launch
            MikrotikClient.fetchCardStats(r).onSuccess { Store.setStatus(it) }
            MikrotikClient.fetchProfiles(r).onSuccess { Store.setProfiles(it) }
        }
    }
}
