package com.binwaps.cardmanager.mikrotik

import com.binwaps.cardmanager.model.AppSettings
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.legrange.mikrotik.ApiConnection

/**
 * عميل RouterOS API (منفذ 8728) لجلب وإنشاء مستخدمي الهوتسبوت واليوزر منجر.
 */
object MikrotikClient {

    private fun open(s: AppSettings): ApiConnection {
        val con = ApiConnection.connect(
            javax.net.SocketFactory.getDefault(), s.mikrotikHost, s.mikrotikPort, 8000
        )
        con.login(s.mikrotikUser, s.mikrotikPassword)
        return con
    }

    /** جلب مستخدمي الهوتسبوت */
    suspend fun fetchHotspotUsers(s: AppSettings): Result<List<UserEntry>> = withContext(Dispatchers.IO) {
        runCatching {
            open(s).use { con ->
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
    suspend fun fetchUserManagerUsers(s: AppSettings): Result<List<UserEntry>> = withContext(Dispatchers.IO) {
        runCatching {
            open(s).use { con ->
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
    suspend fun createHotspotUsers(s: AppSettings, users: List<UserEntry>): Result<Int> = withContext(Dispatchers.IO) {
        runCatching {
            open(s).use { con ->
                var ok = 0
                for (u in users) {
                    val cmd = buildString {
                        append("/ip/hotspot/user/add =name=${u.username}")
                        if (u.password.isNotBlank()) append(" =password=${u.password}")
                        if (u.profile.isNotBlank()) append(" =profile=${u.profile}")
                        if (u.validity.isNotBlank()) append(" =limit-uptime=${u.validity}")
                        if (u.comment.isNotBlank()) append(" =comment=${u.comment}")
                    }
                    runCatching { con.execute(cmd) }.onSuccess { ok++ }
                }
                ok
            }
        }
    }

    private inline fun <T> ApiConnection.use(block: (ApiConnection) -> T): T {
        try {
            return block(this)
        } finally {
            runCatching { close() }
        }
    }
}
