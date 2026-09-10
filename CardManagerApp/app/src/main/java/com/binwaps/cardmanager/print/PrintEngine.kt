package com.binwaps.cardmanager.print

import android.content.Context
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardLayoutMode
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.PrintBatch
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
import com.binwaps.cardmanager.performance.PdfParts
import kotlinx.coroutines.ensureActive
import com.dantsu.escposprinter.EscPosPrinter
import com.dantsu.escposprinter.connection.DeviceConnection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * مهمة طباعة مشتركة بين شاشات التطبيق.
 *
 * - يعمل في خلفية التطبيق: الخروج من شاشة الطباعة لا يوقف المهمة.
 * - PDF متجهي، مع تقسيم اختياري وحفظ الأجزاء المكتملة لاستكمال الباقي.
 * - الحرارية: إعادة محاولة لكل كرت، مع حفظ التقدم كل خمسة كروت. بعد قتل
 *   العملية قد تتكرر كروت منذ آخر حفظ، ولا يمكن تأكيد خروج الورق برمجياً.
 * - التقدم محفوظ على القرص: حتى لو أُغلق التطبيق كلياً، يعرض عند فتحه
 *   «طباعة غير مكتملة — استئناف».
 * - فحص مسبق قبل البدء يمنع أكثر الأخطاء شيوعاً بدل أن تفشل في المنتصف.
 */
object PrintEngine {

    private const val THERMAL_RETRIES = 3

    enum class Kind { PDF, THERMAL }

    sealed interface State {
        data object Idle : State

        /** توجد مهمة غير مكتملة محفوظة من جلسة سابقة */
        data class Restorable(val kind: Kind, val done: Int, val total: Int) : State

        data class Running(val kind: Kind, val done: Int, val total: Int, val label: String) : State

        /** مهمة متوقفة يمكن إعادة محاولتها من اللقطة المحفوظة */
        data class Failed(val kind: Kind, val done: Int, val total: Int, val error: String) : State

        data class Done(val kind: Kind, val total: Int, val files: List<File>) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> get() = _state

    /**
     * أي خطأ يفلت من داخل مهمة الطباعة يتحول إلى حالة «متوقفة» قابلة للاستئناف
     * مع إتاحة إعادة المحاولة من الواجهة.
     */
    private val crashGuard = kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        val s = _state.value
        val done = (s as? State.Running)?.done ?: 0
        val total = (s as? State.Running)?.total ?: 0
        val kind = (s as? State.Running)?.kind ?: Kind.PDF
        _state.value = State.Failed(kind, done, total, friendly(e) + " — اضغط استئناف للمتابعة")
        runCatching { persist(kind) }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + crashGuard)
    private var job: Job? = null

    /** سياق التطبيق المحفوظ — للحفظ التلقائي في التنزيلات بعد اكتمال المهمة */
    private var savedContext: Context? = null

    // لقطة المهمة الحالية — تبقى في الذاكرة للاستئناف الفوري
    private var template: CardTemplate? = null
    private var settings: AppSettings = AppSettings()
    private var cards: List<UserEntry> = emptyList()
    private var plan: PdfExporter.PagePlan? = null
    private var files = mutableListOf<File>()
    private var pdfParts = mutableListOf<Store.PdfPart>()
    private var nextPage = 0
    private var nextCard = 0
    private var printNo = 0
    private var dateText = ""
    private var timeText = ""
    private var connectionFactory: (() -> DeviceConnection)? = null
    private var batchSaved = false
    private var cardsFile = "print_job_cards.json"
    private val _pdfMetrics = MutableStateFlow<com.binwaps.cardmanager.performance.ThroughputMeter.Snapshot?>(null)
    val pdfMetrics: StateFlow<com.binwaps.cardmanager.performance.ThroughputMeter.Snapshot?> = _pdfMetrics

    // ==================== الفحص المسبق ====================

