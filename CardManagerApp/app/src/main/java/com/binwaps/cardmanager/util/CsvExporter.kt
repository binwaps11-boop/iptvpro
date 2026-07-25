package com.binwaps.cardmanager.util

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.binwaps.cardmanager.model.SaleEntry
import com.binwaps.cardmanager.model.UserEntry
import java.io.File

/** تصدير الكروت والمبيعات إلى ملفات CSV تفتح في إكسل */
object CsvExporter {

    /** الترميز UTF-8 مع BOM ليعرض إكسل العربية صحيحة */
    private const val BOM = "﻿"

    private fun escape(v: String): String =
        if (v.contains(',') || v.contains('"') || v.contains('\n')) "\"" + v.replace("\"", "\"\"") + "\""
        else v

    private fun write(context: Context, name: String, content: String): File {
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, name)
        file.writeText(BOM + content)
        return file
    }

    fun exportCards(context: Context, cards: List<UserEntry>): File {
        val sb = StringBuilder()
        sb.appendLine("username,password,profile,price,validity,status,uptime,used_bytes,batch,comment")
        cards.forEach { u ->
            sb.appendLine(
                listOf(
                    u.username, u.password, u.profile, u.price, u.validity,
                    u.status.labelAr, u.uptime, u.bytesUsed.toString(), u.batchTag, u.comment,
                ).joinToString(",") { escape(it) }
            )
        }
        return write(context, "cards_${System.currentTimeMillis()}.csv", sb.toString())
    }

    fun exportSales(context: Context, sales: List<SaleEntry>, currency: String): File {
        val fmt = java.text.SimpleDateFormat("yyyy/MM/dd HH:mm", java.util.Locale.US)
        val sb = StringBuilder()
        sb.appendLine("date,type,customer,profile,quantity,unit_price,total,paid,debt,note,currency")
        sales.forEach { s ->
            sb.appendLine(
                listOf(
                    fmt.format(java.util.Date(s.at)), s.kind.labelAr, s.customer, s.profile,
                    s.quantity.toString(), s.unitPrice.toString(), s.total.toString(),
                    s.paid.toString(), s.debt.toString(), s.note, currency,
                ).joinToString(",") { escape(it) }
            )
        }
        return write(context, "sales_${System.currentTimeMillis()}.csv", sb.toString())
    }

    fun share(context: Context, file: File, title: String) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        context.startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/csv"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                title,
            )
        )
    }
}
