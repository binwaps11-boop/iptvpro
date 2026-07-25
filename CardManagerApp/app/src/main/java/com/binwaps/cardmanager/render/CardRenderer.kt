package com.binwaps.cardmanager.render

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.CardFont
import com.binwaps.cardmanager.model.CardMode
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.QrContent
import com.binwaps.cardmanager.model.UserEntry
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
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
    fun renderSafe(template: CardTemplate, user: UserEntry, settings: AppSettings, widthPx: Int): Bitmap =
        runCatching { render(template, user, settings, widthPx) }.getOrElse {
            val w = widthPx.coerceIn(16, 1200)
            val h = (w * (template.heightMm.coerceAtLeast(1f)) / template.widthMm.coerceAtLeast(1f))
                .toInt().coerceIn(16, 2000)
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { it.eraseColor(0xFFFFFFFF.toInt()) }
        }

    fun render(
        template: CardTemplate,
        user: UserEntry,
        settings: AppSettings,
        widthPx: Int,
    ): Bitmap {
        // حماية من قيم القالب غير الصالحة التي قد تُنتج أبعاداً ضخمة أو صفرية
        val safeWidth = widthPx.coerceIn(16, 1600)
        val wMm = template.widthMm.coerceAtLeast(1f)
        val hMm = template.heightMm.coerceAtLeast(1f)
        @Suppress("NAME_SHADOWING") val widthPx = safeWidth
        val heightPx = (widthPx * hMm / wMm).toInt().coerceIn(16, 2400)
        val bmp = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
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

        // الحقول — مع احترام نوع الكرت المختار
        for (field in template.fields) {
            if (!field.visible) continue
            if (!fieldAppliesTo(field.type, settings.cardMode)) continue
            if (field.type == FieldType.QR_CODE) {
                drawQr(canvas, field, template, user, settings, widthPx, heightPx)
            } else {
                drawText(canvas, field, user, settings, widthPx, heightPx, template.font)
            }
        }
        return bmp
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

    fun fieldValue(field: CardField, user: UserEntry, settings: AppSettings): String {
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
        }
        return field.prefix + value
    }

    private fun drawText(
        canvas: Canvas, field: CardField, user: UserEntry, settings: AppSettings,
        widthPx: Int, heightPx: Int, templateFont: CardFont,
    ) {
        val text = fieldValue(field, user, settings)
        if (text.isBlank()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = field.color.toInt()
            textSize = field.sizeFrac * heightPx
            textAlign = Paint.Align.CENTER
            typeface = typeface(field.font ?: templateFont, field.bold)
        }
        // تصغير تلقائي إذا تجاوز النص عرض الكرت
        val maxWidth = widthPx * 0.94f
        while (paint.measureText(text) > maxWidth && paint.textSize > 4f) {
            paint.textSize *= 0.94f
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
        val qr = encodeQr(content, side) ?: return
        val left = field.xFrac * widthPx - side / 2f
        val top = field.yFrac * heightPx - side / 2f
        canvas.drawBitmap(qr, left, top, null)
        qr.recycle()
    }

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
        val bmp = Bitmap.createBitmap(sidePx, sidePx, Bitmap.Config.ARGB_8888)
        for (x in 0 until sidePx) {
            for (y in 0 until sidePx) {
                bmp.setPixel(x, y, if (matrix.get(x, y)) Color.BLACK else Color.WHITE)
            }
        }
        bmp
    }.getOrNull()
}
