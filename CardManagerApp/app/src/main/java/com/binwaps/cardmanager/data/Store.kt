package com.binwaps.cardmanager.data

import android.content.Context
import android.net.Uri
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * تخزين بسيط بملفات JSON داخل مجلد التطبيق:
 * templates.json / users.json / settings.json
 */
object Store {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }

    private lateinit var appContext: Context

    private val _templates = MutableStateFlow<List<CardTemplate>>(emptyList())
    val templates: StateFlow<List<CardTemplate>> get() = _templates

    private val _users = MutableStateFlow<List<UserEntry>>(emptyList())
    val users: StateFlow<List<UserEntry>> get() = _users

    private val _settings = MutableStateFlow(AppSettings())
    val settings: StateFlow<AppSettings> get() = _settings

    fun init(context: Context) {
        appContext = context.applicationContext
        _templates.value = load("templates.json") ?: listOf(defaultTemplate())
        _users.value = load("users.json") ?: emptyList()
        _settings.value = load("settings.json") ?: AppSettings()
    }

    private inline fun <reified T> load(name: String): T? = runCatching {
        val f = File(appContext.filesDir, name)
        if (!f.exists()) null else json.decodeFromString<T>(f.readText())
    }.getOrNull()

    private inline fun <reified T> save(name: String, value: T) = runCatching {
        File(appContext.filesDir, name).writeText(json.encodeToString(value))
    }

    fun setUsers(list: List<UserEntry>) {
        _users.value = list
        save("users.json", list)
    }

    fun addUsers(list: List<UserEntry>) = setUsers(_users.value + list)

    fun clearUsers() = setUsers(emptyList())

    fun upsertTemplate(t: CardTemplate) {
        val cur = _templates.value
        _templates.value = if (cur.any { it.id == t.id }) cur.map { if (it.id == t.id) t else it } else cur + t
        save("templates.json", _templates.value)
    }

    fun deleteTemplate(id: Long) {
        _templates.value = _templates.value.filterNot { it.id == id }
        save("templates.json", _templates.value)
    }

    fun template(id: Long): CardTemplate? = _templates.value.firstOrNull { it.id == id }

    fun updateSettings(s: AppSettings) {
        _settings.value = s
        save("settings.json", s)
    }

    /** نسخ صورة خلفية مختارة من الجوال إلى مجلد القوالب وإرجاع مسارها */
    fun importBackground(uri: Uri): String? = runCatching {
        val dir = File(appContext.filesDir, "templates").apply { mkdirs() }
        val out = File(dir, "bg_${System.currentTimeMillis()}.img")
        appContext.contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { input.copyTo(it) }
        }
        out.absolutePath
    }.getOrNull()

    fun newId(): Long = System.currentTimeMillis() + (0..999).random()

    fun defaultTemplate(): CardTemplate = CardTemplate(
        id = 1L,
        name = "قالب افتراضي",
        fields = listOf(
            CardField(id = 1, type = FieldType.CUSTOM_TEXT, customText = "كرت انترنت", xFrac = 0.5f, yFrac = 0.14f, sizeFrac = 0.13f, color = 0xFF0B5E4F),
            CardField(id = 2, type = FieldType.USERNAME, prefix = "المستخدم: ", xFrac = 0.5f, yFrac = 0.40f, sizeFrac = 0.11f),
            CardField(id = 3, type = FieldType.PASSWORD, prefix = "الرمز: ", xFrac = 0.5f, yFrac = 0.58f, sizeFrac = 0.11f),
            CardField(id = 4, type = FieldType.PRICE, xFrac = 0.16f, yFrac = 0.84f, sizeFrac = 0.10f, color = 0xFFB71C1C),
            CardField(id = 5, type = FieldType.VALIDITY, xFrac = 0.80f, yFrac = 0.84f, sizeFrac = 0.08f),
        ),
    )
}
