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
    private const val RENDER_DPI = 240

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

    fun export(
        context: Context,
        template: CardTemplate,
        users: List<UserEntry>,
        settings: AppSettings,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): File {
        val layout = settings.layout
        val info = computeLayout(template, settings, users.size)

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
        val offsetX = ((pageW - gridW) / 2f).coerceAtLeast(margin)
        val offsetY = ((pageH - gridH) / 2f).coerceAtLeast(margin)

        val renderW = (info.cardWidthMm / 25.4f * RENDER_DPI).toInt().coerceIn(64, 2000)

        val doc = PdfDocument()
        val imagePaint = Paint(Paint.FILTER_BITMAP_FLAG)
        val markPaint = Paint().apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.5f
            color = 0xFF9E9E9E.toInt()
        }
        val dashPaint = Paint(markPaint).apply {
            pathEffect = android.graphics.DashPathEffect(floatArrayOf(4f, 4f), 0f)
        }

        var done = 0
        users.chunked(info.perPage).forEachIndexed { pageIndex, pageUsers ->
            val page = doc.startPage(PdfDocument.PageInfo.Builder(pageW, pageH, pageIndex + 1).create())
            val canvas = page.canvas

            pageUsers.forEachIndexed { i, user ->
                val col = i % info.columns
                val row = i / info.columns
                val left = offsetX + col * (cardW + hGap)
                val top = offsetY + row * (cardH + vGap)
                val rect = RectF(left, top, left + cardW, top + cardH)

                val bmp = CardRenderer.render(template, user, settings, renderW)
                canvas.drawBitmap(bmp, null, rect, imagePaint)
                bmp.recycle()

                drawCutMarks(canvas, rect, layout.cutMarks, markPaint, dashPaint)
                done++
                onProgress(done, users.size)
            }
            doc.finishPage(page)
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
        val cardBmp = CardRenderer.render(template, sample, settings, cardRenderW)
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
