package com.binwaps.cardmanager.license

import android.net.Uri

/**
 * الربط بين تطبيق المشترك ولوحة التراخيص عبر روابط.
 *
 * - المشترك يرسل رابط طلب: cardmanager-admin://request?d=<رمز الجهاز>&n=<الاسم>
 *   عند الضغط عليه يفتح تطبيق الأدمن والبيانات مملوءة تلقائياً.
 * - الأدمن يرد برابط تفعيل: cardmanager://activate?k=<المفتاح>
 *   عند الضغط عليه يفتح تطبيق المشترك ويُفعَّل فوراً.
 *
 * لا يحتاج خادماً — الروابط تُرسل عبر واتساب أو أي تطبيق مراسلة.
 */
object LicenseLink {

    const val SCHEME_ADMIN = "cardmanager-admin"
    const val SCHEME_APP = "cardmanager"

    // ===== طلب الترخيص (من المشترك إلى الأدمن) =====

    data class Request(
        val deviceCode: String,
        val name: String,
        val renewal: Boolean,
        val email: String = "",
        val phone: String = "",
    )

    fun buildRequest(
        deviceCode: String,
        name: String,
        renewal: Boolean = false,
        email: String = "",
        phone: String = "",
    ): String =
        Uri.Builder()
            .scheme(SCHEME_ADMIN)
            .authority("request")
            .appendQueryParameter("d", deviceCode)
            .apply { if (name.isNotBlank()) appendQueryParameter("n", name) }
            .apply { if (email.isNotBlank()) appendQueryParameter("e", email) }
            .apply { if (phone.isNotBlank()) appendQueryParameter("p", phone) }
            .apply { if (renewal) appendQueryParameter("r", "1") }
            .build()
            .toString()

    fun parseRequest(uri: Uri?): Request? {
        if (uri == null || uri.scheme != SCHEME_ADMIN) return null
        val device = uri.getQueryParameter("d")?.takeIf { it.isNotBlank() } ?: return null
        return Request(
            deviceCode = device,
            name = uri.getQueryParameter("n").orEmpty(),
            renewal = uri.getQueryParameter("r") == "1",
            email = uri.getQueryParameter("e").orEmpty(),
            phone = uri.getQueryParameter("p").orEmpty(),
        )
    }

    // ===== تحليل الطلب من نص ملصوق =====

    /** رمز الجهاز بالشكل XXXX-XXXX — مجموعات المفتاح خمسة أحرف فلا تتطابق معه */
    private val DEVICE_CODE_RE = Regex("\\b[A-Z0-9]{4}-[A-Z0-9]{4}\\b")

    fun isDeviceCode(s: String): Boolean = DEVICE_CODE_RE.matches(s.trim().uppercase())

    /** يستخرج رمز الجهاز من أي نص — رسالة كاملة أو رابط أو الرمز وحده */
    fun extractDeviceCode(text: String): String? =
        DEVICE_CODE_RE.find(text.uppercase())?.value

