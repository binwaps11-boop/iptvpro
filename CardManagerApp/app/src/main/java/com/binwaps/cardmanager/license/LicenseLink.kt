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

    data class Request(val deviceCode: String, val name: String, val renewal: Boolean)

    fun buildRequest(deviceCode: String, name: String, renewal: Boolean = false): String =
        Uri.Builder()
            .scheme(SCHEME_ADMIN)
            .authority("request")
            .appendQueryParameter("d", deviceCode)
            .apply { if (name.isNotBlank()) appendQueryParameter("n", name) }
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
        append(buildRequest(deviceCode, name, renewal))
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
