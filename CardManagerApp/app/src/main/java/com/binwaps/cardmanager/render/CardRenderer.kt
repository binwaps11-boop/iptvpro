package com.binwaps.cardmanager.render

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardCell
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.CardFont
import com.binwaps.cardmanager.model.CardLayoutMode
import com.binwaps.cardmanager.model.CardMode
import com.binwaps.cardmanager.model.CardRow
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.CellAlign
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.QrContent
import com.binwaps.cardmanager.model.RenderInfo
import com.binwaps.cardmanager.model.UserEntry
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.oned.Code128Writer
import com.google.zxing.qrcode.QRCodeWriter
import java.io.File

/**
 * يرسم كرتاً واحداً (قالب + بيانات مستخدم) على Bitmap.
 * نفس المحرك يُستخدم للمعاينة وتصدير PDF والطباعة الحرارية.
 */
object CardRenderer {

    /** ذاكرة الخطوط المضمّنة — تُحمَّل مرة واحدة */
    private val typefaces = mutableMapOf<String, Typeface>()
    private var assets: android.content.res.AssetManager? = null

    /** يُستدعى مرة عند بدء التطبيق حتى تتوفر الخطوط للرسم */
    fun init(context: android.content.Context) {
        assets = context.applicationContext.assets
    }

    @Synchronized
    private fun typeface(font: CardFont, bold: Boolean): Typeface {
        val path = (if (bold) font.boldAsset ?: font.asset else font.asset)
            ?: return if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        typefaces[path]?.let { return it }
        val am = assets ?: return if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        val tf = runCatching { Typeface.createFromAsset(am, path) }.getOrNull()
            ?: return if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        // الخط العادي مع طلب عريض: نُثقّله برمجياً
        val result = if (bold && font.boldAsset == null) Typeface.create(tf, Typeface.BOLD) else tf
        typefaces[path] = result
        return result
    }

    /** ذاكرة مؤقتة لصورة الخلفية — تمنع فك ترميز الصورة لكل كرت (تسريع كبير للدفعات) */
    private var bgPath: String? = null
    private var bgBitmap: Bitmap? = null

    @Synchronized
    private fun background(path: String): Bitmap? {
        if (path.isBlank()) return null
        if (bgPath == path && bgBitmap?.isRecycled == false) return bgBitmap
        bgBitmap?.recycle()
        bgBitmap = if (File(path).exists()) BitmapFactory.decodeFile(path) else null
        bgPath = path
        return bgBitmap
    }

    /** تُستدعى عند تغيير خلفية القالب */
    @Synchronized
    fun clearCache() {
        bgBitmap?.recycle()
        bgBitmap = null
        bgPath = null
    }

    /** نسخة آمنة لا تُسقط التطبيق أبداً — تعيد صورة بسيطة عند أي خطأ */
    fun renderSafe(
        template: CardTemplate, user: UserEntry, settings: AppSettings, widthPx: Int,
        info: RenderInfo = RenderInfo(),
    ): Bitmap =
        runCatching { render(template, user, settings, widthPx, info) }.getOrElse {
            val w = widthPx.coerceIn(16, 1200)
            val h = (w * (template.heightMm.coerceAtLeast(1f)) / template.widthMm.coerceAtLeast(1f))
                .toInt().coerceIn(16, 2000)
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { it.eraseColor(0xFFFFFFFF.toInt()) }
        }

    /** أبعاد الرسم الداخلية لقالبٍ ما عند عرض معيّن — تستخدمها كل مسارات الرسم */
    fun renderSize(template: CardTemplate, widthPx: Int): Pair<Int, Int> {
        val w = widthPx.coerceIn(16, 1600)
        val wMm = template.widthMm.coerceAtLeast(1f)
        val hMm = template.heightMm.coerceAtLeast(1f)
        val h = (w * hMm / wMm).toInt().coerceIn(16, 2400)
        return w to h
    }

