package com.binwaps.cardmanager.data

import android.content.Context
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.model.*
import com.binwaps.cardmanager.performance.ThroughputMeter
import com.binwaps.cardmanager.print.PrintEngine
import com.binwaps.cardmanager.util.Charset
import com.binwaps.cardmanager.util.UserGenerator
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** One production job shared across screens; navigation does not abandon an upload. */
object ProductionEngine {
    enum class Status { IDLE, RUNNING, DONE, PAUSED, SKIPPED }
    data class Stage(
        val status: Status = Status.IDLE,
        val done: Int = 0,
        val total: Int = 0,
        val rate: Double = 0.0,
        val seconds: Double = 0.0,
        val remaining: Long = -1,
        val detail: String = "",
    )
    data class State(val batchId: String = "", val count: Int = 0, val generation: Stage = Stage(), val upload: Stage = Stage()) {
        val busy: Boolean get() = generation.status == Status.RUNNING || upload.status == Status.RUNNING
    }
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var generationJob: Job? = null
    private var uploadJob: Job? = null
    private var pending = emptyList<UserEntry>()
    private var router: RouterProfile? = null
    private var target = UploadTarget.HOTSPOT

    private fun measured(status: Status, done: Int, meter: ThroughputMeter, detail: String = ""): Stage {
        val s = meter.sample(done, System.nanoTime())
        return Stage(status, s.done, s.total, s.perSecond, s.elapsedSeconds, s.remainingSeconds, detail)
    }

    @Synchronized
    fun start(
        context: Context, template: CardTemplate, settings: AppSettings,
        count: Int, length: Int, profile: String, price: String, validity: String,
        uploadEnabled: Boolean,
    ) {
        if (_state.value.busy || generationJob?.isCompleted == false || uploadJob?.isCompleted == false || PrintEngine.hasPendingJob()) return
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) return
        require(count in 1..100000)
        val batchId = "vc-" + UUID.randomUUID().toString().take(12)
        val snapshotRouter = Store.activeRouter()
        val meter = ThroughputMeter(count, System.nanoTime())
        val appContext = context.applicationContext
        _state.value = State(batchId, count, Stage(Status.RUNNING, 0, count))
        router = snapshotRouter
        target = settings.uploadTarget
        pending = emptyList()
        generationJob = scope.launch {
            var saved = false
            var added = false
            try {
                val task = currentCoroutineContext()
                val existing = Store.users.value.map { it.username }
                var lastGenerationEmit = 0L
                val cards = UserGenerator.generate(
                    count, "", length, Charset.DIGITS, settings.cardMode, 8,
                    profile, price, validity, batchTag = batchId,
                    existingUsernames = existing,
                    shouldContinue = { task.isActive },
                    onProgress = { done, total ->
                        val now = System.nanoTime()
                        if (now - lastGenerationEmit >= 150_000_000L || done == total) {
                            lastGenerationEmit = now
                            _state.update { it.copy(generation = measured(Status.RUNNING, done, meter)) }
                        }
                    },
                )
                ensureActive()
                Store.addGeneratedUsers(cards)
                added = true
                _state.update { it.copy(generation = measured(Status.RUNNING, cards.size, meter, "حفظ الدفعة على الجهاز…")) }
                Store.checkpointUsers().await()
                saved = true
                pending = cards
                // Both consumers share the same immutable batch and settings snapshot.
                check(PrintEngine.startPdf(appContext, template, cards, settings, productionBatch = true)) {
                    "توجد مهمة طباعة أخرى؛ الدفعة محفوظة لاختيارها من شاشة الطباعة"
                }
                if (uploadEnabled && snapshotRouter != null) beginUpload(cards)
                else _state.update { it.copy(upload = Stage(Status.SKIPPED, detail = "تجهيز PDF فقط")) }
                _state.update { it.copy(generation = measured(Status.DONE, cards.size, meter)) }
            } catch (e: CancellationException) {
                _state.update { it.copy(generation = it.generation.copy(
                    status = if (saved) Status.DONE else Status.PAUSED,
                    detail = if (saved) "الدفعة محفوظة في قائمة الكروت"
                        else if (added) "أُوقف تجهيز الدفعة؛ الكروت المولدة موجودة في القائمة"
                        else "أُلغي التوليد قبل حفظ الدفعة",
                )) }
            } catch (e: Throwable) {
                _state.update { it.copy(generation = it.generation.copy(
                    status = if (saved) Status.DONE else Status.PAUSED,
                    detail = (if (saved) "الدفعة محفوظة. " else "") +
                        (if (e is OutOfMemoryError) "الذاكرة غير كافية — أغلق تطبيقات أخرى أو قلّل حجم الدفعة"
                        else e.message ?: "تعذّر تجهيز الدفعة"),
                )) }
            }
        }
    }

    @Synchronized
    private fun beginUpload(cards: List<UserEntry>) {
        if (cards.isEmpty() || uploadJob?.isActive == true) return
        val selectedRouter = router
        val selectedTarget = target
        val meter = ThroughputMeter(cards.size, System.nanoTime())
        val completed = ConcurrentHashMap.newKeySet<String>()
        _state.update { it.copy(upload = Stage(Status.RUNNING, total = cards.size, detail = "إنشاء المستخدمين وتأكيد الباقات")) }
        uploadJob = scope.launch {
            var lastEmit = 0L
            var lastSave = System.nanoTime()
            var error: String? = null
            var stopped = false
            try {
                val onCreated: (UserEntry) -> Unit = { card ->
                    completed.add(card.username)
                    val now = System.nanoTime()
                    if (now - lastEmit >= 150_000_000L || completed.size == cards.size) {
                        lastEmit = now
                        _state.update { it.copy(upload = measured(Status.RUNNING, completed.size, meter, "كروت اكتمل رفعها وربط باقاتها")) }
                    }
                    // Time-bounded checkpoints instead of copying the growing list every card.
                    if (now - lastSave >= 2_000_000_000L) {
                        lastSave = now
                        Store.markUploaded(completed.toList())
                    }
                }
                val result = when (selectedTarget) {
                    UploadTarget.HOTSPOT -> MikrotikClient.createHotspotUsers(selectedRouter, cards, onCreated = onCreated)
                    UploadTarget.USER_MANAGER -> MikrotikClient.createUserManagerUsers(selectedRouter, cards, onCreated = onCreated)
                }
                error = result.exceptionOrNull()?.message
            } catch (e: CancellationException) {
                stopped = true
            } catch (e: Exception) {
                error = e.message
            } finally {
                // A set lookup per card keeps partial-failure recovery linear for 50k+ cards.
                val accepted = completed.toSet()
                Store.markUploaded(accepted)
                pending = cards.filterNot { it.username in accepted }
                val status = if (pending.isEmpty()) Status.DONE else Status.PAUSED
                val detail = when {
                    pending.isEmpty() -> "اكتمل رفع الدفعة"
                    stopped -> "توقف الإرسال؛ الكروت غير المؤكدة محفوظة لإعادة المحاولة"
                    else -> error ?: "بقي ${pending.size} كرت لم يكتمل رفعه"
                }
                _state.update { it.copy(upload = measured(status, accepted.size, meter, detail)) }
            }
            if (!stopped) SyncEngine.syncNow()
        }
    }

    @Synchronized
    fun retryUpload() {
        if (_state.value.upload.status == Status.PAUSED && uploadJob?.isActive != true) beginUpload(pending)
    }

    fun stopUpload() { uploadJob?.cancel() }
    fun cancelGeneration() { generationJob?.cancel() }
}
