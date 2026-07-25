package com.binwaps.cardmanager.data

import android.content.Context
import android.net.Uri
import com.binwaps.cardmanager.model.ActiveUser
import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.HotspotProfile
import com.binwaps.cardmanager.model.PrintBatch
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.model.RouterStatus
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/** تخزين بملفات JSON داخل مجلد التطبيق */
object Store {
    // JSON مضغوط — الكتابة المنسّقة كانت تضاعف حجم ملفات القوائم الكبيرة
    private val json = Json { ignoreUnknownKeys = true }

    private lateinit var appContext: Context

    private val _templates = MutableStateFlow<List<CardTemplate>>(emptyList())
    val templates: StateFlow<List<CardTemplate>> get() = _templates

    private val _users = MutableStateFlow<List<UserEntry>>(emptyList())
    val users: StateFlow<List<UserEntry>> get() = _users

    private val _settings = MutableStateFlow(AppSettings())
    val settings: StateFlow<AppSettings> get() = _settings

    private val _routers = MutableStateFlow<List<RouterProfile>>(emptyList())
    val routers: StateFlow<List<RouterProfile>> get() = _routers

    private val _batches = MutableStateFlow<List<PrintBatch>>(emptyList())
    val batches: StateFlow<List<PrintBatch>> get() = _batches

    private val _profiles = MutableStateFlow<List<HotspotProfile>>(emptyList())
    val profiles: StateFlow<List<HotspotProfile>> get() = _profiles

    private val _sales = MutableStateFlow<List<com.binwaps.cardmanager.model.SaleEntry>>(emptyList())
    val sales: StateFlow<List<com.binwaps.cardmanager.model.SaleEntry>> get() = _sales

    /** حالة الجلسة الحالية (لا تُحفظ على القرص) */
    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> get() = _connected

    private val _status = MutableStateFlow(RouterStatus())
    val status: StateFlow<RouterStatus> get() = _status

    private val _activeUsers = MutableStateFlow<List<ActiveUser>>(emptyList())
    val activeUsers: StateFlow<List<ActiveUser>> get() = _activeUsers

    fun init(context: Context) {
        appContext = context.applicationContext
        _templates.value = load("templates.json") ?: listOf(defaultTemplate())
        _users.value = load("users.json") ?: emptyList()
        _settings.value = load("settings.json") ?: AppSettings()
        _routers.value = load("routers.json") ?: emptyList()
        _batches.value = load("batches.json") ?: emptyList()
        _profiles.value = load("profiles.json") ?: emptyList()
        _sales.value = load("sales.json") ?: emptyList()
    }

    // ===== المبيعات والصندوق =====
    fun addSale(s: com.binwaps.cardmanager.model.SaleEntry) {
        _sales.value = listOf(s) + _sales.value
        save("sales.json", _sales.value)
    }

    fun deleteSale(id: Long) {
        _sales.value = _sales.value.filterNot { it.id == id }
        save("sales.json", _sales.value)
    }

    fun updateSale(s: com.binwaps.cardmanager.model.SaleEntry) {
        _sales.value = _sales.value.map { if (it.id == s.id) s else it }
        save("sales.json", _sales.value)
    }

    private inline fun <reified T> load(name: String): T? = runCatching {
        val f = File(appContext.filesDir, name)
        if (!f.exists()) null else json.decodeFromString<T>(f.readText())
    }.getOrNull()

    /** يُسلسل فوراً (لالتقاط الحالة الصحيحة) ويكتب على القرص في خيط خلفي حتى لا تتجمد الواجهة */
    private inline fun <reified T> save(name: String, value: T) {
        val text = runCatching { json.encodeToString(value) }.getOrNull() ?: return
        io.execute {
            runCatching { File(appContext.filesDir, name).writeText(text) }
        }
    }

    val io: java.util.concurrent.ExecutorService =
        java.util.concurrent.Executors.newSingleThreadExecutor()

