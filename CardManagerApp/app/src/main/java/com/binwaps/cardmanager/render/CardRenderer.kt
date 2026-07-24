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

    fun render(
        template: CardTemplate,
        user: UserEntry,
        settings: AppSettings,
        widthPx: Int,
    ): Bitmap {
        val heightPx = (widthPx * template.heightMm / template.widthMm).toInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val pxPerMm = widthPx / template.widthMm
        val radius = template.cornerRadiusMm * pxPerMm
        val rect = RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat())

        // الخلفية
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = template.backgroundColor.toInt() }
        canvas.drawRoundRect(rect, radius, radius, bgPaint)

        if (template.backgroundPath.isNotBlank() && File(template.backgroundPath).exists()) {
            val bg = BitmapFactory.decodeFile(template.backgroundPath)
            if (bg != null) {
                canvas.drawBitmap(bg, null, rect, Paint(Paint.FILTER_BITMAP_FLAG))
                bg.recycle()
            }
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

        // الحقول
        for (field in template.fields) {
            if (!field.visible) continue
            if (field.type == FieldType.QR_CODE) {
                drawQr(canvas, field, template, user, settings, widthPx, heightPx)
            } else {
                drawText(canvas, field, user, settings, widthPx, heightPx)
            }
        }
        return bmp
    }

    fun fieldValue(field: CardField, user: UserEntry, settings: AppSettings): String {
        val value = when (field.type) {
            FieldType.USERNAME -> user.username
            FieldType.PASSWORD -> user.password
            FieldType.PRICE -> if (user.price.isBlank()) "" else "${user.price} ${settings.currency}"
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
        widthPx: Int, heightPx: Int,
    ) {
        val text = fieldValue(field, user, settings)
        if (text.isBlank()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = field.color.toInt()
            textSize = field.sizeFrac * heightPx
            textAlign = Paint.Align.CENTER
            typeface = if (field.bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
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

    fun qrText(kind: QrContent, user: UserEntry, settings: AppSettings): String = when (kind) {
        QrContent.LOGIN_URL -> {
            val base = settings.hotspotLoginUrl.trimEnd('/')
            "$base?username=${user.username}&password=${user.password}"
        }
        QrContent.WIFI -> "WIFI:S:${settings.wifiSsid};T:WPA;P:${settings.wifiPassword};;"
        QrContent.USER_PASS -> "${user.username}:${user.password}"
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
