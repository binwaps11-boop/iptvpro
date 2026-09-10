package com.binwaps.cardmanager.util

import android.content.Context
import android.net.ConnectivityManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket

/**
 * اكتشاف الراوتر تلقائياً — الحل الجذري لأكثر أسباب فشل الاتصال شيوعاً:
 * كتابة عنوان ليس على شبكة الجوال أصلاً (مثل 192.168.88.1 بينما شبكة
 * الجوال 10.x.x.x). بوابة شبكة الجوال هي الراوتر نفسه من منظور الجوال،
 * فنقرأها من النظام ونفحص منافذ API الشائعة بالتوازي ونملأ الصحيح بضغطة.
 */
object RouterDiscovery {

    data class Found(val host: String, val port: Int)

    data class Result(
        val phoneIp: String?,
        val gateway: String?,
        val found: List<Found>,
    )

    /** عنوان الجوال IPv4 على الشبكة النشطة */
    fun phoneIp(context: Context): String? = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.getLinkProperties(cm.activeNetwork)?.linkAddresses
            ?.firstOrNull { it.address is Inet4Address && !it.address.isLoopbackAddress }
            ?.address?.hostAddress
    }.getOrNull()

    /** بوابة الشبكة النشطة — عنوان الراوتر من منظور الجوال في معظم الشبكات */
    fun gatewayIp(context: Context): String? = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.getLinkProperties(cm.activeNetwork)?.routes
            // المسار الافتراضي (destination 0.0.0.0/0) وله بوابة IPv4
            ?.firstOrNull { it.gateway is Inet4Address && it.destination.prefixLength == 0 }
            ?.gateway?.hostAddress
    }.getOrNull() ?: runCatching {
        // احتياط للأجهزة التي لا تعيد المسارات: معلومات DHCP القديمة للواي فاي
        @Suppress("DEPRECATION")
        val wm = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
        @Suppress("DEPRECATION")
        val gw = wm.dhcpInfo?.gateway ?: 0
        if (gw == 0) null
        else "%d.%d.%d.%d".format(gw and 0xff, (gw shr 8) and 0xff, (gw shr 16) and 0xff, (gw shr 24) and 0xff)
    }.getOrNull()

    /**
     * هل يبدو العنوان المكتوب على شبكة مختلفة عن شبكة الجوال؟
     * مقارنة استرشادية بأول خانتين (10.70 مقابل 192.168 مثلاً).
     * الدومينات (غير الأرقام) لا يُحكم عليها.
     */
    fun looksDifferentNetwork(phoneIp: String?, host: String): Boolean {
        if (phoneIp == null) return false
        val a = phoneIp.split(".")
        val b = host.trim().split(".")
        if (a.size < 2 || b.size < 2) return false
        if (b[0].toIntOrNull() == null || b[1].toIntOrNull() == null) return false
        return a[0] != b[0] || a[1] != b[1]
    }

    private fun portOpen(host: String, port: Int, timeoutMs: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs); true }
    }.getOrDefault(false)

    /**
     * يفحص بالتوازي منافذ API الشائعة (المكتوب، 8728، 8729) على بوابة الشبكة
     * والعنوان المكتوب معاً، ويعيد المفتوح منها — البوابة أولاً لأنها الراوتر فعلاً.
     */
    suspend fun discover(context: Context, typedHost: String, typedPort: Int?): Result =
        withContext(Dispatchers.IO) {
            val gw = gatewayIp(context)
            val me = phoneIp(context)
            val hosts = listOfNotNull(
                gw,
                typedHost.trim().takeIf { it.isNotBlank() && it != gw },
            )
            val ports = listOfNotNull(typedPort, 8728, 8729).distinct()
            val pairs = hosts.flatMap { h -> ports.map { p -> Found(h, p) } }
            val found = coroutineScope {
                pairs.map { f -> async { if (portOpen(f.host, f.port, 1500)) f else null } }
                    .awaitAll()
                    .filterNotNull()
            }
            Result(phoneIp = me, gateway = gw, found = found)
        }
}