    // ===== المستخدمون =====
    /**
     * يُحفظ على القرص الكروت المحلية فقط. الكروت المجلوبة من الراوتر
     * تبقى في الذاكرة — قد تكون بعشرات الآلاف وكتابتها تجمّد الجهاز،
     * وجلبها من جديد أصبح سريعاً.
     */
    fun setUsers(list: List<UserEntry>) {
        _users.value = list
        save("users.json", list.filter { it.source == com.binwaps.cardmanager.model.CardSource.LOCAL })
    }

    fun addUsers(list: List<UserEntry>) = setUsers(_users.value + list)
    fun clearUsers() = setUsers(emptyList())

    // ===== القوالب =====
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

    // ===== الإعدادات =====
    fun updateSettings(s: AppSettings) {
        _settings.value = s
        save("settings.json", s)
    }

    // ===== الراوترات =====
    fun upsertRouter(r: RouterProfile) {
        val cur = _routers.value
        _routers.value = if (cur.any { it.id == r.id }) cur.map { if (it.id == r.id) r else it } else cur + r
        save("routers.json", _routers.value)
    }

    fun deleteRouter(id: Long) {
        _routers.value = _routers.value.filterNot { it.id == id }
        save("routers.json", _routers.value)
        if (_settings.value.activeRouterId == id) {
            updateSettings(_settings.value.copy(activeRouterId = _routers.value.firstOrNull()?.id ?: 0))
        }
    }

    fun activeRouter(): RouterProfile? =
        _routers.value.firstOrNull { it.id == _settings.value.activeRouterId } ?: _routers.value.firstOrNull()

    fun setActiveRouter(id: Long) = updateSettings(_settings.value.copy(activeRouterId = id))

    // ===== حالة الاتصال =====
    fun setConnected(value: Boolean) { _connected.value = value }

    /** دمج الحالة: التحديث الخفيف لا يحمل عدادات الكروت (-1) فنبقي القديمة */
    fun setStatus(s: RouterStatus) {
        val prev = _status.value
        _status.value = s.copy(
            activeUsers = if (s.activeUsers >= 0) s.activeUsers else prev.activeUsers,
            hotspotUsers = if (s.hotspotUsers >= 0) s.hotspotUsers else prev.hotspotUsers,
            userManagerUsers = if (s.userManagerUsers >= 0) s.userManagerUsers else prev.userManagerUsers,
            usedUsers = if (s.usedUsers >= 0) s.usedUsers else prev.usedUsers,
            identity = s.identity.ifBlank { prev.identity },
            version = s.version.ifBlank { prev.version },
            board = s.board.ifBlank { prev.board },
            uptime = s.uptime.ifBlank { prev.uptime },
            cpuLoad = s.cpuLoad.ifBlank { prev.cpuLoad },
            freeMemory = s.freeMemory.ifBlank { prev.freeMemory },
            totalMemory = s.totalMemory.ifBlank { prev.totalMemory },
        )
    }
    fun setActiveUsers(list: List<ActiveUser>) { _activeUsers.value = list }

    // ===== الباقات =====
    fun setProfiles(list: List<HotspotProfile>) {
        // نحافظ على الأسعار المحفوظة محلياً عند تحديث القائمة من الراوتر
        val prices = _profiles.value.associate { it.name to it.price }
        _profiles.value = list.map { p -> if (p.price.isBlank()) p.copy(price = prices[p.name] ?: "") else p }
        save("profiles.json", _profiles.value)
    }

    fun updateProfilePrice(name: String, price: String) {
        _profiles.value = _profiles.value.map { if (it.name == name) it.copy(price = price) else it }
        save("profiles.json", _profiles.value)
    }

    // ===== سجل الدفعات =====
    fun addBatch(b: PrintBatch) {
        _batches.value = listOf(b) + _batches.value
        save("batches.json", _batches.value)
    }

    fun deleteBatch(id: Long) {
        _batches.value = _batches.value.filterNot { it.id == id }
        save("batches.json", _batches.value)
    }

    fun markReprinted(id: Long) {
        _batches.value = _batches.value.map { if (it.id == id) it.copy(printCount = it.printCount + 1) else it }
        save("batches.json", _batches.value)
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