    /** يعيد قائمة عوائق بالعربية — فارغة يعني جاهز للطباعة */
    fun preflight(
        template: CardTemplate?,
        users: List<UserEntry>,
        settings: AppSettings,
        thermal: Boolean,
    ): List<String> {
        val issues = mutableListOf<String>()
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) issues += "تحقق من الاشتراك قبل الطباعة"
        if (template == null) {
            issues += "لا يوجد قالب — أنشئ قالباً من قسم القوالب"
        } else {
            val empty = if (template.layoutMode == CardLayoutMode.TABLE)
                template.rows.all { it.cells.isEmpty() }
            else template.fields.none { it.visible }
            if (empty) issues += "القالب فارغ — أضف حقولاً أو صفوفاً في محرر القالب"
            // كل صور القالب (الخلفية + شعارات الحقول والخلايا) — شعار مفقود كان يمرّ
            // من الفحص ثم يُرسم الكرت بلا شعار صامتاً
            val missing = Store.templateImagePaths(template).filter { !File(it).exists() }
            if (missing.isNotEmpty()) {
                issues += if (template.backgroundPath in missing) "صورة خلفية القالب مفقودة — ارفعها من جديد أو أزلها"
                else "صورة/شعار في القالب مفقود — أعد اختياره من محرر القالب أو أزله"
            }
        }
        if (users.isEmpty()) issues += "لا توجد كروت — ولّد أو اجلب كروتاً أولاً"
        if (settings.printFrom > 0 && settings.printTo in 1 until settings.printFrom) {
            issues += "نطاق الطباعة مقلوب: «من» أكبر من «إلى»"
        }
        if (!thermal && settings.layout.marginMm * 2 >= settings.layout.pageWidthMm) {
            issues += "الهوامش أكبر من عرض الصفحة — صغّرها من تخطيط الصفحة"
        }
        return issues
    }

    fun isRunning(): Boolean = _state.value is State.Running || job?.isCompleted == false

    fun hasPendingJob(): Boolean = isRunning() || _state.value is State.Failed || _state.value is State.Restorable

    // ==================== PDF ====================

    @Synchronized
    fun startPdf(context: Context, template: CardTemplate, users: List<UserEntry>, settings: AppSettings,
                 productionBatch: Boolean = false): Boolean {
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) return false
        if (hasPendingJob() || (!productionBatch && com.binwaps.cardmanager.data.ProductionEngine.state.value.busy)) {
            com.binwaps.cardmanager.data.EventLog.log("طباعة", "تم تجاهل الطلب — مهمة طباعة جارية بالفعل", ok = false)
            return false
        }
        com.binwaps.cardmanager.data.EventLog.log(
            "طباعة",
            "بدء PDF: ${users.size} كرت، قالب «${template.name}»، ورق ${settings.paperType}",
        )
        val appContext = context.applicationContext
        savedContext = appContext
        this.template = template
        this.settings = settings
        this.cards = PdfExporter.selectRange(users, settings)
        this.plan = PdfExporter.plan(template, users, settings)
        this.files = mutableListOf()
        this.pdfParts = mutableListOf()
        this.nextPage = 0
        this.batchSaved = false
        _savedTo.value = null
        _pdfMetrics.value = null
        stampRun()
        cardsFile = "print_job_cards_${java.util.UUID.randomUUID()}.json"
        // الحالة «جارية» تُثبَّت فوراً لا داخل المهمة: ضغطتان سريعتان كانتا تطلقان
        // مهمتين تتشاركان الحقول (files/nextPage) قبل أن يمنعهما isRunning
        _state.value = State.Running(Kind.PDF, 0, plan?.pages?.size ?: 0, "تجهيز الملف…")
        runPdf(appContext)
        return true
    }

    private fun stampRun() {
        printNo = Store.nextPrintNo()
        val now = Date()
        dateText = SimpleDateFormat("yyyy/MM/dd", Locale.US).format(now)
        timeText = SimpleDateFormat("HH:mm", Locale.US).format(now)
    }

    /** Verify the saved prefix on the IO dispatcher before reusing any PDF part. */
    private fun restorePdfParts(appContext: Context, active: () -> Boolean = { true }) {
        val p = plan ?: return
        val chunks = PdfParts(p.pages.size, p.copies, settings.splitLargePdf)
        val validRangeCount = (0 until minOf(pdfParts.size, chunks.size)).takeWhile { i ->
            val part = pdfParts[i]
            val expected = chunks[i]
            part.from == expected.from && part.toExclusive == expected.toExclusive
        }.size
        val candidates = pdfParts.take(validRangeCount)
        val dir = File(appContext.cacheDir, "exports")
        val valid = chunks.verifiedPrefix(dir, candidates.map { it.fileName }, candidates.map { it.sha256 }) { active() }
        pdfParts = candidates.take(valid).toMutableList()
        files = pdfParts.map { PdfParts.resolve(dir, it.fileName) }.toMutableList()
        nextPage = chunks.pagesCompleted(valid)
    }

    private fun runPdf(appContext: Context) {
        val t = template ?: return
        val p = plan ?: return
        val totalPages = p.pages.size
        job = scope.launch {
            val chunks = PdfParts(totalPages, p.copies, settings.splitLargePdf)
            var attemptStart = 0
            var meter = com.binwaps.cardmanager.performance.ThroughputMeter(p.totalCards, System.nanoTime())
            var rendered = 0
            var lastEmit = 0L
            fun sample() {
                val measured = meter.sample((rendered - attemptStart).coerceAtLeast(0), System.nanoTime())
                _pdfMetrics.value = com.binwaps.cardmanager.performance.ThroughputMeter.withOverallCount(measured, rendered, p.totalCards)
            }
            try {
                _state.value = State.Running(Kind.PDF, nextPage, totalPages, "فحص الأجزاء المحفوظة…")
                restorePdfParts(appContext) { isActive }
                attemptStart = p.cardsBefore(nextPage)
                rendered = attemptStart
                meter = com.binwaps.cardmanager.performance.ThroughputMeter(p.totalCards - attemptStart, System.nanoTime())
                sample()
                // Wait until the initial payload and current checkpoint are on disk.
                persist(Kind.PDF, includeCards = true)?.await()
                for (index in pdfParts.size until chunks.size) {
                    ensureActive()
                    check(com.binwaps.cardmanager.license.LicenseManager.isUsable()) { "انتهت صلاحية التحقق من الاشتراك — حدّث الاشتراك ثم استأنف" }
                    val range = chunks[index]
                    val jobId = cardsFile.removePrefix("print_job_cards_").removeSuffix(".json")
                    val name = "cards_${jobId}_${(index + 1).toString().padStart(4, '0')}_of_${chunks.size}.pdf"
                    val file = PdfExporter.exportPages(
                        appContext, t, settings, p, range.from, range.toExclusive,
                        printNo, dateText, timeText, fileName = name, isActive = { isActive },
                    ) { pageDone ->
                        rendered = p.cardsBefore(pageDone + 1)
                        val now = System.nanoTime()
                        if (isActive && (now - lastEmit >= 150_000_000L || pageDone + 1 == range.toExclusive)) {
                            lastEmit = now
                            sample()
                            _state.value = State.Running(Kind.PDF, pageDone + 1, totalPages,
                                "ملف ${index + 1} من ${chunks.size} • " +
                                    if (pageDone + 1 == range.toExclusive) "حفظ الجزء…" else "صفحة ${pageDone + 1} من $totalPages")
                        }
                    }
                    ensureActive()
                    val digest = PdfParts.fingerprint(file) { isActive }
                    pdfParts.add(Store.PdfPart(file.name, digest, range.from, range.toExclusive))
                    files.add(file)
                    nextPage = range.toExclusive
                    persist(Kind.PDF)?.await()
                }
                ensureActive()
                rendered = p.totalCards
                sample()
                finishJob(Kind.PDF, p.totalCards)
            } catch (e: Throwable) {
                if (!isActive || e is kotlinx.coroutines.CancellationException) return@launch
                // Count only complete files; a failed metadata write may rebuild the last part after restart.
                rendered = p.cardsBefore(nextPage)
                sample()
                _state.value = State.Failed(Kind.PDF, nextPage, totalPages,
                    friendly(e) + " — حُفظ ${pdfParts.size} ملف مكتمل، اضغط استكمال")
            }
        }
    }

    // ==================== الحرارية ====================

    @Synchronized
    fun startThermal(
        context: Context,
        template: CardTemplate,
        users: List<UserEntry>,
        settings: AppSettings,
        connect: () -> DeviceConnection,
    ) {
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) return
        if (hasPendingJob() || com.binwaps.cardmanager.data.ProductionEngine.state.value.busy) return
        val appContext = context.applicationContext
        savedContext = appContext
        this.template = template
        this.settings = settings
        this.cards = PdfExporter.selectRange(users, settings)
        this.connectionFactory = connect
        this.nextCard = 0
        this.files = mutableListOf()
        this.pdfParts = mutableListOf()
        this.batchSaved = false
        _savedTo.value = null
        _pdfMetrics.value = null
        stampRun()
        cardsFile = "print_job_cards_${java.util.UUID.randomUUID()}.json"
        persist(Kind.THERMAL, includeCards = true)
        _state.value = State.Running(Kind.THERMAL, 0, cards.size, "الاتصال بالطابعة…")
        runThermal(appContext)
    }

    private fun runThermal(appContext: Context) {
        val t = template ?: return
        val factory = connectionFactory ?: return
        val toPrint = cards
        job = scope.launch {
            _state.value = State.Running(Kind.THERMAL, nextCard, toPrint.size, "الاتصال بالطابعة…")

            var connection: DeviceConnection? = null
            var printer: EscPosPrinter? = null

            fun closeQuietly() {
                runCatching { printer?.disconnectPrinter() }
                printer = null
                connection = null
            }

            fun ensurePrinter(): EscPosPrinter {
                printer?.let { return it }
                val conn = factory()
                connection = conn
                val widthMm = ThermalPrinter.printableWidthMm(settings.paperType)
                val chars = ThermalPrinter.charsPerLine(settings.paperType)
                return EscPosPrinter(conn, settings.thermalDpi, widthMm, chars).also {
                    if (settings.escAsteriskMode) it.useEscAsteriskCommand(true)
                    printer = it
                }
            }

            try {
                val dotsPerMm = settings.thermalDpi / 25.4f
                val widthPx = (ThermalPrinter.printableWidthMm(settings.paperType) * dotsPerMm).toInt()
                val heightPx = (settings.thermalCardHeightMm * dotsPerMm).toInt().coerceAtLeast(32)

                while (nextCard < toPrint.size && isActive) {
                    check(com.binwaps.cardmanager.license.LicenseManager.isUsable()) { "تحقق من الاشتراك ثم استأنف الطباعة" }
                    val user = toPrint[nextCard]
                    val info = com.binwaps.cardmanager.model.RenderInfo(
                        pageNumber = nextCard + 1, cardNumber = nextCard + 1,
                        printNo = printNo, dateText = dateText, timeText = timeText,
                    )

                    var lastError: Throwable? = null
                    var printed = false
                    // ثلاث محاولات لكل كرت — انقطاع البلوتوث لحظةً لا يفشل الدفعة
                    for (attempt in 1..THERMAL_RETRIES) {
                        try {
                            val pr = ensurePrinter()
                            val rendered = CardRenderer.renderSafe(t, user, settings, widthPx, info)
                            val scaled = if (rendered.width != widthPx || rendered.height != heightPx) {
                                android.graphics.Bitmap.createScaledBitmap(rendered, widthPx, heightPx, true)
                                    .also { rendered.recycle() }
                            } else rendered
                            val text = ThermalPrinter.buildImageText(pr, scaled)
                            scaled.recycle()
                            val isLast = nextCard == toPrint.size - 1
                            if (settings.autoCut && isLast) {
                                pr.printFormattedTextAndCut(text, settings.thermalFeedMm)
                            } else {
                                pr.printFormattedText(text, settings.thermalFeedMm)
                            }
                            printed = true
                            break
                        } catch (e: kotlinx.coroutines.CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            lastError = e
                            closeQuietly()
                            if (attempt < THERMAL_RETRIES) delay(700L * attempt)
                        }
                    }
                    // أُلغيت أثناء الطباعة: لا نكتب أي حالة بعد «إيقاف» المستخدم —
                    // كتابة Running بعد الإلغاء كانت تُبقي الشاشة على «جارية» بلا مهمة
                    if (!isActive) return@launch

                    if (!printed) {
                        _state.value = State.Failed(
                            Kind.THERMAL, nextCard, toPrint.size,
                            friendly(lastError) + " — طُبع $nextCard من ${toPrint.size}، " +
                                "تأكد من الطابعة ثم اضغط استئناف ليكمل من الكرت ${nextCard + 1}",
                        )
                        persist(Kind.THERMAL)
                        return@launch
                    }

                    nextCard++
                    _state.value = State.Running(Kind.THERMAL, nextCard, toPrint.size, "كرت $nextCard من ${toPrint.size}")
                    if (nextCard % 5 == 0) persist(Kind.THERMAL)
                }
                if (nextCard >= toPrint.size && isActive) finishJob(Kind.THERMAL, toPrint.size)
            } finally {
                closeQuietly()
            }
        }
    }

    // ==================== الاستئناف والإلغاء ====================

    /** يستأنف PDF من أول جزء غير مكتمل، والحرارية من آخر تأكيد داخل الجلسة. */
    @Synchronized
    fun resume(context: Context) {
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) return
        val s = _state.value
        if (s !is State.Failed || job?.isCompleted == false) return
        _state.value = State.Running(s.kind, s.done, s.total, "استئناف المهمة…")
        when (s.kind) {
            Kind.PDF -> runPdf(context.applicationContext)
            Kind.THERMAL -> runThermal(context.applicationContext)
        }
    }

    /** للحرارية بعد إعادة فتح التطبيق: نحتاج اختيار الطابعة من جديد */
    @Synchronized
    fun resumeThermalWith(context: Context, connect: () -> DeviceConnection) {
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) return
        if (isRunning()) return
        if (_state.value !is State.Failed && _state.value !is State.Restorable) return
        connectionFactory = connect
        _state.value = State.Running(Kind.THERMAL, nextCard, cards.size, "الاتصال بالطابعة…")
        runThermal(context.applicationContext)
    }

    @Synchronized
    fun cancel() {
        val stopping = job
        if (stopping == null || stopping.isCompleted) {
            _state.value = State.Idle
            clearPersisted()
            return
        }
        val s = _state.value as? State.Running
        if (s != null) _state.value = s.copy(label = "إيقاف المهمة وحفظ التقدم…")
        stopping.invokeOnCompletion {
            synchronized(this@PrintEngine) {
                if (job === stopping) {
                    job = null
                    if (s?.kind == Kind.PDF) {
                        _state.value = State.Failed(Kind.PDF, nextPage, plan?.pages?.size ?: 0,
                            "أُوقفت المهمة — ${pdfParts.size} ملف مكتمل. يمكن استكمال الأجزاء المتبقية.")
                        persist(Kind.PDF, includeCards = true)
                    } else {
                        _state.value = State.Idle
                        clearPersisted()
                    }
                }
            }
        }
        stopping.cancel()
    }

    /** بعد اكتمال مهمة: العودة للوضع الطبيعي (الملفات تبقى للمشاركة من السجل) */
    fun acknowledge() {
        if (_state.value is State.Done) _state.value = State.Idle
        _savedTo.value = null
    }

    private fun finishJob(kind: Kind, totalCards: Int) {
        saveBatchOnce()
        _state.value = State.Done(kind, totalCards, files.toList())
        clearPersisted()
        com.binwaps.cardmanager.data.EventLog.log(
            "طباعة",
            "اكتمل ${if (kind == Kind.PDF) "PDF" else "حراري"}: $totalCards كرت، ${files.size} ملف",
        )
        // حفظ تلقائي في «التنزيلات» — كل شيء تلقائي بلا ضغطة زر
        if (kind == Kind.PDF) {
            val ctx = savedContext
            val toSave = files.toList()
            val completedJobId = cardsFile
            if (ctx != null && toSave.isNotEmpty()) {
                scope.launch {
                    val names = toSave.mapNotNull { PdfExporter.saveToDownloads(ctx, it) }
                    if (names.isNotEmpty()) {
                        if (cardsFile == completedJobId && _state.value is State.Done) {
                            _savedTo.value = names.joinToString("، ")
                        }
                        com.binwaps.cardmanager.data.EventLog.log(
                            "طباعة", "حُفظ تلقائياً في التنزيلات: ${names.joinToString("، ")}",
                        )
                    }
                }
            }
        }
    }

    /** آخر ملف حُفظ تلقائياً في التنزيلات — لعرض تأكيد للمستخدم */
    private val _savedTo = MutableStateFlow<String?>(null)
    val savedTo: StateFlow<String?> get() = _savedTo

    fun clearSavedTo() { _savedTo.value = null }

    private fun saveBatchOnce() {
        if (batchSaved) return
        batchSaved = true
        val t = template ?: return
        Store.addBatch(
            PrintBatch(
                id = Store.newId(),
                createdAt = System.currentTimeMillis(),
                templateId = t.id,
                templateName = t.name,
                profile = cards.firstOrNull()?.profile ?: "",
                unitPrice = cards.firstOrNull()?.price ?: "",
                paper = settings.paperType,
                users = cards,
            )
        )
    }

    // ==================== الحفظ على القرص ====================

    private fun persist(kind: Kind, includeCards: Boolean = false): kotlinx.coroutines.Deferred<Unit>? {
        val t = template ?: return null
        return Store.savePrintJob(
            Store.PrintJobMeta(
                kind = kind.name,
                templateId = t.id,
                next = if (kind == Kind.PDF) nextPage else nextCard,
                total = if (kind == Kind.PDF) (plan?.pages?.size ?: 0) else cards.size,
                createdAt = System.currentTimeMillis(),
                cardsFile = cardsFile,
                templateSnapshot = t,
                settingsSnapshot = settings,
                printNo = printNo, dateText = dateText, timeText = timeText,
                pdfParts = if (kind == Kind.PDF) pdfParts.toList() else emptyList(),
            ),
            if (includeCards) cards else null,
        )
    }

    private fun clearPersisted() = Store.clearPrintJob()

    /**
     * يُستدعى عند فتح التطبيق: إن وُجدت مهمة غير مكتملة من جلسة سابقة
     * تُعرض للمستخدم «استئناف» بدل أن يبدأ من الصفر.
     */
    @Synchronized
    fun restoreIfAny() {
        if (_state.value !is State.Idle) return
        val meta = Store.loadPrintJobMeta() ?: return
        val savedCards = Store.loadPrintJobCards()
        val t = meta.templateSnapshot ?: Store.template(meta.templateId)
        if (savedCards.isEmpty() || t == null) {
            clearPersisted()
            return
        }
        template = t
        settings = (meta.settingsSnapshot ?: Store.settings.value).copy(printFrom = 0, printTo = 0)
        cards = savedCards
        cardsFile = meta.cardsFile
        printNo = meta.printNo
        dateText = meta.dateText
        timeText = meta.timeText
        if (printNo <= 0) stampRun()
        if (meta.kind == Kind.PDF.name) {
            // إعادة بناء الخطة من اللقطة المحفوظة
            plan = PdfExporter.plan(t, savedCards, settings)
            pdfParts = meta.pdfParts.toMutableList()
            nextPage = meta.next.coerceIn(0, plan?.pages?.size ?: 0)
            _state.value = State.Restorable(Kind.PDF, nextPage, plan?.pages?.size ?: 0)
        } else {
            nextCard = meta.next.coerceIn(0, savedCards.size)
            _state.value = State.Restorable(Kind.THERMAL, nextCard, savedCards.size)
        }
    }

    /** استئناف مهمة مستعادة من جلسة سابقة (PDF فقط — الحرارية تحتاج اختيار طابعة) */
    @Synchronized
    fun resumeRestored(context: Context) {
        if (!com.binwaps.cardmanager.license.LicenseManager.isUsable()) return
        val s = _state.value
        if (s !is State.Restorable || isRunning()) return
        savedContext = context.applicationContext
        batchSaved = false
        if (s.kind == Kind.PDF) {
            _state.value = State.Running(Kind.PDF, nextPage, s.total, "استعادة المهمة…")
            runPdf(context.applicationContext)
        }
    }

    fun dismissRestored() {
        if (_state.value is State.Restorable) {
            _state.value = State.Idle
            clearPersisted()
        }
    }

    private fun friendly(t: Throwable?): String {
        val raw = t?.message ?: "خطأ غير معروف"
        return when {
            // رسالة OutOfMemoryError لا تحوي اسم الصنف («Failed to allocate…») — نفحص النوع
            t is OutOfMemoryError -> "الذاكرة ممتلئة — أغلق تطبيقات أخرى ثم استأنف"
            raw.contains("ENOSPC", true) || raw.contains("No space", true) ->
                "امتلأت ذاكرة الجوال — احذف ملفات ثم استأنف"
            raw.contains("Broken pipe", true) || raw.contains("socket", true) ||
                raw.contains("connection", true) || raw.contains("bluetooth", true) ->
                "انقطع الاتصال بالطابعة"
            raw.contains("OutOfMemory", true) ->
                "الذاكرة ممتلئة — أغلق تطبيقات أخرى ثم استأنف"
            else -> raw
        }
    }
}
