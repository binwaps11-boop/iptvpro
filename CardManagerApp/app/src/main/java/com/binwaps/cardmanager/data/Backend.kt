package com.binwaps.cardmanager.data

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * الربط السحابي الحي بين تطبيق المشترك ولوحة الأدمن عبر Firebase Firestore.
 *
 * البنية:
 *   accounts/{id}                 حساب مشترك: البريد، الاسم، الجوال، الجهاز، الحالة، المفتاح…
 *   accounts/{id}/chat/{msgId}    رسائل الدردشة بين الأدمن والمشترك
 *
 * كل شيء لحظي: الأدمن يستمع للطلبات فتصل فور إرسالها، والمشترك يستمع لحسابه
 * فيُفعَّل تلقائياً عند إصدار المفتاح، والدردشة تصل الطرفين مباشرة.
 *
 * إن لم تُملأ [BackendConfig] يبقى [ready] = false ويعمل التطبيق دون سحابة.
 */
object Backend {

    private var db: FirebaseFirestore? = null
    private var auth: FirebaseAuth? = null

    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> get() = _ready

    /** آخر خطأ سحابي بالعربية — لعرضه في الواجهة */
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> get() = _error

    fun init(context: Context) {
        if (!BackendConfig.enabled) return
        runCatching {
            val name = "cardmanager"
            val existing = FirebaseApp.getApps(context).firstOrNull { it.name == name }
            val app = existing ?: FirebaseApp.initializeApp(
                context,
                FirebaseOptions.Builder()
                    .setApiKey(BackendConfig.API_KEY)
                    .setApplicationId(BackendConfig.APP_ID)
                    .setProjectId(BackendConfig.PROJECT_ID)
                    .apply {
                        if (BackendConfig.SENDER_ID.isNotBlank()) setGcmSenderId(BackendConfig.SENDER_ID)
                        if (BackendConfig.STORAGE_BUCKET.isNotBlank()) setStorageBucket(BackendConfig.STORAGE_BUCKET)
                    }
                    .build(),
                name,
            )
            db = FirebaseFirestore.getInstance(app)
            auth = FirebaseAuth.getInstance(app)
            // دخول مجهول — قواعد Firestore تسمح للمصادَقين
            auth?.signInAnonymously()
                ?.addOnSuccessListener { _ready.value = true }
                ?.addOnFailureListener { _ready.value = false; _error.value = arabic(it) }
        }.onFailure {
            _ready.value = false
            _error.value = arabic(it)
        }
    }

    private fun accounts() = db?.collection("accounts")

    /** معرّف مستقر للحساب من البريد (أو رمز الجهاز إن لم يوجد بريد) */
    fun accountId(email: String, deviceCode: String): String {
        val base = email.trim().lowercase().ifBlank { "device_$deviceCode" }
        return base.replace(Regex("[^a-z0-9._-]"), "_").take(120).ifBlank { "acc_$deviceCode" }
    }

    // ==================== كتابة (المشترك) ====================

    /** المشترك يسجّل بريده — يظهر للأدمن كحساب في التجربة */
    fun registerAccount(email: String, name: String, phone: String, deviceCode: String) {
        val col = accounts() ?: return
        val id = accountId(email, deviceCode)
        col.document(id).set(
            mapOf(
                "email" to email.trim(),
                "name" to name.trim(),
                "phone" to phone.trim(),
                "deviceCode" to deviceCode.trim(),
                "status" to "trial",
                "registeredAt" to System.currentTimeMillis(),
            ),
            com.google.firebase.firestore.SetOptions.merge(),
        )
    }

    /** المشترك يرسل طلب ترخيص — يصل لوحة الأدمن لحظياً */
    fun submitRequest(
        email: String, name: String, phone: String, deviceCode: String, renewal: Boolean,
        onResult: (ok: Boolean, id: String) -> Unit = { _, _ -> },
    ) {
        val col = accounts() ?: return onResult(false, "")
        val id = accountId(email, deviceCode)
        val data = mapOf(
            "email" to email.trim(),
            "name" to name.trim(),
            "phone" to phone.trim(),
            "deviceCode" to deviceCode.trim(),
            "status" to "pending",
            "renewal" to renewal,
            "requestedAt" to System.currentTimeMillis(),
        )
        col.document(id).set(data, com.google.firebase.firestore.SetOptions.merge())
            .addOnSuccessListener { onResult(true, id) }
            .addOnFailureListener { _error.value = arabic(it); onResult(false, id) }
    }

    // ==================== كتابة (الأدمن) ====================

    /** الأدمن يوافق ويصدر المفتاح — يصل المشترك لحظياً فيُفعَّل تلقائياً */
    fun issue(
        id: String, key: String, planCode: Int, expiresAt: Long, boundDevice: String,
        onResult: (Boolean) -> Unit = {},
    ) {
        val col = accounts() ?: return onResult(false)
        col.document(id).set(
            mapOf(
                "status" to "approved",
                "key" to key,
                "planCode" to planCode,
                "expiresAt" to expiresAt,
                "boundDevice" to boundDevice,
                "issuedAt" to System.currentTimeMillis(),
            ),
            com.google.firebase.firestore.SetOptions.merge(),
        ).addOnSuccessListener { onResult(true) }
            .addOnFailureListener { _error.value = arabic(it); onResult(false) }
    }

