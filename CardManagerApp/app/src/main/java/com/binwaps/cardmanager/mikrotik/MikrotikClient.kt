package com.binwaps.cardmanager.mikrotik

import com.binwaps.cardmanager.model.ActiveUser
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.HotspotProfile
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.model.RouterStatus
import com.binwaps.cardmanager.model.SessionEntry
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.legrange.mikrotik.ApiConnection

/**
 * عميل RouterOS API — يدعم الهوتسبوت واليوزر منجر (v6 و v7)،
 * الجلسات النشطة وسجلها، الباقات، والكروت المنتهية.
 */
object MikrotikClient {

    // ===== الاتصال =====

    private fun open(r: RouterProfile): ApiConnection {
        val timeoutMs = (r.timeoutSec.coerceIn(3, 120)) * 1000
        val factory = if (r.useSsl) trustAllSocketFactory() else javax.net.SocketFactory.getDefault()
        val con = ApiConnection.connect(factory, r.host.trim(), r.port, timeoutMs)
        con.login(r.username, r.password)
        return con
    }

    /**
     * راوترات مايكروتك تستخدم شهادة موقّعة ذاتياً افتراضياً، فلا يمكن التحقق منها
     * عبر سلسلة ثقة عامة. نقبلها لأن الاتصال موجّه لعنوان يحدده المستخدم بنفسه.
     */
    private fun trustAllSocketFactory(): javax.net.SocketFactory {
        val trustAll = arrayOf<javax.net.ssl.TrustManager>(object : javax.net.ssl.X509TrustManager {
            override fun checkClientTrusted(chain: Array<java.security.cert.X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<java.security.cert.X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = arrayOf()
        })
        val ctx = javax.net.ssl.SSLContext.getInstance("TLS")
        ctx.init(null, trustAll, java.security.SecureRandom())
        return ctx.socketFactory
    }

    private inline fun <T> ApiConnection.useCon(block: (ApiConnection) -> T): T {
        try {
            return block(this)
        } finally {
            runCatching { close() }
        }
    }

    /** ينفّذ عملية على الراوتر ويحوّل الأخطاء إلى رسائل عربية مفهومة */
    private suspend fun <T> onRouter(r: RouterProfile?, block: (ApiConnection) -> T): Result<T> =
        withContext(Dispatchers.IO) {
            if (r == null) return@withContext Result.failure(Exception("لا يوجد راوتر محفوظ — اتصل أولاً"))
            runCatching { open(r).useCon(block) }.recoverCatching { throw Exception(arabicError(it), it) }
        }

    private fun arabicError(t: Throwable): String {
        val raw = (t.message ?: t.toString())
        return when {
            raw.contains("timed out", true) || raw.contains("timeout", true) ->
                "انتهت مهلة الاتصال — تأكد من العنوان والمنفذ، أو زد المهلة من شاشة الاتصال"
            raw.contains("ECONNREFUSED", true) || raw.contains("refused", true) ->
                "الراوتر رفض الاتصال — تأكد أن خدمة API مفعّلة: IP → Services → api"
            raw.contains("UnknownHost", true) || raw.contains("Unable to resolve", true) ->
                "تعذّر العثور على العنوان — تحقق من الدومين أو الـ IP"
            raw.contains("cannot log in", true) || raw.contains("invalid user", true) ||
                raw.contains("password", true) ->
                "اسم المستخدم أو كلمة المرور غير صحيحة"
            raw.contains("not enough permissions", true) || raw.contains("policy", true) ->
                "هذا المستخدم لا يملك صلاحية — أعطه صلاحيات api و read و write على الراوتر"
            raw.contains("no such command", true) || raw.contains("unknown command", true) ->
                "هذا الأمر غير موجود على الراوتر — قد تكون حزمة اليوزر منجر غير مثبّتة"
            raw.contains("SSL", true) || raw.contains("handshake", true) ->
                "فشل الاتصال المشفّر — جرّب إيقاف api-ssl أو تأكد من المنفذ 8729"
            else -> raw
        }
    }

    /** ينفّذ أمراً ويعيد قائمة فارغة بدل الانهيار إن لم يكن الأمر مدعوماً */
    private fun ApiConnection.tryList(vararg commands: String): List<Map<String, String>> {
        for (cmd in commands) {
            val result = runCatching { execute(cmd) }.getOrNull()
            if (result != null) return result
        }
        return emptyList()
    }

    // ===== الحالة =====

    suspend fun connect(r: RouterProfile): Result<RouterStatus> = onRouter(r) { con ->
        val res = con.execute("/system/resource/print").firstOrNull() ?: emptyMap()
        val identity = runCatching { con.execute("/system/identity/print").firstOrNull()?.get("name") }
            .getOrNull().orEmpty()
        val active = con.tryList("/ip/hotspot/active/print").size

        val hotspotRows = con.tryList("/ip/hotspot/user/print")
            .filter { (it["name"] ?: "") != "default-trial" }
        val used = hotspotRows.count { classify(it) != CardStatus.UNUSED }
        val umRows = con.tryList("/user-manager/user/print", "/tool/user-manager/user/print")

        RouterStatus(
            identity = identity,
            version = res["version"].orEmpty(),
            board = res["board-name"].orEmpty(),
            uptime = res["uptime"].orEmpty(),
            cpuLoad = res["cpu-load"].orEmpty(),
            freeMemory = res["free-memory"].orEmpty(),
            totalMemory = res["total-memory"].orEmpty(),
            activeUsers = active,
            hotspotUsers = hotspotRows.size,
            userManagerUsers = umRows.size,
            usedUsers = used,
        )
    }

    // ===== تصنيف حالة الكرت =====

    /**
     * الكرت "غير مستهلك" إذا لم يُستخدم إطلاقاً.
     * يصبح "منتهياً" إذا استهلك كامل الوقت أو كامل الباقة المسموحة.
     */
    fun classify(row: Map<String, String>): CardStatus {
        if (row["disabled"] == "true") return CardStatus.DISABLED

        val limitUptime = parseUptime(row["limit-uptime"].orEmpty())
        val uptime = parseUptime(row["uptime"].orEmpty())
        if (limitUptime > 0 && uptime >= limitUptime) return CardStatus.EXPIRED

        val limitBytes = row["limit-bytes-total"]?.toLongOrNull() ?: 0
        val usedBytes = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0)
        if (limitBytes > 0 && usedBytes >= limitBytes) return CardStatus.EXPIRED

        return if (uptime > 0 || usedBytes > 0) CardStatus.IN_USE else CardStatus.UNUSED
    }

