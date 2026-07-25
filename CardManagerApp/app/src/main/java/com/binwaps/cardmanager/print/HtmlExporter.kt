package com.binwaps.cardmanager.print

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardLayoutMode
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.CellAlign
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.RenderInfo
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * تصدير الكروت كصفحة HTML — تُفتح في أي متصفح على الجوال أو الكمبيوتر وتُطبع منه.
 * مفيدة لمن يريد الطباعة من كمبيوتر أو إرسال الكروت لشخص آخر ليطبعها.
 * المقاسات بالمليمتر فتخرج الطباعة بنفس أبعاد PDF.
 */
object HtmlExporter {

    fun export(
        context: Context,
        template: CardTemplate,
        allUsers: List<UserEntry>,
        settings: AppSettings,
    ): File {
        val users = PdfExporter.selectRange(allUsers, settings)
        val info = PdfExporter.computeLayout(template, settings, users.size)
        val layout = settings.layout
        val now = Date()
        val dateText = SimpleDateFormat("yyyy/MM/dd", Locale.US).format(now)
        val timeText = SimpleDateFormat("HH:mm", Locale.US).format(now)
        val printNo = settings.printCounter + 1

        val sb = StringBuilder()
        sb.append("<!DOCTYPE html>\n<html dir=\"rtl\" lang=\"ar\">\n<head>\n")
        sb.append("<meta charset=\"utf-8\">\n")
        sb.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n")
        sb.append("<title>كروت للطباعة — ${users.size} كرت</title>\n")
        sb.append("<style>\n")
        sb.append(css(template, layout.marginMm, layout.hSpacingMm, layout.vSpacingMm, info.columns))
        sb.append("</style>\n</head>\n<body>\n")
        sb.append("<div class=\"bar\">${users.size} كرت — ${info.columns} في الصف — اضغط طباعة من المتصفح</div>\n")
        sb.append("<div class=\"sheet\">\n")

        users.forEachIndexed { i, u ->
            val ri = RenderInfo(
                pageNumber = i / info.perPage + 1,
                cardNumber = i + 1,
                printNo = printNo,
                dateText = dateText,
                timeText = timeText,
            )
            sb.append(card(template, u, settings, ri))
        }

        sb.append("</div>\n</body>\n</html>\n")

        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "cards_${System.currentTimeMillis()}.html")
        file.writeText(sb.toString())
        return file
    }

    private fun css(
        t: CardTemplate,
        marginMm: Float,
        hGapMm: Float,
        vGapMm: Float,
        columns: Int,
    ): String = """
        * { box-sizing: border-box; }
        body { margin: 0; padding: ${marginMm}mm; background: #f4f6fa;
               font-family: "Cairo", "Droid Arabic Kufi", "Segoe UI", Tahoma, sans-serif; }
        .bar { background: #111827; color: #eaf2ff; padding: 10px 14px; border-radius: 10px;
               margin-bottom: 8mm; font-size: 13px; }
        .sheet { display: grid; grid-template-columns: repeat($columns, ${t.widthMm}mm);
                 column-gap: ${hGapMm}mm; row-gap: ${vGapMm}mm; justify-content: center; }
        .card { width: ${t.widthMm}mm; height: ${t.heightMm}mm; position: relative;
                background: ${hex(t.backgroundColor)}; overflow: hidden;
                border: ${t.borderWidthMm}mm solid ${hex(t.borderColor)};
                border-radius: ${t.cornerRadiusMm}mm; }
        .grid { width: 100%; height: 100%; border-collapse: collapse; table-layout: fixed; }
        .grid td { text-align: center; vertical-align: middle; padding: 0 1px;
                   white-space: nowrap; overflow: hidden; }
        .b { border: ${t.gridWidthMm}mm solid ${hex(t.gridColor)}; }
        .free { position: absolute; transform: translate(50%, -50%); white-space: nowrap; }
        @media print {
          body { background: #fff; padding: ${marginMm}mm; }
          .bar { display: none; }
          .card { break-inside: avoid; }
        }
    """.trimIndent() + "\n"

    private fun card(
        t: CardTemplate,
        u: UserEntry,
        s: AppSettings,
        info: RenderInfo,
    ): String = buildString {
        append("<div class=\"card\">")
        if (t.layoutMode == CardLayoutMode.TABLE) {
            append("<table class=\"grid\">")
            t.rows.forEach { row ->
                if (row.cells.isEmpty()) return@forEach
                val dataCells = row.cells.filter { it.type != FieldType.CUSTOM_TEXT }
                val keep = dataCells.isEmpty() ||
                    dataCells.any { CardRenderer.fieldAppliesTo(it.type, s.cardMode) }
                if (!keep) return@forEach
                append("<tr style=\"height:${row.heightMm}mm\">")
                val sum = row.cells.sumOf { it.weight.toDouble().coerceAtLeast(0.01) }
                row.cells.forEach { c ->
                    val pct = 100.0 * c.weight.coerceAtLeast(0.01f) / sum
                    val align = when (c.align) {
                        CellAlign.START -> "right"
                        CellAlign.END -> "left"
                        CellAlign.CENTER -> "center"
                    }
                    append("<td class=\"${if (c.border) "b" else ""}\" ")
                    append("style=\"width:${"%.2f".format(Locale.US, pct)}%;")
                    append("font-size:${c.fontSizePt}pt;color:${hex(c.color)};text-align:$align;")
                    if (c.bold) append("font-weight:700;")
                    append("\">")
                    val text = if (CardRenderer.fieldAppliesTo(c.type, s.cardMode))
                        CardRenderer.cellValue(c, u, s, info) else ""
                    append(esc(text))
                    append("</td>")
                }
                append("</tr>")
            }
            append("</table>")
        } else {
            t.fields.filter { it.visible && CardRenderer.fieldAppliesTo(it.type, s.cardMode) }
                .forEach { f ->
                    if (f.type == FieldType.QR_CODE) return@forEach   // الـ QR يحتاج صورة — استخدم PDF له
                    val text = CardRenderer.fieldValue(f, u, s, info)
                    if (text.isBlank()) return@forEach
                    append("<div class=\"free\" style=\"")
                    append("right:${(1f - f.xFrac) * 100}%;top:${f.yFrac * 100}%;")
                    append("font-size:${f.sizeFrac * t.heightMm}mm;color:${hex(f.color)};")
                    if (f.bold) append("font-weight:700;")
                    append("\">").append(esc(text)).append("</div>")
                }
        }
        append("</div>\n")
    }

    private fun hex(argb: Long): String {
        val a = ((argb shr 24) and 0xFF).toInt()
        val r = ((argb shr 16) and 0xFF).toInt()
        val g = ((argb shr 8) and 0xFF).toInt()
        val b = (argb and 0xFF).toInt()
        return if (a >= 255) String.format(Locale.US, "#%02X%02X%02X", r, g, b)
        else String.format(Locale.US, "rgba(%d,%d,%d,%.2f)", r, g, b, a / 255.0)
    }

    private fun esc(s: String): String = s
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    fun share(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        context.startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/html"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                "مشاركة صفحة الكروت",
            )
        )
    }

    /** يفتح الصفحة في المتصفح مباشرة للطباعة منه */
    fun open(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "text/html")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        )
    }
}
