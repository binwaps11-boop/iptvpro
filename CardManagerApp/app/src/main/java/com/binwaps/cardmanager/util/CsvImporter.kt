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
    private val profileKeys = listOf("profile", "group", "plan", "الباقة")
    private val priceKeys = listOf("price", "cost", "amount", "السعر")
    private val validityKeys = listOf("validity", "uptime", "limit-uptime", "uptime-limit", "time", "الصلاحية")
    private val commentKeys = listOf("comment", "note", "ملاحظة")

    fun import(context: Context, uri: Uri): List<UserEntry> {
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            ?: return emptyList()
        return parse(text)
    }

    fun parse(text: String): List<UserEntry> {
        val lines = text.split("\r\n", "\n").map { it.trim() }.filter { it.isNotBlank() }
        if (lines.isEmpty()) return emptyList()

        val delimiter = detectDelimiter(lines.first())
        val firstCells = splitLine(lines.first(), delimiter)
        val hasHeader = firstCells.any { cell -> userKeys.any { cell.lowercase().contains(it) } }

        val header = if (hasHeader) firstCells.map { it.lowercase().trim().trim('"') } else emptyList()
        val dataLines = if (hasHeader) lines.drop(1) else lines

        fun idx(keys: List<String>): Int = header.indexOfFirst { h -> keys.any { h == it || h.contains(it) } }

        val ui = if (hasHeader) idx(userKeys) else 0
        val pi = if (hasHeader) idx(passKeys) else 1
        val pri = if (hasHeader) idx(profileKeys) else -1
        val prc = if (hasHeader) idx(priceKeys) else -1
        val vi = if (hasHeader) idx(validityKeys) else -1
        val ci = if (hasHeader) idx(commentKeys) else -1

        return dataLines.mapNotNull { line ->
            val cells = splitLine(line, delimiter).map { it.trim().trim('"') }
            fun cell(i: Int) = if (i in cells.indices) cells[i] else ""
            val username = cell(if (ui >= 0) ui else 0)
            if (username.isBlank()) return@mapNotNull null
            UserEntry(
                username = username,
                password = cell(if (pi >= 0) pi else 1),
                profile = cell(pri),
                price = cell(prc),
                validity = cell(vi),
                comment = cell(ci),
            )
        }
    }

    private fun detectDelimiter(line: String): Char {
        val candidates = listOf(',', ';', '\t', '|')
        return candidates.maxByOrNull { c -> line.count { it == c } } ?: ','
    }

    private fun splitLine(line: String, delimiter: Char): List<String> {
        val result = mutableListOf<String>()
        val sb = StringBuilder()
        var inQuotes = false
        for (ch in line) {
            when {
                ch == '"' -> inQuotes = !inQuotes
                ch == delimiter && !inQuotes -> { result.add(sb.toString()); sb.clear() }
                else -> sb.append(ch)
            }
        }
        result.add(sb.toString())
        return result
    }
}
