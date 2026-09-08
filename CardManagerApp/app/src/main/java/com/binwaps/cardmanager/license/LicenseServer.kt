package com.binwaps.cardmanager.license

import android.content.Context
import com.binwaps.cardmanager.data.BackendConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** HTTPS licensing with a pinned provider key, signed device proof and original signed leases. */
object LicenseServer {

    private const val PREFS = "license_server"
    private const val KEY_LAST_OK = "last_online_ok"
    private const val KEY_LAST_STATE = "last_state_json"

    private const val TIMEOUT_MS = 8_000

    /**
     * تهدئة بعد فشل شبكي: إن كان الخادم غير منشور أو الجهاز بلا إنترنت،
     * فلا معنى لانتظار مهلة كاملة عند كل نبضة. لا تُطبَّق على الطلبات التي
     * يبدأها المستخدم بنفسه — هو ينتظر جواباً حقيقياً.
     */
    @Volatile private var lastFailAt = 0L
    private const val COOLDOWN_MS = 60_000L
    private fun coolingDown() = lastFailAt > 0 && System.currentTimeMillis() - lastFailAt < COOLDOWN_MS

    val configured: Boolean get() = BackendConfig.LICENSE_SERVER.isNotBlank()

    private lateinit var appContext: Context
    fun init(context: Context) { appContext = context.applicationContext; LicenseConnection.init(context) }

    private fun prefs() = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** حالة الحساب كما قررها الخادم */
    data class ServerState(
        val status: String,
        val valid: Boolean,
        val reason: String = "",
        val plan: String = "",
        val daysLeft: Int = 0,
        val expiresAt: Long = 0,
        val graceHours: Int = 72,
        val issuedAt: Long = 0,
    )

    /**
     * رفض صريح من الخادم (٤xx) — قرار وليس انقطاعاً.
     * التفريق مهم: انقطاع الشبكة يُتسامح معه، أما الرفض فيُنفَّذ فوراً.
     */
    class Rejected(message: String) : Exception(message)

    // ==================== الشبكة ====================