    fun deleteAccount(id: String) {
        accounts()?.document(id)?.delete()
    }

    /**
     * إيقاف/استئناف حساب عن بعد — القرار من الأدمن يصل المشترك لحظياً
     * فيُقفل تطبيقه (أو يعود) دون أي ملف محلي يمكن التلاعب به.
     */
    fun setSuspended(id: String, suspended: Boolean, onResult: (Boolean) -> Unit = {}) {
        val col = accounts() ?: return onResult(false)
        col.document(id).set(
            mapOf("status" to if (suspended) "suspended" else "approved"),
            com.google.firebase.firestore.SetOptions.merge(),
        ).addOnSuccessListener { onResult(true) }
            .addOnFailureListener { _error.value = arabic(it); onResult(false) }
    }

    // ==================== استماع ====================

    /** الأدمن: يستمع لكل الحسابات لحظياً (الطلبات والمشتركون) */
    fun listenAccounts(onChange: (List<CloudAccount>) -> Unit): ListenerRegistration? =
        accounts()?.orderBy("requestedAt", Query.Direction.DESCENDING)
            ?.addSnapshotListener { snap, err ->
                if (err != null) { _error.value = arabic(err); return@addSnapshotListener }
                onChange(snap?.documents?.mapNotNull { it.toCloudAccount() } ?: emptyList())
            }

    /** المشترك: يستمع لحسابه فقط — يُفعَّل تلقائياً عند وصول المفتاح */
    fun listenAccount(id: String, onChange: (CloudAccount?) -> Unit): ListenerRegistration? =
        accounts()?.document(id)?.addSnapshotListener { doc, err ->
            if (err != null) { _error.value = arabic(err); return@addSnapshotListener }
            onChange(doc?.toCloudAccount())
        }

    // ==================== الدردشة ====================

    fun sendMessage(accountId: String, fromAdmin: Boolean, text: String) {
        val col = accounts()?.document(accountId)?.collection("chat") ?: return
        col.add(
            mapOf(
                "from" to if (fromAdmin) "admin" else "user",
                "text" to text.trim(),
                "at" to System.currentTimeMillis(),
            )
        )
    }

    fun listenChat(accountId: String, onChange: (List<ChatMessage>) -> Unit): ListenerRegistration? =
        accounts()?.document(accountId)?.collection("chat")
            ?.orderBy("at", Query.Direction.ASCENDING)
            ?.addSnapshotListener { snap, err ->
                if (err != null) return@addSnapshotListener
                onChange(
                    snap?.documents?.map {
                        ChatMessage(
                            fromAdmin = it.getString("from") == "admin",
                            text = it.getString("text").orEmpty(),
                            at = it.getLong("at") ?: 0,
                        )
                    } ?: emptyList()
                )
            }

    private fun com.google.firebase.firestore.DocumentSnapshot.toCloudAccount(): CloudAccount? {
        if (!exists()) return null
        return CloudAccount(
            id = id,
            email = getString("email").orEmpty(),
            name = getString("name").orEmpty(),
            phone = getString("phone").orEmpty(),
            deviceCode = getString("deviceCode").orEmpty(),
            status = getString("status").orEmpty(),
            key = getString("key").orEmpty(),
            planCode = (getLong("planCode") ?: 1).toInt(),
            expiresAt = getLong("expiresAt") ?: 0,
            boundDevice = getString("boundDevice").orEmpty(),
            renewal = getBoolean("renewal") ?: false,
            requestedAt = getLong("requestedAt") ?: 0,
            issuedAt = getLong("issuedAt") ?: 0,
        )
    }

    private fun arabic(t: Throwable): String {
        val raw = t.message ?: "خطأ سحابي"
        return when {
            raw.contains("PERMISSION_DENIED", true) ->
                "قواعد Firestore ترفض الوصول — اضبطها على وضع الاختبار أو اسمح للمصادَقين"
            raw.contains("UNAVAILABLE", true) || raw.contains("network", true) ->
                "لا يوجد اتصال بالإنترنت"
            raw.contains("API key", true) || raw.contains("api-key", true) ->
                "مفتاح Firebase غير صحيح — تأكد من apiKey في الإعدادات"
            else -> raw
        }
    }
}

/** حساب كما هو في السحابة */
data class CloudAccount(
    val id: String,
    val email: String,
    val name: String,
    val phone: String,
    val deviceCode: String,
    val status: String,
    val key: String,
    val planCode: Int,
    val expiresAt: Long,
    val boundDevice: String,
    val renewal: Boolean,
    val requestedAt: Long,
    val issuedAt: Long,
) {
    val pending: Boolean get() = status == "pending"
    val approved: Boolean get() = status == "approved" && key.isNotBlank()
}

data class ChatMessage(val fromAdmin: Boolean, val text: String, val at: Long)