    fun render(
        template: CardTemplate,
        user: UserEntry,
        settings: AppSettings,
        widthPx: Int,
        info: RenderInfo = RenderInfo(),
    ): Bitmap {
        val (w, h) = renderSize(template, widthPx)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        drawCard(Canvas(bmp), template, user, settings, w, h, info)
        return bmp
    }

    /**
     * يرسم الكرت على أي Canvas — على صورة للمعاينة والحرارية، أو مباشرة على
     * صفحة PDF فيخرج النص متجهياً حاداً والملف صغيراً (أسرع بكثير للدفعات).
     */
    fun drawCard(
        canvas: Canvas,
        template: CardTemplate,
        user: UserEntry,
        settings: AppSettings,
        widthPx: Int,
        heightPx: Int,
        info: RenderInfo = RenderInfo(),
    ) {
        val wMm = template.widthMm.coerceAtLeast(1f)
        val pxPerMm = widthPx / wMm
        val radius = template.cornerRadiusMm * pxPerMm
        val rect = RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat())

        // الخلفية
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = template.backgroundColor.toInt() }
        canvas.drawRoundRect(rect, radius, radius, bgPaint)

        background(template.backgroundPath)?.let { bg ->
            canvas.drawBitmap(bg, null, rect, Paint(Paint.FILTER_BITMAP_FLAG))
        }

        // الإطار
        if (template.borderWidthMm > 0f) {
            val bw = template.borderWidthMm * pxPerMm
            val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = bw
                color = template.borderColor.toInt()
            }
            val inset = bw / 2f
            canvas.drawRoundRect(RectF(inset, inset, widthPx - inset, heightPx - inset), radius, radius, borderPaint)
        }

        if (template.layoutMode == CardLayoutMode.TABLE) {
            drawTable(canvas, template, user, settings, widthPx, heightPx, pxPerMm, info)
            return
        }

        // الحقول — مع احترام نوع الكرت المختار
        for (field in template.fields) {
            if (!field.visible) continue
            if (!fieldAppliesTo(field.type, settings.cardMode)) continue
            when (field.type) {
                FieldType.QR_CODE ->
                    drawQr(canvas, field, template, user, settings, widthPx, heightPx)
                FieldType.BARCODE ->
                    drawBarcode(canvas, field, user, settings, widthPx, heightPx)
                else ->
                    drawText(canvas, field, user, settings, widthPx, heightPx, template.font, info)
            }
        }
    }

    /**
     * هل يُطبع هذا الحقل مع نوع الكرت المختار؟
     * - اسم مستخدم فقط: لا تُطبع كلمة المرور
     * - متشابه: يُطبع رمز واحد فقط (نخفي كلمة المرور لأنها نفس الاسم)
     */
    fun fieldAppliesTo(type: FieldType, mode: CardMode): Boolean = when (type) {
        FieldType.PASSWORD -> mode == CardMode.USER_PASS
        else -> true
    }

    /** الحقول التي تُحسب لحظة الطباعة — رقم الصفحة والتسلسل والتاريخ والوقت */
    private fun computed(type: FieldType, user: UserEntry, info: RenderInfo): String = when (type) {
        FieldType.BATCH_NO -> user.batchTag
        FieldType.PRINT_NO -> if (info.printNo > 0) info.printNo.toString() else ""
        FieldType.PAGE_NO -> info.pageNumber.toString()
        FieldType.CARD_NO -> info.cardNumber.toString()
        FieldType.PRINT_DATE -> info.dateText
        FieldType.PRINT_TIME -> info.timeText
        else -> ""
    }

    // ==================== نمط الجدول ====================
    // يُحاكي طريقة طباعة سمارت كريتور: صفوف بإطارات، كل صف مقسوم إلى خلايا،
    // والنص في وسط الخلية. الفرق أن كل شيء هنا قابل للتعديل من التطبيق.

    /** هل يُطبع هذا الصف مع نوع الكرت المختار؟ صف كلمة المرور يُحذف كاملاً إن لم تكن مطلوبة */
    private fun rowApplies(row: CardRow, mode: CardMode): Boolean {
        val dataCells = row.cells.filter { it.type != FieldType.CUSTOM_TEXT }
        if (dataCells.isEmpty()) return true
        return dataCells.any { fieldAppliesTo(it.type, mode) }
    }

    fun cellValue(cell: CardCell, user: UserEntry, settings: AppSettings, info: RenderInfo = RenderInfo()): String {
        val value = when (cell.type) {
            FieldType.USERNAME -> user.username
            FieldType.PASSWORD -> user.password
            FieldType.PRICE ->
                if (user.isFree) settings.freeRules.freeLabel
                else if (user.price.isBlank()) "" else "${user.price} ${settings.currency}"
            FieldType.VALIDITY -> user.validity
            FieldType.PROFILE -> user.profile
            FieldType.SERIAL -> user.serial
            FieldType.CUSTOM_TEXT -> cell.customText
            FieldType.QR_CODE -> ""
            else -> computed(cell.type, user, info)
        }
        if (value.isBlank() && cell.type != FieldType.CUSTOM_TEXT) return ""
        return cell.prefix + value
    }

    private fun drawTable(
        canvas: Canvas, template: CardTemplate, user: UserEntry, settings: AppSettings,
        widthPx: Int, heightPx: Int, pxPerMm: Float, info: RenderInfo,
    ) {
        val rows = template.rows.filter { rowApplies(it, settings.cardMode) && it.cells.isNotEmpty() }
        if (rows.isEmpty()) return

        val pad = (template.tablePaddingMm * pxPerMm).coerceAtLeast(0f)
        val left = pad
        val right = widthPx - pad
        val availW = (right - left).coerceAtLeast(1f)
        val availH = (heightPx - 2 * pad).coerceAtLeast(1f)

        // ارتفاعات الصفوف بالمليمتر — تُصغَّر بالتناسب إن تجاوزت المساحة
        val wanted = rows.sumOf { it.heightMm.toDouble() }.toFloat() * pxPerMm
        val scale = if (wanted > availH && wanted > 0f) availH / wanted else 1f
        val totalH = wanted * scale
        var top = pad + (availH - totalH) / 2f   // الجدول في وسط الكرت رأسياً

        val grid = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = (template.gridWidthMm * pxPerMm).coerceAtLeast(0.6f)
            color = template.gridColor.toInt()
        }

        for (row in rows) {
            val rowH = row.heightMm * pxPerMm * scale
            val weightSum = row.cells.sumOf { it.weight.toDouble().coerceAtLeast(0.01) }.toFloat()
            // الخلية الأولى في اليمين — الكرت عربي فالترتيب من اليمين لليسار
            var x = right
            for (cell in row.cells) {
                val cellW = availW * (cell.weight.coerceAtLeast(0.01f) / weightSum)
                val cellRect = RectF(x - cellW, top, x, top + rowH)

                if (cell.fillColor.toInt() != 0 && (cell.fillColor ushr 24) != 0L) {
                    canvas.drawRect(cellRect, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = cell.fillColor.toInt()
                    })
                }
                if (cell.border) canvas.drawRect(cellRect, grid)

                if (cell.type == FieldType.QR_CODE) {
                    drawCellQr(canvas, cellRect, template, user, settings)
                } else if (fieldAppliesTo(cell.type, settings.cardMode)) {
                    drawCellText(canvas, cellRect, cell, user, settings, template.font, pxPerMm, info)
                }
                x -= cellW
            }
            top += rowH
        }
    }

    private fun drawCellText(
        canvas: Canvas, r: RectF, cell: CardCell, user: UserEntry, settings: AppSettings,
        templateFont: CardFont, pxPerMm: Float, info: RenderInfo,
    ) {
        val text = cellValue(cell, user, settings, info)
        if (text.isBlank()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = cell.color.toInt()
            // النقطة الطباعية = 0.352778 مم
            textSize = (cell.fontSizePt * PT_MM * pxPerMm).coerceAtLeast(3f)
            typeface = typeface(cell.font ?: templateFont, cell.bold)
        }
        val inset = r.width() * 0.04f
        val maxW = (r.width() - 2 * inset).coerceAtLeast(1f)
        val measured = paint.measureText(text)
        if (measured > maxW) paint.textSize = (paint.textSize * maxW / measured).coerceAtLeast(3f)

        val baseline = r.centerY() - (paint.ascent() + paint.descent()) / 2f
        val x = when (cell.align) {
            CellAlign.CENTER -> { paint.textAlign = Paint.Align.CENTER; r.centerX() }
            CellAlign.START -> { paint.textAlign = Paint.Align.RIGHT; r.right - inset }
            CellAlign.END -> { paint.textAlign = Paint.Align.LEFT; r.left + inset }
        }
        canvas.drawText(text, x, baseline, paint)
    }

    private fun drawCellQr(
        canvas: Canvas, r: RectF, template: CardTemplate, user: UserEntry, settings: AppSettings,
    ) {
        val content = qrText(template.qrContent, user, settings)
        if (content.isBlank()) return
        val side = (minOf(r.width(), r.height()) * 0.92f).toInt().coerceAtLeast(16)
        val qr = cachedQr(content, side) ?: return
        canvas.drawBitmap(qr, r.centerX() - side / 2f, r.centerY() - side / 2f, null)
    }

    private const val PT_MM = 0.352778f

    fun fieldValue(field: CardField, user: UserEntry, settings: AppSettings, info: RenderInfo = RenderInfo()): String {
        val value = when (field.type) {
            FieldType.USERNAME -> user.username
            FieldType.PASSWORD -> user.password
            FieldType.PRICE ->
                if (user.isFree) settings.freeRules.freeLabel
                else if (user.price.isBlank()) "" else "${user.price} ${settings.currency}"
            FieldType.VALIDITY -> user.validity
            FieldType.PROFILE -> user.profile
            FieldType.SERIAL -> user.serial
            FieldType.CUSTOM_TEXT -> field.customText
            FieldType.QR_CODE -> ""
            else -> computed(field.type, user, info)
        }
        return field.prefix + value
    }

    private fun drawText(
        canvas: Canvas, field: CardField, user: UserEntry, settings: AppSettings,
        widthPx: Int, heightPx: Int, templateFont: CardFont, info: RenderInfo,
    ) {
        val text = fieldValue(field, user, settings, info)
        if (text.isBlank()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = field.color.toInt()
            textSize = field.sizeFrac * heightPx
            textAlign = Paint.Align.CENTER
            typeface = typeface(field.font ?: templateFont, field.bold)
        }
        // تصغير تلقائي بخطوة واحدة إذا تجاوز النص عرض الكرت
        val maxWidth = widthPx * 0.94f
        val measured = paint.measureText(text)
        if (measured > maxWidth) {
            paint.textSize = (paint.textSize * maxWidth / measured).coerceAtLeast(4f)
        }
        val x = field.xFrac * widthPx
        val y = field.yFrac * heightPx - (paint.ascent() + paint.descent()) / 2f
        canvas.drawText(text, x, y, paint)
    }

    private fun drawQr(
        canvas: Canvas, field: CardField, template: CardTemplate, user: UserEntry,
        settings: AppSettings, widthPx: Int, heightPx: Int,
    ) {
        val content = qrText(template.qrContent, user, settings)
        if (content.isBlank()) return
        val side = (field.sizeFrac * heightPx).toInt().coerceAtLeast(16)
        val qr = cachedQr(content, side) ?: return
        val left = field.xFrac * widthPx - side / 2f
        val top = field.yFrac * heightPx - side / 2f
        canvas.drawBitmap(qr, left, top, null)
    }

    /** الباركود يرمّز اسم المستخدم — أكثر قيمة قابلة للمسح على الكرت */
    private fun barcodeContent(user: UserEntry, settings: AppSettings): String =
        user.username.trim()

    private fun drawBarcode(
        canvas: Canvas, field: CardField, user: UserEntry,
        settings: AppSettings, widthPx: Int, heightPx: Int,
    ) {
        val content = barcodeContent(user, settings)
        if (content.isBlank()) return
        // الباركود عريض قصير: العرض نسبة من عرض الكرت والارتفاع كسر منه
        val bw = (field.sizeFrac * widthPx).toInt().coerceIn(40, widthPx)
        val bh = (bw * 0.32f).toInt().coerceAtLeast(20)
        val bmp = encodeBarcode(content, bw, bh) ?: return
        val left = field.xFrac * widthPx - bw / 2f
        val top = field.yFrac * heightPx - bh / 2f
        canvas.drawBitmap(bmp, left, top, null)
    }

    /** Code128 — يقبل الأرقام والحروف اللاتينية. يعيد صورة أو null عند الفشل */
    fun encodeBarcode(content: String, wPx: Int, hPx: Int): Bitmap? = runCatching {
        val hints = mapOf(EncodeHintType.MARGIN to 2)
        val matrix = Code128Writer().encode(content, BarcodeFormat.CODE_128, wPx, hPx, hints)
        val pixels = IntArray(wPx * hPx)
        for (y in 0 until hPx) {
            val off = y * wPx
            for (x in 0 until wPx) {
                pixels[off + x] = if (matrix.get(x, y)) Color.BLACK else Color.WHITE
            }
        }
        Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888).also {
            it.setPixels(pixels, 0, wPx, 0, 0, wPx, hPx)
        }
    }.getOrNull()

    fun qrText(kind: QrContent, user: UserEntry, settings: AppSettings): String {
        // كلمة المرور الفعلية للدخول تختلف حسب نوع الكرت
        val loginPassword = when (settings.cardMode) {
            CardMode.USERNAME_ONLY -> ""
            CardMode.SAME -> user.username
            CardMode.USER_PASS -> user.password
        }
        return when (kind) {
            QrContent.LOGIN_URL -> {
                val base = settings.hotspotLoginUrl.trimEnd('/')
                if (loginPassword.isBlank()) "$base?username=${user.username}"
                else "$base?username=${user.username}&password=$loginPassword"
            }
            QrContent.WIFI -> "WIFI:S:${settings.wifiSsid};T:WPA;P:${settings.wifiPassword};;"
            QrContent.USER_PASS ->
                if (loginPassword.isBlank()) user.username else "${user.username}:$loginPassword"
        }
    }

    fun encodeQr(content: String, sidePx: Int): Bitmap? = runCatching {
        val hints = mapOf(EncodeHintType.MARGIN to 1)
        val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, sidePx, sidePx, hints)
        // ملء دفعة واحدة — setPixel نقطة نقطة كان أبطأ بعشرات المرات
        val pixels = IntArray(sidePx * sidePx)
        for (y in 0 until sidePx) {
            val off = y * sidePx
            for (x in 0 until sidePx) {
                pixels[off + x] = if (matrix.get(x, y)) Color.BLACK else Color.WHITE
            }
        }
        Bitmap.createBitmap(sidePx, sidePx, Bitmap.Config.ARGB_8888).also {
            it.setPixels(pixels, 0, sidePx, 0, 0, sidePx, sidePx)
        }
    }.getOrNull()

    // ذاكرة آخر رمز QR — عندما يكون المحتوى واحداً لكل الكروت (واي فاي مثلاً)
    // يُرمَّز مرة واحدة للدفعة كلها بدل 500 مرة
    private var qrKey: String? = null
    private var qrBitmap: Bitmap? = null

    @Synchronized
    private fun cachedQr(content: String, sidePx: Int): Bitmap? {
        val key = "$sidePx|$content"
        if (qrKey == key && qrBitmap?.isRecycled == false) return qrBitmap
        qrBitmap = encodeQr(content, sidePx)
        qrKey = key
        return qrBitmap
    }
}