    // ===== الكروت =====

    /** كروت الهوتسبوت مع حالتها */
    suspend fun fetchHotspotUsers(r: RouterProfile?): Result<List<UserEntry>> = onRouter(r) { con ->
        con.execute("/ip/hotspot/user/print").mapNotNull { row ->
            val name = row["name"] ?: return@mapNotNull null
            if (name == "default-trial") return@mapNotNull null
            UserEntry(
                username = name,
                password = row["password"].orEmpty(),
                profile = row["profile"].orEmpty(),
                validity = row["limit-uptime"].orEmpty(),
                comment = row["comment"].orEmpty(),
                routerId = row[".id"].orEmpty(),
                source = CardSource.HOTSPOT,
                status = classify(row),
                uptime = row["uptime"].orEmpty(),
                bytesUsed = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0),
                disabled = row["disabled"] == "true",
            )
        }
    }

    /** مستخدمو اليوزر منجر — v7 ثم v6 */
    suspend fun fetchUserManagerUsers(r: RouterProfile?): Result<List<UserEntry>> = onRouter(r) { con ->
        val rows = con.tryList("/user-manager/user/print", "/tool/user-manager/user/print")
        if (rows.isEmpty()) {
            throw Exception("لم يُعثر على مستخدمين في اليوزر منجر — تأكد أن الحزمة مثبّتة ومفعّلة على الراوتر")
        }
        rows.mapNotNull { row ->
            val name = row["name"] ?: row["username"] ?: return@mapNotNull null
            UserEntry(
                username = name,
                password = row["password"].orEmpty(),
                profile = row["group"] ?: row["actual-profile"] ?: row["profile"].orEmpty(),
                comment = row["comment"].orEmpty(),
                routerId = row[".id"].orEmpty(),
                source = CardSource.USER_MANAGER,
                status = if (row["disabled"] == "true") CardStatus.DISABLED else CardStatus.UNKNOWN,
                disabled = row["disabled"] == "true",
            )
        }
    }

    /** كل الكروت من المصدرين معاً */
    suspend fun fetchAllCards(r: RouterProfile?): Result<List<UserEntry>> = onRouter(r) { con ->
        val hotspot = con.tryList("/ip/hotspot/user/print")
            .filter { (it["name"] ?: "") != "default-trial" }
            .mapNotNull { row ->
                val name = row["name"] ?: return@mapNotNull null
                UserEntry(
                    username = name,
                    password = row["password"].orEmpty(),
                    profile = row["profile"].orEmpty(),
                    validity = row["limit-uptime"].orEmpty(),
                    comment = row["comment"].orEmpty(),
                    routerId = row[".id"].orEmpty(),
                    source = CardSource.HOTSPOT,
                    status = classify(row),
                    uptime = row["uptime"].orEmpty(),
                    bytesUsed = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0),
                    disabled = row["disabled"] == "true",
                )
            }
        val um = con.tryList("/user-manager/user/print", "/tool/user-manager/user/print")
            .mapNotNull { row ->
                val name = row["name"] ?: row["username"] ?: return@mapNotNull null
                UserEntry(
                    username = name,
                    password = row["password"].orEmpty(),
                    profile = row["group"] ?: row["actual-profile"] ?: row["profile"].orEmpty(),
                    comment = row["comment"].orEmpty(),
                    routerId = row[".id"].orEmpty(),
                    source = CardSource.USER_MANAGER,
                    status = if (row["disabled"] == "true") CardStatus.DISABLED else CardStatus.UNKNOWN,
                    disabled = row["disabled"] == "true",
                )
            }
        hotspot + um
    }

    // ===== الجلسات =====

    /** الجلسات النشطة الآن */
    suspend fun fetchActiveSessions(r: RouterProfile?): Result<List<SessionEntry>> = onRouter(r) { con ->
        con.execute("/ip/hotspot/active/print").map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["user"].orEmpty(),
                address = row["address"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                uptime = row["uptime"].orEmpty(),
                bytesIn = row["bytes-in"]?.toLongOrNull() ?: 0,
                bytesOut = row["bytes-out"]?.toLongOrNull() ?: 0,
                startedAt = row["login-by"].orEmpty(),
                active = true,
            )
        }
    }

    /** سجل الجلسات السابقة — من اليوزر منجر إن وُجد، وإلا من كوكيز الهوتسبوت */
    suspend fun fetchSessionHistory(r: RouterProfile?): Result<List<SessionEntry>> = onRouter(r) { con ->
        val umSessions = con.tryList("/user-manager/session/print", "/tool/user-manager/session/print")
        if (umSessions.isNotEmpty()) {
            return@onRouter umSessions.map { row ->
                SessionEntry(
                    id = row[".id"].orEmpty(),
                    username = row["user"] ?: row["username"].orEmpty(),
                    address = row["nas-ip-address"] ?: row["address"].orEmpty(),
                    macAddress = row["calling-station-id"] ?: row["mac-address"].orEmpty(),
                    uptime = row["session-time"] ?: row["uptime"].orEmpty(),
                    bytesIn = row["download"]?.toLongOrNull() ?: row["bytes-in"]?.toLongOrNull() ?: 0,
                    bytesOut = row["upload"]?.toLongOrNull() ?: row["bytes-out"]?.toLongOrNull() ?: 0,
                    startedAt = row["started"] ?: row["from-time"].orEmpty(),
                    endedAt = row["ended"] ?: row["till-time"].orEmpty(),
                    active = false,
                )
            }
        }
        // بديل: الكوكيز تحفظ آخر دخول لكل مستخدم
        con.tryList("/ip/hotspot/cookie/print").map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["user"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                uptime = row["expires-in"].orEmpty(),
                active = false,
            )
        }
    }

    suspend fun disconnectActive(r: RouterProfile?, id: String): Result<Unit> = onRouter(r) { con ->
        con.execute("/ip/hotspot/active/remove =.id=$id")
        Unit
    }

    // ===== الباقات =====

    /** باقات الهوتسبوت واليوزر منجر معاً، مع عدد الكروت في كل باقة */
    suspend fun fetchProfiles(r: RouterProfile?): Result<List<HotspotProfile>> = onRouter(r) { con ->
        val hotspotUsers = con.tryList("/ip/hotspot/user/print")
        val umUsers = con.tryList("/user-manager/user/print", "/tool/user-manager/user/print")

        val hotspotProfiles = con.tryList("/ip/hotspot/user/profile/print").map { row ->
            val name = row["name"].orEmpty()
            HotspotProfile(
                id = row[".id"].orEmpty(),
                name = name,
                rateLimit = row["rate-limit"].orEmpty(),
                sessionTimeout = row["session-timeout"].orEmpty(),
                sharedUsers = row["shared-users"] ?: "1",
                source = CardSource.HOTSPOT,
                userCount = hotspotUsers.count { it["profile"] == name },
            )
        }

        // اليوزر منجر v7 يسميها profile، و v6 يسميها profile أيضاً لكن بمسار مختلف
        val umProfiles = con.tryList("/user-manager/profile/print", "/tool/user-manager/profile/print")
            .map { row ->
                val name = row["name"].orEmpty()
                HotspotProfile(
                    id = row[".id"].orEmpty(),
                    name = name,
                    rateLimit = row["rate-limit"] ?: row["rate-limit-rx"].orEmpty(),
                    sessionTimeout = row["validity"] ?: row["session-timeout"].orEmpty(),
                    sharedUsers = row["shared-users"] ?: "1",
                    source = CardSource.USER_MANAGER,
                    userCount = umUsers.count { (it["group"] ?: it["actual-profile"] ?: it["profile"]) == name },
                )
            }

        val all = hotspotProfiles + umProfiles
        if (all.isEmpty()) throw Exception("لا توجد باقات على الراوتر — أنشئ باقة من الهوتسبوت أو اليوزر منجر أولاً")
        all
    }

    suspend fun createProfile(r: RouterProfile?, p: HotspotProfile): Result<Unit> = onRouter(r) { con ->
        val cmd = buildString {
            append("/ip/hotspot/user/profile/add =name=${p.name}")
            if (p.rateLimit.isNotBlank()) append(" =rate-limit=${p.rateLimit}")
            if (p.sessionTimeout.isNotBlank()) append(" =session-timeout=${p.sessionTimeout}")
            if (p.sharedUsers.isNotBlank()) append(" =shared-users=${p.sharedUsers}")
        }
        con.execute(cmd)
        Unit
    }

    // ===== الرفع والحذف =====

    suspend fun createHotspotUsers(
        r: RouterProfile?,
        users: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> = onRouter(r) { con ->
        var ok = 0
        users.forEachIndexed { i, u ->
            val cmd = buildString {
                append("/ip/hotspot/user/add =name=${u.username}")
                if (u.password.isNotBlank()) append(" =password=${u.password}")
                if (u.profile.isNotBlank()) append(" =profile=${u.profile}")
                if (u.validity.isNotBlank()) append(" =limit-uptime=${u.validity}")
                if (u.comment.isNotBlank()) append(" =comment=${u.comment}")
            }
            runCatching { con.execute(cmd) }.onSuccess { ok++ }
            onProgress(i + 1, users.size)
        }
        ok
    }

    /** حذف الكروت المنتهية أو المعطّلة من الهوتسبوت */
    suspend fun removeExpiredUsers(r: RouterProfile?): Result<Int> = onRouter(r) { con ->
        var removed = 0
        for (row in con.execute("/ip/hotspot/user/print")) {
            val id = row[".id"] ?: continue
            if ((row["name"] ?: "") == "default-trial") continue
            if (classify(row) == CardStatus.EXPIRED) {
                runCatching { con.execute("/ip/hotspot/user/remove =.id=$id") }.onSuccess { removed++ }
            }
        }
        removed
    }

    /** حذف كرت واحد من الراوتر */
    suspend fun removeUser(r: RouterProfile?, user: UserEntry): Result<Unit> = onRouter(r) { con ->
        if (user.routerId.isBlank()) throw Exception("هذا الكرت غير موجود على الراوتر")
        val path = if (user.source == CardSource.USER_MANAGER) {
            if (runCatching { con.execute("/user-manager/user/print .proplist=.id") }.isSuccess)
                "/user-manager/user/remove" else "/tool/user-manager/user/remove"
        } else "/ip/hotspot/user/remove"
        con.execute("$path =.id=${user.routerId}")
        Unit
    }

    /** تحويل صيغة مايكروتك للوقت (1w2d3h4m5s) إلى ثوانٍ */
    fun parseUptime(v: String): Long {
        if (v.isBlank()) return 0
        val re = Regex("(\\d+)([wdhms])")
        var total = 0L
        for (m in re.findAll(v)) {
            val n = m.groupValues[1].toLongOrNull() ?: 0
            total += when (m.groupValues[2]) {
                "w" -> n * 604800
                "d" -> n * 86400
                "h" -> n * 3600
                "m" -> n * 60
                else -> n
            }
        }
        // صيغة 00:15:32
        if (total == 0L && v.contains(":")) {
            val parts = v.split(":").mapNotNull { it.toLongOrNull() }
            if (parts.size == 3) total = parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return total
    }

    /** جلب المستخدمين المتصلين بصيغة ActiveUser (للوحة التحكم) */
    suspend fun fetchActiveUsers(r: RouterProfile?): Result<List<ActiveUser>> =
        fetchActiveSessions(r).map { list ->
            list.map {
                ActiveUser(
                    id = it.id, username = it.username, address = it.address,
                    macAddress = it.macAddress, uptime = it.uptime,
                    bytesIn = it.bytesIn, bytesOut = it.bytesOut,
                )
            }
        }
}
