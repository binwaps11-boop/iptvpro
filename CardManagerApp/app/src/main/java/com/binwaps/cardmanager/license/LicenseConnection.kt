package com.binwaps.cardmanager.license

import android.content.Context

/**
 * نقطة الاتصال الرسمية المشتركة بين تطبيق المشترك ولوحة التراخيص.
 * لا نسمح بتغييرها من الواجهة لأن إدخال IP أو نطاق آخر يسبب خطأ Hostname.
 */
object LicenseConnection {
    /** Public endpoint shared by the subscriber and admin applications. */
    const val DEFAULT_URL = "https://iptvpro.lol/license-api"
    private lateinit var context: Context
    fun init(ctx: Context) {
        context = ctx.applicationContext
        // إزالة أي عنوان IP/HTTPS قديم من الإصدارات السابقة حتى لا يعود الخطأ.
        context.getSharedPreferences("license_connection", 0).edit().remove("url").apply()
    }

    val url: String get() = DEFAULT_URL
}
