package com.binwaps.cardmanager.mikrotik

import com.binwaps.cardmanager.model.ActiveUser
import com.binwaps.cardmanager.model.HotspotProfile
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.model.RouterStatus
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.legrange.mikrotik.ApiConnection

/**
 * عميل RouterOS API (منفذ 8728) — الاتصال، الحالة، الهوتسبوت، اليوزر منجر، والباقات.
 */
object MikrotikClient {

    private fun open(r: RouterProfile): ApiConnection {
        val con = ApiConnection.connect(
            javax.net.SocketFactory.getDefault(), r.host, r.port, 8000
        )
        con.login(r.username, r.password)
        return con
    }

    private inline fun <T> ApiConnection.useCon(block: (ApiConnection) -> T): T {
        try {
            return block(this)
        } finally {
            runCatching { close() }
        }
    }

    /** اختبار الاتصال وقراءة حالة الراوتر */
    suspend fun connect(r: RouterProfile): Result<RouterStatus> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                val res = con.execute("/system/resource/print").firstOrNull() ?: emptyMap()
                val identity = con.execute("/system/identity/print").firstOrNull()?.get("name") ?: ""
                val active = runCatching { con.execute("/ip/hotspot/active/print").size }.getOrDefault(0)
                val hs = runCatching { con.execute("/ip/hotspot/user/print").size }.getOrDefault(0)
                RouterStatus(
                    identity = identity,
                    version = res["version"] ?: "",
                    board = res["board-name"] ?: "",
                    uptime = res["uptime"] ?: "",
                    cpuLoad = res["cpu-load"] ?: "",
                    freeMemory = res["free-memory"] ?: "",
                    totalMemory = res["total-memory"] ?: "",
                    activeUsers = active,
                    hotspotUsers = hs,
                )
            }
        }
    }

    /** المستخدمون المتصلون الآن */
    suspend fun fetchActiveUsers(r: RouterProfile): Result<List<ActiveUser>> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                con.execute("/ip/hotspot/active/print").map { row ->
                    ActiveUser(
                        id = row[".id"] ?: "",
                        username = row["user"] ?: "",
                        address = row["address"] ?: "",
                        macAddress = row["mac-address"] ?: "",
                        uptime = row["uptime"] ?: "",
                        bytesIn = row["bytes-in"]?.toLongOrNull() ?: 0,
                        bytesOut = row["bytes-out"]?.toLongOrNull() ?: 0,
                    )
                }
            }
        }
    }

    /** فصل مستخدم متصل */
    suspend fun disconnectActive(r: RouterProfile, id: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con -> con.execute("/ip/hotspot/active/remove =.id=$id") }
            Unit
        }
    }

    /** باقات الهوتسبوت */
    suspend fun fetchProfiles(r: RouterProfile): Result<List<HotspotProfile>> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                con.execute("/ip/hotspot/user/profile/print").map { row ->
                    HotspotProfile(
                        id = row[".id"] ?: "",
                        name = row["name"] ?: "",
                        rateLimit = row["rate-limit"] ?: "",
                        sessionTimeout = row["session-timeout"] ?: "",
                        sharedUsers = row["shared-users"] ?: "1",
                    )
                }
            }
        }
    }

    /** إنشاء باقة جديدة */
    suspend fun createProfile(r: RouterProfile, p: HotspotProfile): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                val cmd = buildString {
                    append("/ip/hotspot/user/profile/add =name=${p.name}")
                    if (p.rateLimit.isNotBlank()) append(" =rate-limit=${p.rateLimit}")
                    if (p.sessionTimeout.isNotBlank()) append(" =session-timeout=${p.sessionTimeout}")
                    if (p.sharedUsers.isNotBlank()) append(" =shared-users=${p.sharedUsers}")
                }
                con.execute(cmd)
            }
            Unit
        }
    }

    /** جلب مستخدمي الهوتسبوت */
    suspend fun fetchHotspotUsers(r: RouterProfile): Result<List<UserEntry>> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                con.execute("/ip/hotspot/user/print").mapNotNull { row ->
                    val name = row["name"] ?: return@mapNotNull null
                    if (name == "default-trial") return@mapNotNull null
                    UserEntry(
                        username = name,
                        password = row["password"] ?: "",
                        profile = row["profile"] ?: "",
                        validity = row["limit-uptime"] ?: "",
                        comment = row["comment"] ?: "",
                    )
                }
            }
        }
    }

    /** جلب مستخدمي اليوزر منجر — يجرب مسار v7 ثم مسار v6 تلقائياً */
    suspend fun fetchUserManagerUsers(r: RouterProfile): Result<List<UserEntry>> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                val rows = try {
                    con.execute("/user-manager/user/print")
                } catch (e: Exception) {
                    con.execute("/tool/user-manager/user/print")
                }
                rows.mapNotNull { row ->
                    val name = row["name"] ?: row["username"] ?: return@mapNotNull null
                    UserEntry(
                        username = name,
                        password = row["password"] ?: "",
                        profile = row["group"] ?: row["actual-profile"] ?: "",
                        comment = row["comment"] ?: "",
                    )
                }
            }
        }
    }

    /** رفع دفعة مستخدمين إلى الهوتسبوت */
    suspend fun createHotspotUsers(
        r: RouterProfile,
        users: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
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
        }
    }

    /** حذف مستخدمي الهوتسبوت المنتهية صلاحيتهم (الذين استهلكوا الوقت بالكامل) */
    suspend fun removeExpiredUsers(r: RouterProfile): Result<Int> = withContext(Dispatchers.IO) {
        runCatching {
            open(r).useCon { con ->
                val rows = con.execute("/ip/hotspot/user/print")
                var removed = 0
                for (row in rows) {
                    val limit = row["limit-uptime"] ?: continue
                    val used = row["uptime"] ?: continue
                    val id = row[".id"] ?: continue
                    if (limit.isNotBlank() && used.isNotBlank() && parseUptime(used) >= parseUptime(limit) && parseUptime(limit) > 0) {
                        runCatching { con.execute("/ip/hotspot/user/remove =.id=$id") }.onSuccess { removed++ }
                    }
                }
                removed
            }
        }
    }

    /** تحويل صيغة مايكروتك للوقت (1d2h30m) إلى ثوانٍ */
    private fun parseUptime(v: String): Long {
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
        return total
    }
}
