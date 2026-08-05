package com.binwaps.cardmanager.print

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import androidx.core.content.FileProvider
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.CutMarkStyle
import com.binwaps.cardmanager.model.RenderInfo
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * تصدير الكروت كشبكة على الورق بصيغة PDF.
 * سريع: يرسم كل كرت مرة واحدة بدقة مناسبة ويعيد استخدام كائنات الرسم.
 */
object PdfExporter {

    private const val MM_TO_PT = 72f / 25.4f
    private const val RENDER_DPI = 300

    /** معلومات التخطيط لعرضها للمستخدم قبل الطباعة */
    data class LayoutInfo(
        val columns: Int,
        val rows: Int,
        val perPage: Int,
        val pages: Int,
        val cardWidthMm: Float,
        val cardHeightMm: Float,
    )

    fun computeLayout(template: CardTemplate, settings: AppSettings, cardCount: Int): LayoutInfo {
        val layout = settings.layout
        var cw = template.widthMm
        var ch = template.heightMm
        val (cols, rows) = layout.gridFor(cw, ch)

        if (layout.stretchToFit || !layout.autoFit) {
            val usableW = layout.pageWidthMm - 2 * layout.marginMm - (cols - 1) * layout.hSpacingMm
            val usableH = layout.pageHeightMm - 2 * layout.marginMm - (rows - 1) * layout.vSpacingMm
            val fitW = usableW / cols
            val fitH = usableH / rows
            if (layout.stretchToFit) {
                // نحافظ على نسبة الكرت ونكبّره لأقصى حد يسع الخلية
                val scale = minOf(fitW / cw, fitH / ch)
                cw *= scale
                ch *= scale
            } else {
                cw = minOf(cw, fitW)
                ch = minOf(ch, fitH)
            }
        }

        val perPage = (cols * rows).coerceAtLeast(1)
        val pages = if (cardCount == 0) 0 else (cardCount + perPage - 1) / perPage
        return LayoutInfo(cols, rows, perPage, pages, cw, ch)
    }

    /** يطبّق نطاق الطباعة المختار (من كرت … إلى كرت …) */
    fun selectRange(users: List<UserEntry>, settings: AppSettings): List<UserEntry> {
        if (users.isEmpty()) return users
        val from = (if (settings.printFrom > 0) settings.printFrom else 1).coerceIn(1, users.size)
        val to = (if (settings.printTo > 0) settings.printTo else users.size).coerceIn(from, users.size)
        return users.subList(from - 1, to)
    }

    /** خطة الطباعة: الصفحات جاهزة للتقسيم والاستئناف */
    data class PagePlan(
        val info: LayoutInfo,
        val pages: List<List<UserEntry?>>,
        val copies: Int,
        val totalCards: Int,
    )

    fun plan(template: CardTemplate, allUsers: List<UserEntry>, settings: AppSettings): PagePlan {
        val selected = selectRange(allUsers, settings)
        val info = computeLayout(template, settings, selected.size)
        val skip = (settings.startCell - 1).coerceIn(0, (info.perPage - 1).coerceAtLeast(0))
        val users: List<UserEntry?> = List(skip) { null } + selected
        return PagePlan(info, users.chunked(info.perPage), settings.copies.coerceIn(1, 20), selected.size)
    }

