package com.binwaps.cardmanager.print

import android.content.Context
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardLayoutMode
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.PrintBatch
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
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
 * محرك الطباعة الصامد — الهدف: صفر فشل يعيدك من البداية.
 *
 * - يعمل في خلفية التطبيق: الخروج من شاشة الطباعة لا يوقف المهمة.
 * - PDF ملف واحد دائماً مهما كان العدد. الرسم متجهي فالدفعات الضخمة
 *   تكتمل في ثوانٍ، وأي فشل يعيد البناء تلقائياً بلا تدخل.
 * - الحرارية: إعادة محاولة لكل كرت (3 مرات بإعادة اتصال)، والاستئناف من
 *   الكرت الذي توقف عنده بالضبط.
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

        /** فشل قابل للاستئناف — لا شيء ضاع */
        data class Failed(val kind: Kind, val done: Int, val total: Int, val error: String) : State

        data class Done(val kind: Kind, val total: Int, val files: List<File>) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> get() = _state

    /**
     * أي خطأ يفلت من داخل مهمة الطباعة يتحول إلى حالة «متوقفة» قابلة للاستئناف
     * بدل أن يُسقط التطبيق كله — الطباعة لا تفشل فشلاً كارثياً أبداً.
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

    // لقطة المهمة الحالية — تبقى في الذاكرة للاستئناف الفوري
    private var template: CardTemplate? = null
    private var settings: AppSettings = AppSettings()
    private var cards: List<UserEntry> = emptyList()
    private var plan: PdfExporter.PagePlan? = null
    private var files = mutableListOf<File>()
    private var nextPage = 0
    private var nextCard = 0
    private var printNo = 0
    private var dateText = ""
    private var timeText = ""
    private var connectionFactory: (() -> DeviceConnection)? = null
    private var batchSaved = false

    // ==================== الفحص المسبق ====================

    /** يعيد قائمة عوائق بالعربية — فارغة يعني جاهز للطباعة */
    fun preflight(
        template: CardTemplate?,
        users: List<UserEntry>,
        settings: AppSettings,
        thermal: Boolean,
    ): List<String> {
        val issues = mutableListOf<String>()
        if (template == null) {
            issues += "لا يوجد قالب — أنشئ قالباً من قسم القوالب"
        } else {
            val empty = if (template.layoutMode == CardLayoutMode.TABLE)
                template.rows.all { it.cells.isEmpty() }
            else template.fields.none { it.visible }
            if (empty) issues += "القالب فارغ — أضف حقولاً أو صفوفاً في محرر القالب"
            if (template.backgroundPath.isNotBlank() && !File(template.backgroundPath).exists()) {
                issues += "صورة خلفية القالب مفقودة — ارفعها من جديد أو أزلها"
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

    fun isRunning(): Boolean = _state.value is State.Running

    // ==================== PDF ====================

    fun startPdf(context: Context, template: CardTemplate, users: List<UserEntry>, settings: AppSettings) {
        if (isRunning()) {
            com.binwaps.cardmanager.data.EventLog.log("طباعة", "تم تجاهل الطلب — مهمة طباعة جارية بالفعل", ok = false)
            return
        }
        com.binwaps.cardmanager.data.EventLog.log(
            "طباعة",
            "بدء PDF: ${users.size} كرت، قالب «${template.name}»، ورق ${settings.paperType}",
        )
        val appContext = context.applicationContext
        this.template = template
        this.settings = settings
        this.cards = PdfExporter.selectRange(users, settings)
        this.plan = PdfExporter.plan(template, users, settings)
        this.files = mutableListOf()
        this.nextPage = 0
        this.batchSaved = false
        stampRun()
        persist(Kind.PDF)
        runPdf(appContext)
    }

    private fun stampRun() {
        printNo = Store.nextPrintNo()
        val now = Date()
        dateText = SimpleDateFormat("yyyy/MM/dd", Locale.US).format(now)
        timeText = SimpleDateFormat("HH:mm", Locale.US).format(now)
    }

    private fun runPdf(appContext: Context) {
        val t = template ?: return
        val p = plan ?: return
        val totalPages = p.pages.size
        job = scope.launch {
            _state.value = State.Running(Kind.PDF, 0, totalPages, "تجهيز الملف…")
            try {
                // ملف واحد دائماً — الرسم متجهي فحتى آلاف الكروت ثوانٍ معدودة
                val file = PdfExporter.exportPages(
                    appContext, t, settings, p, 0, totalPages,
                    printNo, dateText, timeText,
                ) { pageDone ->
                    _state.value = State.Running(
                        Kind.PDF, pageDone + 1, totalPages,
                        "صفحة ${pageDone + 1} من $totalPages",
                    )
                }
                files = mutableListOf(file)
                nextPage = totalPages
                finishJob(Kind.PDF, p.totalCards)
            } catch (e: Throwable) {
                // Throwable لا Exception: نفاد الذاكرة مع الدفعات الضخمة كان
                // يهرب من الالتقاط ويُسقط التطبيق بدل أن يصير حالة قابلة للاستئناف
                _state.value = State.Failed(
                    Kind.PDF, 0, totalPages,
                    friendly(e) + " — اضغط استئناف وسيُعاد بناء الملف في ثوانٍ",
                )
                persist(Kind.PDF)
            }
        }
    }

    // ==================== الحرارية ====================

    fun startThermal(
        context: Context,
        template: CardTemplate,
        users: List<UserEntry>,
        settings: AppSettings,
        connect: () -> DeviceConnection,
    ) {
        if (isRunning()) return
        val appContext = context.applicationContext
        this.template = template
        this.settings = settings
        this.cards = PdfExporter.selectRange(users, settings)
        this.connectionFactory = connect
        this.nextCard = 0
        this.files = mutableListOf()
        this.batchSaved = false
        stampRun()
        persist(Kind.THERMAL)
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
                        } catch (e: Exception) {
                            lastError = e
                            closeQuietly()
                            if (attempt < THERMAL_RETRIES) delay(700L * attempt)
                        }
                    }

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
                if (nextCard >= toPrint.size) finishJob(Kind.THERMAL, toPrint.size)
            } finally {
                closeQuietly()
            }
        }
    }

    // ==================== الاستئناف والإلغاء ====================

    /** يستأنف المهمة الفاشلة من نقطة التوقف بالضبط */
    fun resume(context: Context) {
        val s = _state.value
        if (s !is State.Failed) return
        when (s.kind) {
            Kind.PDF -> runPdf(context.applicationContext)
            Kind.THERMAL -> runThermal(context.applicationContext)
        }
    }

    /** للحرارية بعد إعادة فتح التطبيق: نحتاج اختيار الطابعة من جديد */
    fun resumeThermalWith(context: Context, connect: () -> DeviceConnection) {
        connectionFactory = connect
        runThermal(context.applicationContext)
    }

    fun cancel() {
        job?.cancel()
        job = null
        _state.value = State.Idle
        clearPersisted()
    }

    /** بعد اكتمال مهمة: العودة للوضع الطبيعي (الملفات تبقى للمشاركة من السجل) */
    fun acknowledge() {
        if (_state.value is State.Done) _state.value = State.Idle
    }

    private fun finishJob(kind: Kind, totalCards: Int) {
        saveBatchOnce()
        _state.value = State.Done(kind, totalCards, files.toList())
        clearPersisted()
        com.binwaps.cardmanager.data.EventLog.log(
            "طباعة",
            "اكتمل ${if (kind == Kind.PDF) "PDF" else "حراري"}: $totalCards كرت، ${files.size} ملف",
        )
    }

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

    private fun persist(kind: Kind) {
        val t = template ?: return
        Store.savePrintJob(
            Store.PrintJobMeta(
                kind = kind.name,
                templateId = t.id,
                next = if (kind == Kind.PDF) nextPage else nextCard,
                total = if (kind == Kind.PDF) (plan?.pages?.size ?: 0) else cards.size,
                createdAt = System.currentTimeMillis(),
            ),
            cards,
        )
    }

    private fun clearPersisted() = Store.clearPrintJob()

    /**
     * يُستدعى عند فتح التطبيق: إن وُجدت مهمة غير مكتملة من جلسة سابقة
     * تُعرض للمستخدم «استئناف» بدل أن يبدأ من الصفر.
     */
    fun restoreIfAny() {
        if (_state.value !is State.Idle) return
        val meta = Store.loadPrintJobMeta() ?: return
        val savedCards = Store.loadPrintJobCards()
        val t = Store.template(meta.templateId)
        if (savedCards.isEmpty() || t == null) {
            clearPersisted()
            return
        }
        template = t
        settings = Store.settings.value
        cards = savedCards
        if (meta.kind == Kind.PDF.name) {
            // إعادة بناء الخطة من اللقطة المحفوظة
            plan = PdfExporter.plan(t, savedCards, settings.copy(printFrom = 0, printTo = 0, startCell = 1))
            nextPage = 0
            stampRun()
            _state.value = State.Restorable(Kind.PDF, meta.next, plan?.pages?.size ?: 0)
        } else {
            nextCard = meta.next.coerceIn(0, savedCards.size)
            stampRun()
            _state.value = State.Restorable(Kind.THERMAL, nextCard, savedCards.size)
        }
    }

    /** استئناف مهمة مستعادة من جلسة سابقة (PDF فقط — الحرارية تحتاج اختيار طابعة) */
    fun resumeRestored(context: Context) {
        val s = _state.value
        if (s !is State.Restorable) return
        if (s.kind == Kind.PDF) runPdf(context.applicationContext)
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
