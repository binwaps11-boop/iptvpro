package com.binwaps.cardmanager.util

import android.content.Context
import android.net.Uri
import com.binwaps.cardmanager.model.UserEntry

/**
 * استيراد المستخدمين من ملف CSV مُصدَّر من اليوزر منجر أو الهوتسبوت.
 * يتعرف تلقائياً على الفاصلة (، أو ; أو tab) وعلى أسماء الأعمدة الشائعة.
 */
object CsvImporter {

    private val userKeys = listOf("username", "user", "login", "name", "اسم المستخدم", "المستخدم")
    private val passKeys = listOf("password", "pass", "pwd", "كلمة المرور", "الرمز")
    private val profileKeys = listOf("profile", "userprofname", "group", "tariff", "plan", "الباقة")
    private val priceKeys = listOf("price", "moneypaid", "cost", "amount", "السعر")
    private val validityKeys = listOf("validity", "profile-end-time", "userprofendtime", "end-time", "expiry", "uptime", "limit-uptime", "uptime-limit", "time", "الصلاحية")
    private val commentKeys = listOf("comment", "note", "ملاحظة")

    fun import(context: Context, uri: Uri): List<UserEntry> {
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            ?: return emptyList()
        return parse(text)
    }

    fun parse(text: String): List<UserEntry> {
        val input = text.removePrefix("\uFEFF").trimStart('\r', '\n')
        if (input.isBlank()) return emptyList()
        val records = splitRecords(input, detectDelimiter(input))
            .filter { row -> row.any { it.isNotBlank() } }
        if (records.isEmpty()) return emptyList()
        // Exact aliases: a username such as "user001" is data, not a header.
        val first = records.first().map { it.trim().lowercase() }
        val hasHeader = first.any { it in userKeys }
        val header = if (hasHeader) first else emptyList()
        fun idx(keys: List<String>): Int = header.indexOfFirst { it in keys }
        val ui = if (hasHeader) idx(userKeys) else 0
        val pi = if (hasHeader) idx(passKeys) else 1
        val pri = idx(profileKeys)
        val prc = idx(priceKeys)
        val vi = idx(validityKeys)
        val ci = idx(commentKeys)
        val bi = idx(listOf("batch", "batchtag", "batch_tag", "الدفعة"))

        return (if (hasHeader) records.drop(1) else records).mapNotNull { cells ->
            fun cell(i: Int) = cells.getOrNull(i).orEmpty()
            val username = cell(ui).trim()
            if (username.isBlank()) return@mapNotNull null
            UserEntry(
                username = username,
                // No positional fallback for a missing named password column.
                password = cell(pi),
                profile = cell(pri).trim(),
                price = cell(prc).trim(),
                validity = cell(vi).trim(),
                comment = cell(ci),
                batchTag = cell(bi).trim(),
            )
        }
    }

    private fun detectDelimiter(text: String): Char {
        val counts = linkedMapOf(',' to 0, ';' to 0, '\t' to 0, '|' to 0, '،' to 0)
        var quoted = false
        var i = 0
        while (i < text.length) {
            val ch = text[i]
            if (ch == '"') {
                if (quoted && text.getOrNull(i + 1) == '"') i++ else quoted = !quoted
            } else if (!quoted) {
                if (ch == '\r' || ch == '\n') break
                if (ch in counts) counts[ch] = counts.getValue(ch) + 1
            }
            i++
        }
        return counts.maxByOrNull { it.value }!!.key
    }

    /** CSV records may contain escaped quotes, delimiters and embedded newlines. */
    private fun splitRecords(text: String, delimiter: Char): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var quoted = false
        var closedQuote = false
        fun endField() {
            row.add(field.toString())
            field.clear()
            closedQuote = false
        }
        var i = 0
        while (i < text.length) {
            val ch = text[i]
            when {
                quoted && ch == '"' -> {
                    if (text.getOrNull(i + 1) == '"') { field.append('"'); i++ }
                    else { quoted = false; closedQuote = true }
                }
                quoted -> field.append(ch)
                ch == delimiter -> endField()
                ch == '\r' || ch == '\n' -> {
                    endField(); rows.add(row); row = mutableListOf()
                    if (ch == '\r' && text.getOrNull(i + 1) == '\n') i++
                }
                closedQuote && ch.isWhitespace() -> Unit
                closedQuote -> throw IllegalArgumentException("تنسيق CSV غير صالح بعد علامة الاقتباس")
                ch == '"' && field.isEmpty() -> quoted = true
                else -> field.append(ch)
            }
            i++
        }
        require(!quoted) { "ملف CSV غير مكتمل: علامة اقتباس غير مغلقة" }
        endField(); rows.add(row)
        return rows
    }
}