    private fun request(path: String, body: JSONObject?): String {
        require(BackendConfig.LICENSE_SERVER.startsWith("https://")) { "الاتصال الآمن HTTPS مطلوب" }
        val url = URL(BackendConfig.LICENSE_SERVER.trimEnd('/') + path)
        val con = (url.openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = false
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            requestMethod = if (body == null) "GET" else "POST"
            setRequestProperty("Accept", "application/json")
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
            }
        }
        try {
            if (body != null) {
                con.outputStream.use { it.write(DeviceIdentity.envelope(path, body).toString().toByteArray(Charsets.UTF_8)) }
            }
            val stream = if (con.responseCode in 200..299) con.inputStream else con.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (con.responseCode !in 200..299) {
                val msg = runCatching { JSONObject(text).optString("error") }.getOrNull()
                val text2 = msg?.takeIf { it.isNotBlank() } ?: "الخادم رفض الطلب (${con.responseCode})"
                // 5xx خلل مؤقت في الخادم لا قرار بحق الحساب — يُعامل كانقطاع
                if (con.responseCode in 400..499) throw Rejected(text2) else throw Exception(text2)
            }
            return text
        } finally {
            runCatching { con.disconnect() }
        }
    }

    // ==================== التوقيع ====================

    /**
     * المفتاح المرجعي: من الإعدادات أولاً، ثم المثبَّت سابقاً، ثم — كحل أخير —
     * جلبه من الخادم وتثبيته. الترتيب مقصود: الإعدادات لا تمرّ بالشبكة أصلاً.
     */
    private fun pinnedKey(): ByteArray? = runCatching {
        Base64.getDecoder().decode(BackendConfig.SERVER_PUBLIC_KEY)
    }.getOrNull()

    /** تحويل توقيع P-1363 الخام (64 بايت) إلى DER الذي تفهمه جافا */
    internal fun rawToDer(raw: ByteArray): ByteArray {
        fun trim(b: ByteArray): ByteArray {
            var v = b.dropWhile { it == 0.toByte() }.toByteArray()
            if (v.isEmpty()) v = byteArrayOf(0)
            return if (v[0].toInt() and 0x80 != 0) byteArrayOf(0) + v else v
        }
        val r = trim(raw.copyOfRange(0, 32))
        val s = trim(raw.copyOfRange(32, 64))
        val body = byteArrayOf(0x02, r.size.toByte()) + r + byteArrayOf(0x02, s.size.toByte()) + s
        return byteArrayOf(0x30, body.size.toByte()) + body
    }

    /**
     * يتحقق من التوقيع ويعيد الحمولة الأصلية، أو null إن لم تكن موثوقة.
     *
     * يُشترط أن يحمل الرد نفس الـnonce الذي أرسلناه: التوقيع وحده لا يكفي —
     * فرد قديم صالح التوقيع يمكن إعادة بثّه بعد انتهاء الاشتراك.
     */
    private fun verified(responseText: String, expectNonce: String?): JSONObject? = runCatching {
        val res = JSONObject(responseText)
        val data = res.optString("data")
        val sigB64 = res.optString("signature")
        if (data.isBlank() || sigB64.isBlank()) return null
        val rawBytes = Base64.getDecoder().decode(data)
        val sig = Base64.getDecoder().decode(sigB64)
        if (sig.size != 64) return null

        val keyBytes = pinnedKey() ?: return null
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(keyBytes))
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(key)
        verifier.update(rawBytes)
        if (!verifier.verify(rawToDer(sig))) return null

        val payload = JSONObject(String(rawBytes, Charsets.UTF_8))
        if (expectNonce != null && payload.optString("nonce") != expectNonce) return null
        if (payload.optString("device") != LicenseCore.deviceCode(appContext)) return null
        if (payload.optString("clientKey") != DeviceIdentity.publicKey()) return null
        val issued = payload.optLong("issuedAt")
        if (issued <= 0) return null
        if (expectNonce != null && kotlin.math.abs(System.currentTimeMillis() - issued) > 300_000L) return null
        if (expectNonce != null) {
            // Retain original signed bytes, never an unsigned reconstruction of the decision.
            prefs().edit().putString(KEY_LAST_STATE, responseText)
                .putLong(KEY_LAST_OK, System.currentTimeMillis())
                .putLong("receipt_elapsed", android.os.SystemClock.elapsedRealtime())
                .putInt("receipt_boot", bootCount()).apply()
        }
        payload
    }.getOrNull()

    private fun newNonce() = java.util.UUID.randomUUID().toString()

    private fun toState(o: JSONObject) = ServerState(
        status = o.optString("status"),
        valid = o.optBoolean("valid"),
        reason = o.optString("reason"),
        plan = o.optString("plan"),
        daysLeft = o.optInt("daysLeft"),
        expiresAt = o.optLong("expiresAt"),
        graceHours = o.optInt("graceHours", 72),
        issuedAt = o.optLong("issuedAt"),
    )

    private fun bootCount(): Int = android.provider.Settings.Global.getInt(
        appContext.contentResolver, android.provider.Settings.Global.BOOT_COUNT, -1)

    /** Re-verify the cached signature and bind it to this device on every access decision. */
    fun cachedStateWithinGrace(): ServerState? {
        if (!configured || !::appContext.isInitialized) return null
        val envelope = prefs().getString(KEY_LAST_STATE, null) ?: return null
        val o = verified(envelope, null) ?: return null
        val state = toState(o)
        if (!state.valid) return state // Server denials never fall back to a local license.
        val wallNow = System.currentTimeMillis()
        val boot = bootCount()
        if (boot < 0 || prefs().getInt("receipt_boot", -2) != boot) return null
        val received = prefs().getLong("receipt_elapsed", -1)
        val elapsed = android.os.SystemClock.elapsedRealtime() - received
        if (received < 0 || elapsed < 0) return null
        val monotonicNow = state.issuedAt + elapsed
        val now = maxOf(wallNow, monotonicNow)
        val age = now - state.issuedAt
        if (age < 0 || age > state.graceHours.coerceIn(0, 72) * 3600_000L) return null
        if (state.expiresAt <= now) return state.copy(valid = false,
            status = if (state.status == "trial") "trial_ended" else "expired")
        return state.copy(daysLeft = ((state.expiresAt - now + 86_399_999L) / 86_400_000L).toInt())
    }

    // ==================== العمليات ====================

    suspend fun register(
        email: String, name: String, phone: String, device: String,
    ): Result<ServerState> = withContext(Dispatchers.IO) {
        runCatching {
            val nonce = newNonce()
            val body = JSONObject()
                .put("email", email).put("name", name)
                .put("phone", phone).put("device", device).put("nonce", nonce)
            val o = verified(request("/api/register", body), nonce)
                ?: throw Exception("رد الخادم غير موثوق — تعذّر التحقق من توقيعه")
            toState(o)
        }
    }

    /** @param userInitiated يتجاوز التهدئة لأن المستخدم ينتظر جواباً الآن */
    suspend fun check(
        email: String, device: String, userInitiated: Boolean = false,
    ): Result<ServerState> = withContext(Dispatchers.IO) {
        if (!userInitiated && coolingDown()) {
            return@withContext Result.failure(Exception("تعذّر الوصول لخادم التراخيص"))
        }
        runCatching {
            val nonce = newNonce()
            val body = JSONObject()
                .put("email", email).put("device", device).put("nonce", nonce)
            val o = verified(request("/api/check", body), nonce)
                ?: throw Exception("رد الخادم غير موثوق — تعذّر التحقق من توقيعه")
            toState(o).also { lastFailAt = 0 }
        }.onFailure { if (it !is Rejected) lastFailAt = System.currentTimeMillis() }
    }

    /** يرفع ملخّص الراوترات (اسم + عنوان، بلا كلمات مرور) فيراها الأدمن */
    suspend fun pushRouters(
        email: String, device: String, routers: List<Pair<String, String>>,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val arr = org.json.JSONArray()
            routers.forEach { arr.put(JSONObject().put("name", it.first).put("host", it.second)) }
            request("/api/routers", JSONObject().put("email", email).put("device", device).put("routers", arr))
            Unit
        }
    }

    suspend fun requestLicense(
        email: String, device: String, renewal: Boolean, note: String = "",
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val body = JSONObject()
                .put("email", email).put("device", device)
                .put("renewal", renewal).put("note", note)
            val res = JSONObject(request("/api/request", body))
            res.optString("message").ifBlank { "وصل طلبك — بانتظار الموافقة" }
        }
    }
}
