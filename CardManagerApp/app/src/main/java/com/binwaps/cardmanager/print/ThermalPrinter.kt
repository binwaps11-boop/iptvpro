package com.binwaps.cardmanager.print

import android.graphics.Bitmap
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.PaperType
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
import com.dantsu.escposprinter.EscPosPrinter
import com.dantsu.escposprinter.connection.DeviceConnection
import com.dantsu.escposprinter.connection.bluetooth.BluetoothConnection
import com.dantsu.escposprinter.connection.bluetooth.BluetoothPrintersConnections
import com.dantsu.escposprinter.connection.tcp.TcpConnection
import com.dantsu.escposprinter.textparser.PrinterTextParserImg
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * الطباعة على الطابعات الحرارية عبر البلوتوث (ESC/POS).
 * يدعم عرض 58مم (384 نقطة) و80مم (576 نقطة) مع تحكم بارتفاع الكرت والتغذية.
 */
object ThermalPrinter {

    /**
     * الطابعات المقترنة عبر البلوتوث. المكتبة تُرشّح الأجهزة المقترنة بفئة
     * «تصوير/طابعة» فقط، وأغلب الطابعات الحرارية الرخيصة (58/80مم) تعلن فئة
     * أخرى أو لا تعلن شيئاً — فكانت القائمة تخرج فارغة («لا توجد طابعات مقترنة»)
     * ولا سبيل لاختيار الطابعة أصلاً. الآن: الطابعات المصنَّفة أولاً، وإلا كل
     * الأجهزة المقترنة ليختار المستخدم طابعته.
     */
    fun pairedPrinters(): List<BluetoothConnection> = runCatching {
        val classified = BluetoothPrintersConnections().list?.toList().orEmpty()
        if (classified.isNotEmpty()) classified
        else com.dantsu.escposprinter.connection.bluetooth.BluetoothConnections().list?.toList().orEmpty()
    }.getOrElse { e ->
        com.binwaps.cardmanager.data.EventLog.log(
            "طباعة", "تعذّر قراءة أجهزة البلوتوث المقترنة: ${e.message?.take(120)}", ok = false,
        )
        emptyList()
    }

    internal fun printableWidthMm(paper: PaperType): Float = when (paper) {
        PaperType.THERMAL_80 -> 72f
        else -> 48f
    }

    internal fun charsPerLine(paper: PaperType): Int = when (paper) {
        PaperType.THERMAL_80 -> 48
        else -> 32
    }

    /** اتصال طابعة شبكة TCP (المنفذ عادة 9100) */
    fun tcpPrinter(ip: String, port: Int): DeviceConnection = TcpConnection(ip, port)

    suspend fun printCards(
        connection: DeviceConnection,
        template: CardTemplate,
        users: List<UserEntry>,
        settings: AppSettings,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> = withContext(Dispatchers.IO) {
        runCatching {
            val widthMm = printableWidthMm(settings.paperType)
            val printer = EscPosPrinter(connection, settings.thermalDpi, widthMm, charsPerLine(settings.paperType))
            try {
                if (settings.escAsteriskMode) printer.useEscAsteriskCommand(true)
                val printNo = com.binwaps.cardmanager.data.Store.nextPrintNo()
                val now = java.util.Date()
                val dateText = java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(now)
                val timeText = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US).format(now)
                fun thermalInfo(i: Int) = com.binwaps.cardmanager.model.RenderInfo(
                    pageNumber = i + 1, cardNumber = i + 1, printNo = printNo,
                    dateText = dateText, timeText = timeText,
                )

                val dotsPerMm = settings.thermalDpi / 25.4f
                val widthPx = (widthMm * dotsPerMm).toInt()
                val heightPx = (settings.thermalCardHeightMm * dotsPerMm).toInt().coerceAtLeast(32)

                users.forEachIndexed { index, user ->
                    val rendered = CardRenderer.renderSafe(template, user, settings, widthPx, thermalInfo(index))
                    // مط الكرت إلى الارتفاع المطلوب من الإعدادات
                    val scaled = if (rendered.width != widthPx || rendered.height != heightPx) {
                        Bitmap.createScaledBitmap(rendered, widthPx, heightPx, true).also { rendered.recycle() }
                    } else rendered

                    val text = buildImageText(printer, scaled)
                    scaled.recycle()
                    val isLast = index == users.size - 1
                    if (settings.autoCut && isLast) {
                        printer.printFormattedTextAndCut(text, settings.thermalFeedMm)
                    } else {
                        printer.printFormattedText(text, settings.thermalFeedMm)
                    }
                    onProgress(index + 1, users.size)
                }
                users.size
            } finally {
                runCatching { printer.disconnectPrinter() }
            }
        }
    }

    /**
     * تحويل صورة الكرت إلى أوامر طباعة. الطابعات الحرارية تحدّ ارتفاع الصورة
     * الواحدة بـ 256 نقطة، لذلك نقسم الكرت إلى شرائح.
     */
    internal fun buildImageText(printer: EscPosPrinter, bitmap: Bitmap): String {
        val sb = StringBuilder()
        var y = 0
        while (y < bitmap.height) {
            val sliceH = minOf(250, bitmap.height - y)
            val slice = Bitmap.createBitmap(bitmap, 0, y, bitmap.width, sliceH)
            sb.append("[C]<img>")
                .append(PrinterTextParserImg.bitmapToHexadecimalString(printer, slice, false))
                .append("</img>\n")
            slice.recycle()
            y += sliceH
        }
        return sb.toString()
    }
}