    /**
     * يكتب نطاقاً من صفحات الخطة إلى ملف واحد — أساس الاستئناف:
     * الفشل في وسط دفعة ضخمة لا يعيدك من البداية، بل من هذه القطعة فقط.
     */
    fun exportPages(
        context: Context,
        template: CardTemplate,
        settings: AppSettings,
        plan: PagePlan,
        fromPage: Int,
        toPageExclusive: Int,
        printNo: Int,
        dateText: String,
        timeText: String,
        onPageDone: (Int) -> Unit = { },
    ): File {
        val layout = settings.layout
        val info = plan.info
        val pageW = (layout.pageWidthMm * MM_TO_PT).toInt()
        val pageH = (layout.pageHeightMm * MM_TO_PT).toInt()
        val margin = layout.marginMm * MM_TO_PT
        val hGap = layout.hSpacingMm * MM_TO_PT
        val vGap = layout.vSpacingMm * MM_TO_PT
        val cardW = info.cardWidthMm * MM_TO_PT
        val cardH = info.cardHeightMm * MM_TO_PT
        val gridW = info.columns * cardW + (info.columns - 1) * hGap
        val gridH = info.rows * cardH + (info.rows - 1) * vGap
        val offsetX = ((pageW - gridW) / 2f).coerceAtLeast(margin) + settings.offsetXMm * MM_TO_PT
        val offsetY = ((pageH - gridH) / 2f).coerceAtLeast(margin) + settings.offsetYMm * MM_TO_PT
        val renderW = (info.cardWidthMm / 25.4f * RENDER_DPI).toInt().coerceIn(64, 2000)
        val (cellW, cellH) = CardRenderer.renderSize(template, renderW)

        val doc = PdfDocument()
        val markPaint = Paint().apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.5f
            color = 0xFF9E9E9E.toInt()
        }
        val dashPaint = Paint(markPaint).apply {
            pathEffect = android.graphics.DashPathEffect(floatArrayOf(4f, 4f), 0f)
        }

        var pdfPageNo = 0
        var cardsBefore = plan.pages.take(fromPage).sumOf { pg -> pg.count { it != null } }

