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

/**
 * عميل خادم التراخيص — القرار على الخادم لا على الجهاز.
 *
 * كل رد يصل موقّعاً بـ ECDSA P-256؛ المفتاح الخاص لا يغادر الخادم، والتطبيق
 * يتحقق من التوقيع قبل الوثوق بأي حالة. حمولة الرد تُنقل كنص base64 ويُتحقق
 * من نفس بايتاتها بالضبط — إعادة تسلسل JSON كانت ستغيّر الترتيب فيفشل التحقق.
 *
 * المفتاح العام يُقرأ من BackendConfig إن مُلئ — وهذا هو الوضع الصحيح.
 * إن تُرك فارغاً يُجلب عند أول اتصال ويُثبَّت (TOFU)، وهو أضعف بوضوح: فوق HTTP
 * يستطيع وسيط على الشبكة زرع مفتاحه في تلك اللحظة فتُقبل ردوده المزوّرة بعدها.
 * املأ SERVER_PUBLIC_KEY بما يطبعه install.sh ليختفي هذا الباب تماماً.
 */
object LicenseServer {

    private const val PREFS = "license_server"
    private const val KEY_PINNED_PUBKEY = "pinned_pubkey"
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
    fun init(context: Context) { appContext = context.applicationContext }

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
        val url = URL(BackendConfig.LICENSE_SERVER.trimEnd('/') + path)
        val con = (url.openConnection() as HttpURLConnection).apply {
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
                con.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
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
    private fun pinnedKey(): ByteArray? {
        // المضمّن في الإعدادات يسبق أي شيء، ويصحّح تثبيتاً سابقاً خاطئاً:
        // لو زُرع مفتاح مزوّر بـTOFU ثم مُلئت الإعدادات، يجب أن يُزاح لا أن يبقى
        BackendConfig.SERVER_PUBLIC_KEY.takeIf { it.isNotBlank() }?.let { embedded ->
            prefs().edit().putString(KEY_PINNED_PUBKEY, embedded).apply()
            return runCatching { Base64.getDecoder().decode(embedded) }.getOrNull()
        }
        prefs().getString(KEY_PINNED_PUBKEY, null)?.let {
            return runCatching { Base64.getDecoder().decode(it) }.getOrNull()
        }
        val fetched = runCatching {
            JSONObject(request("/api/pubkey", null)).optString("publicKey")
        }.getOrNull()?.takeIf { it.isNotBlank() } ?: return null
        prefs().edit().putString(KEY_PINNED_PUBKEY, fetched).apply()
        return runCatching { Base64.getDecoder().decode(fetched) }.getOrNull()
    }

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
    private fun verified(responseText: String, expectNonce: String): JSONObject? = runCatching {
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
        if (payload.optString("nonce") != expectNonce) return null
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

    private fun remember(state: ServerState) {
        prefs().edit()
            .putLong(KEY_LAST_OK, System.currentTimeMillis())
            .putString(
                KEY_LAST_STATE,
                JSONObject()
                    .put("status", state.status).put("valid", state.valid)
                    .put("reason", state.reason).put("plan", state.plan)
                    .put("daysLeft", state.daysLeft).put("expiresAt", state.expiresAt)
                    .put("graceHours", state.graceHours).toString(),
            )
            .apply()
    }

    /**
     * آخر حالة موقّعة محفوظة، ما دامت ضمن مهلة السماح بلا إنترنت.
     * بعدها تُعاد null فيلزم التحقق أونلاين — لا استخدام دائم بلا اتصال.
     */
    fun cachedStateWithinGrace(): ServerState? {
        if (!configured || !::appContext.isInitialized) return null
        val at = prefs().getLong(KEY_LAST_OK, 0)
        val json = prefs().getString(KEY_LAST_STATE, null) ?: return null
        val o = runCatching { JSONObject(json) }.getOrNull() ?: return null
        val graceMs = o.optInt("graceHours", 72) * 3600_000L
        if (at <= 0 || System.currentTimeMillis() - at > graceMs) return null
        return toState(o)
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
            toState(o).also { remember(it) }
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
            toState(o).also { remember(it); lastFailAt = 0 }
        }.onFailure { if (it !is Rejected) lastFailAt = System.currentTimeMillis() }
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
