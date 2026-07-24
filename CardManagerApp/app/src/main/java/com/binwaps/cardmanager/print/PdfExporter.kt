package com.binwaps.cardmanager.print

import android.content.Context
import android.content.Intent
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
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * تصدير الكروت كشبكة على ورق A4 بصيغة PDF مع علامات قص،
 * ثم مشاركة الملف أو إرساله لأي طابعة عبر نظام الطباعة في أندرويد.
 */
object PdfExporter {

    // أبعاد A4 بالنقاط (72 نقطة/إنش)
    private const val PAGE_W = 595
    private const val PAGE_H = 842
    private const val MM_TO_PT = 72f / 25.4f

    // دقة رسم الكرت داخل الـ PDF
    private const val RENDER_DPI = 300

    fun export(
        context: Context,
        template: CardTemplate,
        users: List<UserEntry>,
        settings: AppSettings,
    ): File {
        val doc = PdfDocument()
        val margin = settings.a4MarginMm * MM_TO_PT
        val spacing = settings.a4SpacingMm * MM_TO_PT
        val cardW = template.widthMm * MM_TO_PT
        val cardH = template.heightMm * MM_TO_PT

        val cols = (((PAGE_W - 2 * margin) + spacing) / (cardW + spacing)).toInt().coerceAtLeast(1)
        val rows = (((PAGE_H - 2 * margin) + spacing) / (cardH + spacing)).toInt().coerceAtLeast(1)
        val perPage = cols * rows

        val renderW = (template.widthMm / 25.4f * RENDER_DPI).toInt().coerceAtLeast(64)

        val cutPaint = Paint().apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.5f
            color = 0xFF9E9E9E.toInt()
        }

        users.chunked(perPage).forEachIndexed { pageIndex, pageUsers ->
            val page = doc.startPage(PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, pageIndex + 1).create())
            val canvas = page.canvas
            pageUsers.forEachIndexed { i, user ->
                val col = i % cols
                val row = i / cols
                val left = margin + col * (cardW + spacing)
                val top = margin + row * (cardH + spacing)
                val bmp = CardRenderer.render(template, user, settings, renderW)
                canvas.drawBitmap(bmp, null, RectF(left, top, left + cardW, top + cardH), Paint(Paint.FILTER_BITMAP_FLAG))
                bmp.recycle()
                if (settings.cutMarks) {
                    canvas.drawRect(left, top, left + cardW, top + cardH, cutPaint)
                }
            }
            doc.finishPage(page)
        }

        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "cards_${System.currentTimeMillis()}.pdf")
        FileOutputStream(file).use { doc.writeTo(it) }
        doc.close()
        return file
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
                        FileOutputStream(destination.fileDescriptor).use { output ->
                            input.copyTo(output)
                        }
                    }
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                }.onFailure { callback.onWriteFailed(it.message) }
            }
        }
        printManager.print("كروت المستخدمين", adapter, PrintAttributes.Builder().build())
    }
}
