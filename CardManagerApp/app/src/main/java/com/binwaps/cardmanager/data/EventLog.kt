package com.binwaps.cardmanager.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * سجل عمليات مرئي للمستخدم: كل اتصال ورفع وطباعة وتوليد مع نتيجته الحقيقية.
 *
 * سببه: عند قول «لا يتصل» أو «لا يرفع» لا توجد أي طريقة لمعرفة أين توقف
 * الأمر على جهاز المستخدم. هذا السجل يُعرض في الإعدادات ويُرسل بضغطة،
 * فتتحول الشكوى العامة إلى سبب محدد.
 *
 * لا يُسجَّل أي سرّ: كلمات مرور الراوتر ومفاتيح الترخيص لا تدخل هنا أبداً.
 */
object EventLog {

    private const val FILE = "events.log"
    private const val MAX = 300

    data class Event(val at: Long, val tag: String, val text: String, val ok: Boolean)

    private lateinit var appContext: Context
    private val _events = MutableStateFlow<List<Event>>(emptyList())
    val events: StateFlow<List<Event>> get() = _events

    fun init(context: Context) {
        appContext = context.applicationContext
        _events.value = runCatching {
            val f = File(appContext.filesDir, FILE)
            if (!f.exists()) return@runCatching emptyList()
            f.readLines().mapNotNull { line ->
                // الصيغة: at|ok|tag|text
                val p = line.split('|', limit = 4)
                if (p.size < 4) return@mapNotNull null
                Event(p[0].toLongOrNull() ?: 0, p[2], p[3], p[1] == "1")
            }.takeLast(MAX)
        }.getOrDefault(emptyList())
    }

    /** يضيف سطراً للسجل — آمن الاستدعاء من أي خيط */
    fun log(tag: String, text: String, ok: Boolean = true) {
        if (!::appContext.isInitialized) return
        val e = Event(System.currentTimeMillis(), tag, text.replace('\n', ' ').take(400), ok)
        val updated = (_events.value + e).takeLast(MAX)
        _events.value = updated
        Store.io.execute {
            runCatching {
                File(appContext.filesDir, FILE).writeText(
                    updated.joinToString("\n") { "${it.at}|${if (it.ok) 1 else 0}|${it.tag}|${it.text}" }
                )
            }
        }
    }

    fun clear() {
        _events.value = emptyList()
        if (!::appContext.isInitialized) return
        Store.io.execute { runCatching { File(appContext.filesDir, FILE).delete() } }
    }

    /** نص جاهز للإرسال — يشمل معلومات الجهاز والنسخة لتشخيص أسرع */
    fun asText(): String {
        val fmt = SimpleDateFormat("MM/dd HH:mm:ss", Locale.US)
        return buildString {
            appendLine("سجل عمليات مدير الكروت")
            appendLine("الجهاز: ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} — أندرويد ${android.os.Build.VERSION.RELEASE}")
            appendLine("عدد الأحداث: ${_events.value.size}")
            appendLine("————")
            _events.value.forEach {
                appendLine("${fmt.format(Date(it.at))} ${if (it.ok) "✓" else "✗"} [${it.tag}] ${it.text}")
            }
        }
    }
}
