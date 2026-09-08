package com.binwaps.cardmanager.license

import android.content.Context
import java.net.URI

/** The endpoint is configurable; the provider verification key is compiled into both apps. */
object LicenseConnection {
    private lateinit var context: Context
    fun init(ctx: Context) { context = ctx.applicationContext }
    val url: String get() = if (::context.isInitialized)
        context.getSharedPreferences("license_connection", 0).getString("url", "").orEmpty() else ""

    fun save(value: String): String? {
        val clean = value.trim().trimEnd('/')
        val uri = runCatching { URI(clean) }.getOrNull()
        if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank() ||
            uri.userInfo != null || uri.rawQuery != null || uri.rawFragment != null) {
            return "أدخل عنوان HTTPS الذي أعطاك إياه مزوّد الخدمة"
        }
        context.getSharedPreferences("license_connection", 0).edit().putString("url", clean).apply()
        return null
    }
}