    /**
     * يحلّل أي نص ملصوق يحوي طلب ترخيص — رسالة واتساب كاملة، رابطاً، جزءاً
     * مقصوصاً منه، أو الرمز وحده — ويستخرج الجهاز والبريد والاسم والجوال.
     *
     * واتساب لا يجعل روابط cardmanager-admin:// قابلة للضغط، فيلصق الأدمن
     * الرسالة نصاً — وهذه الدالة تفهمها مهما كان شكلها أو ترميزها.
     */
    fun parseRequestText(text: String): Request? {
        val t = text.trim()
        if (t.isEmpty()) return null

        // 1) رابط كامل داخل النص — Uri يتكفل بفك ترميز المعاملات
        Regex("$SCHEME_ADMIN://\\S+").find(t)?.let { m ->
            runCatching { parseRequest(Uri.parse(m.value)) }.getOrNull()?.let { return it }
        }

        // 2) معاملات مبعثرة (نص منسوخ جزئياً من الرابط) — تُفك يدوياً
        fun param(k: String): String {
            val raw = Regex("(?:^|[?&])$k=([^&\\s]+)").find(t)?.groupValues?.get(1) ?: return ""
            return runCatching { java.net.URLDecoder.decode(raw, "UTF-8") }.getOrDefault(raw)
        }

        val device = extractDeviceCode(param("d")) ?: extractDeviceCode(t) ?: return null
        val email = param("e").ifBlank {
            Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}").find(t)?.value.orEmpty()
        }
        val phone = param("p").ifBlank {
            Regex("(?<!\\d)\\d{9,15}(?!\\d)").find(t)?.value.orEmpty()
        }
        val name = param("n").ifBlank {
            Regex("الاسم[:：]\\s*(.+)").find(t)?.groupValues?.get(1)?.trim().orEmpty()
        }
        return Request(
            deviceCode = device,
            name = name,
            renewal = param("r") == "1" || t.contains("تجديد"),
            email = email,
            phone = phone,
        )
    }

    /** رقم واتساب مزوّد الخدمة (اليمن +967) — يُفتح إليه طلب الترخيص مباشرة */
    const val WHATSAPP_NUMBER = "967776831921"

    /** الرسالة التي يرسلها المشترك عبر واتساب */
    fun requestMessage(
        deviceCode: String,
        name: String,
        renewal: Boolean,
        email: String = "",
        phone: String = "",
    ): String = buildString {
        appendLine(if (renewal) "طلب تجديد اشتراك — مدير الكروت" else "طلب ترخيص — مدير الكروت")
        if (name.isNotBlank()) appendLine("الاسم: $name")
        if (email.isNotBlank()) appendLine("البريد: $email")
        if (phone.isNotBlank()) appendLine("الجوال: $phone")
        appendLine("رمز الجهاز: $deviceCode")
        appendLine()
        appendLine("اضغط الرابط لفتحه في لوحة التراخيص:")
        append(buildRequest(deviceCode, name, renewal, email, phone))
    }

    /** رابط واتساب مباشر لمزوّد الخدمة مع الرسالة جاهزة */
    fun whatsappLink(message: String): String =
        "https://wa.me/$WHATSAPP_NUMBER?text=" + Uri.encode(message)

    // ===== التفعيل (من الأدمن إلى المشترك) =====

    fun buildActivation(key: String): String =
        Uri.Builder()
            .scheme(SCHEME_APP)
            .authority("activate")
            .appendQueryParameter("k", key)
            .build()
            .toString()

    fun parseActivation(uri: Uri?): String? {
        if (uri == null || uri.scheme != SCHEME_APP) return null
        return uri.getQueryParameter("k")?.takeIf { it.isNotBlank() }
    }

    /**
     * يستخرج مفتاح التفعيل من أي نص ملصوق — رابط تفعيل، رسالة واتساب كاملة،
     * أو المفتاح وحده — حتى لا تفسده الكلمات المحيطة به عند التفعيل.
     */
    fun extractKey(text: String): String? {
        Regex("$SCHEME_APP://\\S+").find(text)?.let { m ->
            runCatching { parseActivation(Uri.parse(m.value)) }.getOrNull()?.let { return it }
        }
        // المفتاح: سلسلة طويلة من مجموعات Base32 مفصولة بشرطات (~24 مجموعة)
        return Regex("(?:[A-Z0-9]{2,5}-){10,}[A-Z0-9]{1,5}").find(text.uppercase())?.value
    }

    /** الرسالة التي يرسلها الأدمن للمشترك */
    fun activationMessage(key: String, planLabel: String, expiryLabel: String): String = buildString {
        appendLine("مفتاح تفعيل مدير الكروت")
        appendLine("المدة: $planLabel")
        if (expiryLabel.isNotBlank()) appendLine("ينتهي في: $expiryLabel")
        appendLine()
        appendLine("اضغط الرابط للتفعيل مباشرة:")
        appendLine(buildActivation(key))
        appendLine()
        appendLine("أو انسخ المفتاح والصقه في التطبيق:")
        append(key)
    }
}