        for (pageIndex in fromPage until toPageExclusive.coerceAtMost(plan.pages.size)) {
            val pageUsers = plan.pages[pageIndex]
            repeat(plan.copies) {
                pdfPageNo++
                val page = doc.startPage(PdfDocument.PageInfo.Builder(pageW, pageH, pdfPageNo).create())
                val canvas = page.canvas
                var localCard = 0
                pageUsers.forEachIndexed { i, user ->
                    val col = i % info.columns
                    val row = i / info.columns
                    val left = offsetX + col * (cardW + hGap)
                    val top = offsetY + row * (cardH + vGap)
                    val rect = RectF(left, top, left + cardW, top + cardH)
                    if (user == null) {
                        drawCutMarks(canvas, rect, layout.cutMarks, markPaint, dashPaint)
                        return@forEachIndexed
                    }
                    localCard++
                    val ri = RenderInfo(
                        pageNumber = pageIndex + 1,
                        cardNumber = cardsBefore + localCard,
                        printNo = printNo,
                        dateText = dateText,
                        timeText = timeText,
                    )
                    canvas.save()
                    canvas.translate(rect.left, rect.top)
                    canvas.scale(rect.width() / cellW.toFloat(), rect.height() / cellH.toFloat())
                    runCatching { CardRenderer.drawCard(canvas, template, user, settings, cellW, cellH, ri) }
                    canvas.restore()
                    drawCutMarks(canvas, rect, layout.cutMarks, markPaint, dashPaint)
                }
                doc.finishPage(page)
            }
            cardsBefore += pageUsers.count { it != null }
            onPageDone(pageIndex)
        }

        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "cards_${System.currentTimeMillis()}.pdf")
        FileOutputStream(file).use { doc.writeTo(it) }
        doc.close()
        return file
    }

    fun export(
        context: Context,
        template: CardTemplate,
        allUsers: List<UserEntry>,
        settings: AppSettings,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): File {
        val layout = settings.layout
        val selected = selectRange(allUsers, settings)
        val info = computeLayout(template, settings, selected.size)

        // البدء من خلية معيّنة: نترك خلايا فارغة في أول صفحة
        val skip = (settings.startCell - 1).coerceIn(0, (info.perPage - 1).coerceAtLeast(0))
        val users: List<UserEntry?> = List(skip) { null } + selected

        val pageW = (layout.pageWidthMm * MM_TO_PT).toInt()
        val pageH = (layout.pageHeightMm * MM_TO_PT).toInt()
        val margin = layout.marginMm * MM_TO_PT
        val hGap = layout.hSpacingMm * MM_TO_PT
        val vGap = layout.vSpacingMm * MM_TO_PT
        val cardW = info.cardWidthMm * MM_TO_PT
        val cardH = info.cardHeightMm * MM_TO_PT

        // توسيط الشبكة أفقياً وعمودياً في الصفحة
        val gridW = info.columns * cardW + (info.columns - 1) * hGap
        val gridH = info.rows * cardH + (info.rows - 1) * vGap
        // التوسيط + معايرة الطابعة
        val offsetX = ((pageW - gridW) / 2f).coerceAtLeast(margin) + settings.offsetXMm * MM_TO_PT
        val offsetY = ((pageH - gridH) / 2f).coerceAtLeast(margin) + settings.offsetYMm * MM_TO_PT

        val renderW = (info.cardWidthMm / 25.4f * RENDER_DPI).toInt().coerceIn(64, 2000)
        // نظام إحداثيات الرسم الداخلي — الرسم متجهي مباشرة على صفحة الـ PDF:
        // نص حاد بأي تكبير، وملف بالكيلوبايتات بدل عشرات الميغابايتات، وسرعة أضعاف
        val (cellW, cellH) = CardRenderer.renderSize(template, renderW)

        // بيانات لحظة الطباعة: رقم الطباعة والتاريخ والوقت تُثبَّت لكل الورقة
        val printNo = com.binwaps.cardmanager.data.Store.nextPrintNo()
        val now = java.util.Date()
        val dateText = java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(now)
        val timeText = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US).format(now)

        val doc = PdfDocument()
        val markPaint = Paint().apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.5f
            color = 0xFF9E9E9E.toInt()
        }
        val dashPaint = Paint(markPaint).apply {
            pathEffect = android.graphics.DashPathEffect(floatArrayOf(4f, 4f), 0f)
        }

        var done = 0
        var pdfPageNo = 0
        var cardsBefore = 0   // عدد الكروت المرسومة في الصفحات السابقة — لتسلسل الكرت
        val copies = settings.copies.coerceIn(1, 20)
        val pages = users.chunked(info.perPage)

        pages.forEachIndexed { pageIndex, pageUsers ->
            // النسخ المتكررة من نفس الورقة تحمل نفس رقم الصفحة ونفس تسلسل الكروت
            repeat(copies) {
                pdfPageNo++
                val page = doc.startPage(PdfDocument.PageInfo.Builder(pageW, pageH, pdfPageNo).create())
                val canvas = page.canvas

                var localCard = 0
                pageUsers.forEachIndexed { i, user ->
                    val col = i % info.columns
                    val row = i / info.columns
                    val left = offsetX + col * (cardW + hGap)
                    val top = offsetY + row * (cardH + vGap)
                    val rect = RectF(left, top, left + cardW, top + cardH)

                    // خلية متروكة عمداً (البدء من خلية لاحقة)
                    if (user == null) {
                        drawCutMarks(canvas, rect, layout.cutMarks, markPaint, dashPaint)
                        return@forEachIndexed
                    }

                    localCard++
                    val ri = RenderInfo(
                        pageNumber = pageIndex + 1,
                        cardNumber = cardsBefore + localCard,
                        printNo = printNo,
                        dateText = dateText,
                        timeText = timeText,
                    )
                    canvas.save()
                    canvas.translate(rect.left, rect.top)
                    canvas.scale(rect.width() / cellW.toFloat(), rect.height() / cellH.toFloat())
                    runCatching {
                        CardRenderer.drawCard(canvas, template, user, settings, cellW, cellH, ri)
                    }
                    canvas.restore()

                    drawCutMarks(canvas, rect, layout.cutMarks, markPaint, dashPaint)
                    done++
                    onProgress(done, selected.size * copies)
                }
                doc.finishPage(page)
            }
            cardsBefore += pageUsers.count { it != null }
        }

        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "cards_${System.currentTimeMillis()}.pdf")
        FileOutputStream(file).use { doc.writeTo(it) }
        doc.close()
        return file
    }

    private fun drawCutMarks(
        canvas: android.graphics.Canvas,
        rect: RectF,
        style: CutMarkStyle,
        paint: Paint,
        dashPaint: Paint,
    ) {
        when (style) {
            CutMarkStyle.NONE -> {}
            CutMarkStyle.BORDER -> canvas.drawRect(rect, paint)
            CutMarkStyle.DASHED -> canvas.drawRect(rect, dashPaint)
            CutMarkStyle.CORNERS -> {
                val len = minOf(rect.width(), rect.height()) * 0.12f
                // زوايا على شكل علامات قص خارجية
                canvas.drawLine(rect.left, rect.top, rect.left + len, rect.top, paint)
                canvas.drawLine(rect.left, rect.top, rect.left, rect.top + len, paint)
                canvas.drawLine(rect.right - len, rect.top, rect.right, rect.top, paint)
                canvas.drawLine(rect.right, rect.top, rect.right, rect.top + len, paint)
                canvas.drawLine(rect.left, rect.bottom - len, rect.left, rect.bottom, paint)
                canvas.drawLine(rect.left, rect.bottom, rect.left + len, rect.bottom, paint)
                canvas.drawLine(rect.right - len, rect.bottom, rect.right, rect.bottom, paint)
                canvas.drawLine(rect.right, rect.bottom - len, rect.right, rect.bottom, paint)
            }
        }
    }

    /** معاينة صفحة واحدة كصورة — تُستخدم في شاشة التخطيط */
    fun renderPagePreview(
        template: CardTemplate,
        users: List<UserEntry>,
        settings: AppSettings,
        widthPx: Int,
    ): Bitmap {
        val layout = settings.layout
        val info = computeLayout(template, settings, maxOf(users.size, 1))
        val heightPx = (widthPx * layout.pageHeightMm / layout.pageWidthMm).toInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        canvas.drawColor(android.graphics.Color.WHITE)

        val pxPerMm = widthPx / layout.pageWidthMm
        val cardW = info.cardWidthMm * pxPerMm
        val cardH = info.cardHeightMm * pxPerMm
        val hGap = layout.hSpacingMm * pxPerMm
        val vGap = layout.vSpacingMm * pxPerMm
        val gridW = info.columns * cardW + (info.columns - 1) * hGap
        val gridH = info.rows * cardH + (info.rows - 1) * vGap
        val offsetX = ((widthPx - gridW) / 2f).coerceAtLeast(layout.marginMm * pxPerMm)
        val offsetY = ((heightPx - gridH) / 2f).coerceAtLeast(layout.marginMm * pxPerMm)

        val cardRenderW = cardW.toInt().coerceIn(40, 600)
        val sample = users.firstOrNull() ?: UserEntry("user1234", "8642", price = "500", validity = "30d")
        val previewNow = java.util.Date()
        val cardBmp = CardRenderer.renderSafe(
            template, sample, settings, cardRenderW,
            RenderInfo(
                pageNumber = 1,
                cardNumber = 1,
                printNo = settings.printCounter + 1,
                dateText = java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(previewNow),
                timeText = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US).format(previewNow),
            ),
        )
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        val markPaint = Paint().apply {
            style = Paint.Style.STROKE; strokeWidth = 1f; color = 0xFFBDBDBD.toInt()
        }

        for (row in 0 until info.rows) {
            for (col in 0 until info.columns) {
                val left = offsetX + col * (cardW + hGap)
                val top = offsetY + row * (cardH + vGap)
                val rect = RectF(left, top, left + cardW, top + cardH)
                canvas.drawBitmap(cardBmp, null, rect, paint)
                if (layout.cutMarks != CutMarkStyle.NONE) canvas.drawRect(rect, markPaint)
            }
        }
        cardBmp.recycle()
        return bmp
    }

    /**
     * يحفظ الملف في مجلد «التنزيلات» على الجوال تلقائياً — بلا أي ضغطة ولا
     * إذن إضافي (MediaStore على أندرويد 10+، والمجلد العام على ما قبله).
     * يعيد اسم الملف المحفوظ أو null إن تعذّر.
     */
    fun saveToDownloads(context: Context, file: File): String? = runCatching {
        if (!file.exists()) return null
        val stamp = java.text.SimpleDateFormat("yyMMdd-HHmm", java.util.Locale.US)
            .format(java.util.Date())
        val name = "كروت-$stamp-${file.name}"
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                put(android.provider.MediaStore.Downloads.MIME_TYPE, "application/pdf")
                put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(
                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values,
            ) ?: return null
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            val dir = android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS,
            )
            if (!dir.exists()) dir.mkdirs()
            file.copyTo(File(dir, name), overwrite = true)
        }
        name
    }.getOrNull()

    /**
     * يرسم كرتاً واحداً كصورة PNG ويشاركه (واتساب/أي تطبيق) — لبيع كرت مفرد
     * للزبون مباشرة بلا طباعة. يستعمل نفس محرّك الرسم فيخرج مطابقاً للطباعة.
     */
    fun shareCardImage(context: Context, template: CardTemplate, user: UserEntry, settings: AppSettings) {
        runCatching {
            val now = java.util.Date()
            val bmp = CardRenderer.renderSafe(
                template, user, settings, 1000,
                RenderInfo(
                    pageNumber = 1, cardNumber = 1, printNo = settings.printCounter,
                    dateText = java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(now),
                    timeText = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US).format(now),
                ),
            )
            val dir = File(context.cacheDir, "exports").apply { mkdirs() }
            val file = File(dir, "card_${user.username}_${System.currentTimeMillis()}.png")
            FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            context.startActivity(
                Intent.createChooser(
                    Intent(Intent.ACTION_SEND).apply {
                        type = "image/png"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    },
                    "مشاركة الكرت",
                ),
            )
        }
    }

    /** مشاركة عدة ملفات دفعة واحدة — تظهر عند تقسيم الدفعات الضخمة */
    fun shareAll(context: Context, files: List<File>) {
        if (files.isEmpty()) return
        if (files.size == 1) return share(context, files.first())
        val uris = ArrayList(files.map {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", it)
        })
        context.startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "application/pdf"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                "مشاركة ملفات الكروت",
            )
        )
    }

    fun share(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "مشاركة ملف الكروت"))
    }

    /** إرسال الـ PDF إلى نظام الطباعة (طابعات WiFi / خدمات الطباعة) */
    fun printViaSystem(context: Context, file: File) {
        val printManager = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
        val adapter = object : PrintDocumentAdapter() {
            override fun onLayout(
                oldAttributes: PrintAttributes?, newAttributes: PrintAttributes,
                cancellationSignal: android.os.CancellationSignal?,
                callback: LayoutResultCallback, extras: android.os.Bundle?,
            ) {
                if (cancellationSignal?.isCanceled == true) { callback.onLayoutCancelled(); return }
                val info = PrintDocumentInfo.Builder(file.name)
                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                    .build()
                callback.onLayoutFinished(info, true)
            }

            override fun onWrite(
                pages: Array<out PageRange>?, destination: ParcelFileDescriptor,
                cancellationSignal: android.os.CancellationSignal?,
                callback: WriteResultCallback,
            ) {
                runCatching {
                    FileInputStream(file).use { input ->
                        FileOutputStream(destination.fileDescriptor).use { output -> input.copyTo(output) }
                    }
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                }.onFailure { callback.onWriteFailed(it.message) }
            }
        }
        printManager.print("كروت المستخدمين", adapter, PrintAttributes.Builder().build())
    }
}
