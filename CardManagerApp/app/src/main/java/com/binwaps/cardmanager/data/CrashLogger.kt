package com.binwaps.cardmanager.data

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * يحفظ أي انهيار في ملف داخل التطبيق ليتمكن المستخدم من إرساله.
 * بدون هذا لا توجد طريقة لمعرفة سبب خروج التطبيق على جهاز المستخدم.
 */
object CrashLogger {
    private const val FILE = "last_crash.txt"
    private lateinit var appContext: Context

    fun install(context: Context) {
        appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                val stamp = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US).format(Date())
                val text = buildString {
                    appendLine("وقت الانهيار: $stamp")
                    appendLine("الخيط: ${thread.name}")
                    appendLine("النوع: ${error::class.java.name}")
                    appendLine("الرسالة: ${error.message}")
                    appendLine()
                    appendLine(error.stackTraceToString())
                    error.cause?.let {
                        appendLine()
                        appendLine("السبب الأصلي: ${it::class.java.name}: ${it.message}")
                        appendLine(it.stackTraceToString())
                    }
                }
                File(appContext.filesDir, FILE).writeText(text)
            }
            previous?.uncaughtException(thread, error)
        }
    }

    fun lastCrash(): String? = runCatching {
        val f = File(appContext.filesDir, FILE)
        if (f.exists()) f.readText() else null
    }.getOrNull()

    fun clear() {
        runCatching { File(appContext.filesDir, FILE).delete() }
    }
}
