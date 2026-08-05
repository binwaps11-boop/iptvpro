package com.binwaps.cardmanager

import android.content.Context
import com.binwaps.cardmanager.data.BackendConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * عميل لوحة الأدمن — يقرأ ويتحكّم في **قاعدة بيانات خادم التراخيص** نفسها
 * التي يسجّل فيها المشتركون. هذا هو الربط الذي كان مفقوداً: قبله كان تطبيق
 * الأدمن يقرأ من ملف محلي/Firestore معطّل فلا يرى طلبات المشتركين.
 *
 * كل نداء يحمل رمز الأدمن في ترويسة x-admin-token (يُدخله الأدمن مرة ويُحفظ).
 */
object AdminApi {

    private const val PREFS = "admin_api"
    private const val KEY_TOKEN = "admin_token"
    private const val TIMEOUT_MS = 12_000

    val serverUrl: String get() = BackendConfig.LICENSE_SERVER
    val configured: Boolean get() = serverUrl.isNotBlank()

    private lateinit var appContext: Context
    fun init(context: Context) { appContext = context.applicationContext }

    private fun prefs() = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun token(): String = prefs().getString(KEY_TOKEN, "").orEmpty()
    fun setToken(value: String) { prefs().edit().putString(KEY_TOKEN, value.trim()).apply() }
    fun hasToken(): Boolean = token().isNotBlank()

    /** حساب كما يراه الأدمن من الخادم */
    data class ServerAccount(
        val id: String,
        val email: String,
        val phone: String,
        val name: String,
        val device: String,
        val plan: String,
        val blocked: Boolean,
        val expiresAt: Long,
        val pending: Boolean,
        val pendingRenewal: Boolean,
        val status: String,
        val valid: Boolean,
        val daysLeft: Int,
        val routers: List<Pair<String, String>>, // (name, host)
    )

    private fun request(path: String, body: JSONObject?): String {
        val url = URL(serverUrl.trimEnd('/') + path)
        val con = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            requestMethod = if (body == null) "GET" else "POST"
            setRequestProperty("Accept", "application/json")
            setRequestProperty("x-admin-token", token())
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
            }
        }
        try {
            if (body != null) {
                con.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val ok = con.responseCode in 200..299
            val text = (if (ok) con.inputStream else con.errorStream)
                ?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (!ok) {
                val msg = runCatching { JSONObject(text).optString("error") }.getOrNull()
                throw Exception(
                    when (con.responseCode) {
                        401 -> "رمز الأدمن غير صحيح"
                        else -> msg?.takeIf { it.isNotBlank() } ?: "الخادم رفض الطلب (${con.responseCode})"
                    },
                )
            }
            return text
        } finally {
            runCatching { con.disconnect() }
        }
    }

    private fun parseAccount(o: JSONObject): ServerAccount {
        val st = o.optJSONObject("state") ?: JSONObject()
        val routers = mutableListOf<Pair<String, String>>()
        o.optJSONArray("routers")?.let { arr ->
            for (i in 0 until arr.length()) {
                val r = arr.optJSONObject(i) ?: continue
                routers.add(r.optString("name") to r.optString("host"))
            }
        }
        val pending = o.optJSONObject("pending")
        return ServerAccount(
            id = o.optString("id"),
            email = o.optString("email"),
            phone = o.optString("phone"),
            name = o.optString("name"),
            device = o.optString("device"),
            plan = o.optString("plan"),
            blocked = o.optBoolean("blocked"),
            expiresAt = o.optLong("expiresAt"),
            pending = pending != null,
            pendingRenewal = pending?.optBoolean("renewal") ?: false,
            status = st.optString("status"),
            valid = st.optBoolean("valid"),
            daysLeft = st.optInt("daysLeft"),
            routers = routers,
        )
    }

    suspend fun accounts(): Result<List<ServerAccount>> = withContext(Dispatchers.IO) {
        runCatching {
            val arr: JSONArray = JSONObject(request("/api/admin/accounts", null)).optJSONArray("accounts")
                ?: JSONArray()
            (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.let(::parseAccount) }
        }
    }

    /** خطط: month / quarter / year / lifetime */
    suspend fun approve(id: String, plan: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching { request("/api/admin/approve", JSONObject().put("id", id).put("plan", plan)); Unit }
    }

    suspend fun block(id: String, blocked: Boolean): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching { request("/api/admin/block", JSONObject().put("id", id).put("blocked", blocked)); Unit }
    }

    suspend fun rebind(id: String, device: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching { request("/api/admin/rebind", JSONObject().put("id", id).put("device", device)); Unit }
    }
}
