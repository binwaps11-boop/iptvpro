package com.binwaps.cardmanager.mikrotik

import com.binwaps.cardmanager.model.ActiveUser
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.HotspotProfile
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.model.RouterStatus
import com.binwaps.cardmanager.model.SessionEntry
import com.binwaps.cardmanager.model.UploadTarget
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
    internal suspend fun <T> onRouter(r: RouterProfile?, block: (ApiConnection) -> T): Result<T> =
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

    /**
     * يلفّ القيمة بعلامتي تنصيص — محلّل المكتبة يقطع القيمة عند المسافة أو
     * الرموز (= ! < > ،) إن لم تكن مقتبسة، فباقة اسمها "شهري 10 جيجا" كانت
     * تتحول إلى ثلاث كلمات يرفضها الراوتر. القيمة الفارغة تخرج "" فتُقبل.
     */
    internal fun q(v: String): String {
        val clean = v.replace('\n', ' ').replace('\r', ' ')
        return when {
            !clean.contains('"') -> "\"$clean\""
            !clean.contains('\'') -> "'$clean'"
            // لا يمكن تمثيل قيمة فيها النوعان معاً — نحذف المزدوجة
            else -> "\"${clean.replace("\"", "")}\""
        }
    }

    /** ينفّذ أمراً ويعيد قائمة فارغة بدل الانهيار إن لم يكن الأمر مدعوماً */
    internal fun ApiConnection.tryList(vararg commands: String): List<Map<String, String>> {
        for (cmd in commands) {
            val result = runCatching { execute(cmd) }.getOrNull()
            if (result != null) return result
        }
        return emptyList()
    }

    /**
     * جلب خفيف: يطلب الحقول المطلوبة فقط بدل كل شيء —
     * الفرق هائل مع قوائم بعشرات آلاف المستخدمين على شبكة بطيئة.
     */
    internal fun ApiConnection.printLight(path: String, props: String): List<Map<String, String>> =
        runCatching { execute("$path/print return $props") }
            .getOrElse { execute("$path/print") }

    internal fun ApiConnection.tryPrintLight(props: String, vararg paths: String): List<Map<String, String>> {
        for (p in paths) {
            val r = runCatching { printLight(p, props) }.getOrNull()
            if (r != null) return r
        }
        return emptyList()
    }

    // ===== الحالة =====

    /**
     * اتصال سريع: حالة النظام وعدد المتصلين فقط.
     * لا يمسح قوائم المستخدمين — تلك تُجلب عند الطلب عبر [fetchCardStats].
     */
    suspend fun connect(r: RouterProfile): Result<RouterStatus> = onRouter(r) { con ->
        val res = con.execute("/system/resource/print").firstOrNull() ?: emptyMap()
        val identity = runCatching { con.execute("/system/identity/print").firstOrNull()?.get("name") }
            .getOrNull().orEmpty()
        val active = con.tryPrintLight(".id", "/ip/hotspot/active").size

        RouterStatus(
            identity = identity,
            version = res["version"].orEmpty(),
            board = res["board-name"].orEmpty(),
            uptime = res["uptime"].orEmpty(),
            cpuLoad = res["cpu-load"].orEmpty(),
            freeMemory = res["free-memory"].orEmpty(),
            totalMemory = res["total-memory"].orEmpty(),
            activeUsers = active,
            hotspotUsers = -1,
            userManagerUsers = -1,
            usedUsers = -1,
        )
    }

    /** عدادات الكروت — تُجلب بحقول مختصرة وعند الطلب فقط */
    suspend fun fetchCardStats(r: RouterProfile?): Result<RouterStatus> = onRouter(r) { con ->
        val hotspotRows = con
            .printLight("/ip/hotspot/user", "name,limit-uptime,uptime,limit-bytes-total,bytes-in,bytes-out,disabled,comment")
            .filter { (it["name"] ?: "") != "default-trial" }
        val used = hotspotRows.count { classify(it) != CardStatus.UNUSED }
        val umCount = con.tryPrintLight("name", "/user-manager/user", "/tool/user-manager/user").size
        RouterStatus(
            activeUsers = -1,
            hotspotUsers = hotspotRows.size,
            userManagerUsers = umCount,
            usedUsers = used,
        )
    }

    // ===== تصنيف حالة الكرت =====

    /**
     * تصنيف كرت الهوتسبوت — يدعم اصطلاح MIKHMON المنتشر إضافة للحدود الأصلية:
     *
     * - MIKHMON يضع `limit-uptime=1s` علامةً على الانتهاء
     * - ويكتب في الملاحظة `vc-` أو `up-` للكرت الذي لم يُستخدم بعد
     * - وعند أول دخول يستبدلها بتاريخ الانتهاء "25/Jul/2026 14:30:00"
     */
    fun classify(row: Map<String, String>): CardStatus {
        if (row["disabled"] == "true") return CardStatus.DISABLED

        val limitUptimeRaw = row["limit-uptime"].orEmpty()
        // علامة MIKHMON للكرت المنتهي
        if (limitUptimeRaw.trim() == "1s") return CardStatus.EXPIRED

        val limitUptime = parseUptime(limitUptimeRaw)
        val uptime = parseUptime(row["uptime"].orEmpty())
        if (limitUptime > 0 && uptime >= limitUptime) return CardStatus.EXPIRED

        val limitBytes = row["limit-bytes-total"]?.toLongOrNull() ?: 0
        val usedBytes = (row["bytes-in"]?.toLongOrNull() ?: 0) + (row["bytes-out"]?.toLongOrNull() ?: 0)
        if (limitBytes > 0 && usedBytes >= limitBytes) return CardStatus.EXPIRED

        // ملاحظة MIKHMON: تاريخ انتهاء مكتوب عند أول دخول
        val comment = row["comment"].orEmpty()
        val expiry = parseCommentExpiry(comment)
        if (expiry != null) {
            return if (expiry < System.currentTimeMillis()) CardStatus.EXPIRED else CardStatus.IN_USE
        }
        val untouched = comment.startsWith("vc-") || comment.startsWith("up-")

        return when {
            uptime > 0 || usedBytes > 0 -> CardStatus.IN_USE
            untouched || comment.isBlank() -> CardStatus.UNUSED
            else -> CardStatus.UNUSED
        }
    }

    /** تاريخ انتهاء بصيغة MIKHMON: 25/Jul/2026 14:30:00 */
    fun parseCommentExpiry(comment: String): Long? {
        if (comment.length < 11 || comment[2] != '/' || comment[6] != '/') return null
        return runCatching {
            java.text.SimpleDateFormat("dd/MMM/yyyy HH:mm:ss", java.util.Locale.ENGLISH)
                .parse(comment.trim())?.time
        }.getOrNull()
    }

    // ===== الكروت =====

    private const val HOTSPOT_PROPS =
        ".id,name,password,profile,limit-uptime,uptime,limit-bytes-total,bytes-in,bytes-out,disabled,comment"

    /** كروت الهوتسبوت مع حالتها */
    suspend fun fetchHotspotUsers(r: RouterProfile?): Result<List<UserEntry>> = onRouter(r) { con ->
        con.printLight("/ip/hotspot/user", HOTSPOT_PROPS).mapNotNull { row ->
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

    /**
     * مستخدمو اليوزر منجر — v7 ثم v6.
     *
     * في v7 لا توجد الصلاحية على سجل المستخدم، بل في جدول منفصل
     * `/user-manager/user-profile` يحمل (user, profile, end-time, state).
     * في v6 تكون العدادات على السجل نفسه (uptime-used, download-used…).
     */
    private fun readUserManager(con: ApiConnection): List<UserEntry> {
        val rows = con.tryPrintLight(
            ".id,name,username,customer,password,group,actual-profile,comment,disabled,uptime-used,download-used,upload-used",
            "/user-manager/user", "/tool/user-manager/user",
        )
        if (rows.isEmpty()) return emptyList()

        // جدول الصلاحيات — v7 ثم v6
        val userProfiles = con.tryPrintLight(
            "user,profile,end-time,state",
            "/user-manager/user-profile", "/tool/user-manager/user-profile",
        ).associateBy { it["user"].orEmpty() }

        return rows.mapNotNull { row ->
            val name = row["name"] ?: row["username"] ?: return@mapNotNull null
            val up = userProfiles[name]
            val endTime = up?.get("end-time").orEmpty()
            val state = up?.get("state").orEmpty()

            val usedUptime = row["uptime-used"].orEmpty()
            val usedBytes = (row["download-used"]?.toLongOrNull() ?: 0) +
                (row["upload-used"]?.toLongOrNull() ?: 0)

            val status = when {
                row["disabled"] == "true" -> CardStatus.DISABLED
                state.equals("used", true) -> CardStatus.EXPIRED
                endTime.isNotBlank() && endTime != "unlimited" &&
                    parseRouterTime(endTime)?.let { it < System.currentTimeMillis() } == true -> CardStatus.EXPIRED
                state.equals("running", true) -> CardStatus.IN_USE
                usedUptime.isNotBlank() && parseUptime(usedUptime) > 0 -> CardStatus.IN_USE
                usedBytes > 0 -> CardStatus.IN_USE
                up == null || state.equals("waiting", true) -> CardStatus.UNUSED
                else -> CardStatus.UNUSED
            }

            UserEntry(
                username = name,
                password = row["password"].orEmpty(),
                profile = up?.get("profile") ?: row["group"] ?: row["actual-profile"] ?: row["profile"].orEmpty(),
                comment = row["comment"].orEmpty(),
                routerId = row[".id"].orEmpty(),
                source = CardSource.USER_MANAGER,
                status = status,
                uptime = usedUptime,
                bytesUsed = usedBytes,
                disabled = row["disabled"] == "true",
                expiryText = endTime,
            )
        }
    }

    suspend fun fetchUserManagerUsers(r: RouterProfile?): Result<List<UserEntry>> = onRouter(r) { con ->
        val list = readUserManager(con)
        if (list.isEmpty()) {
            throw Exception("لم يُعثر على مستخدمين في اليوزر منجر — تأكد أن الحزمة مثبّتة ومفعّلة على الراوتر")
        }
        list
    }

    /** تحويل وقت الراوتر (jul/25/2026 14:30:00 أو 2026-07-25 14:30:00) إلى ميلي ثانية */
    fun parseRouterTime(value: String): Long? {
        val v = value.trim()
        val formats = listOf(
            "MMM/dd/yyyy HH:mm:ss", "dd/MMM/yyyy HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss",
        )
        for (f in formats) {
            val t = runCatching {
                java.text.SimpleDateFormat(f, java.util.Locale.ENGLISH).parse(v)?.time
            }.getOrNull()
            if (t != null) return t
        }
        return null
    }

    /** كل الكروت من المصدرين معاً */
    suspend fun fetchAllCards(r: RouterProfile?): Result<List<UserEntry>> = onRouter(r) { con ->
        // فشل الهوتسبوت خطأ حقيقي يظهر للمستخدم — كان يتحول إلى "0 كرت" بنجاح زائف
        val hotspot = con.printLight("/ip/hotspot/user", HOTSPOT_PROPS)
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
                    limitUptime = row["limit-uptime"].orEmpty(),
                    batchTag = row["comment"].orEmpty().takeIf { it.startsWith("vc-") || it.startsWith("b-") }.orEmpty(),
                    limitBytes = row["limit-bytes-total"]?.toLongOrNull() ?: 0,
                    expiryText = parseCommentExpiry(row["comment"].orEmpty())
                        ?.let { java.text.SimpleDateFormat("yyyy/MM/dd HH:mm", java.util.Locale.US).format(java.util.Date(it)) }
                        .orEmpty(),
                )
            }
        val um = runCatching { readUserManager(con) }.getOrDefault(emptyList())
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
        con.execute("/ip/hotspot/active/remove .id=$id")
        Unit
    }

    // ===== الباقات =====

    /** باقات الهوتسبوت واليوزر منجر معاً، مع عدد الكروت في كل باقة */
    suspend fun fetchProfiles(r: RouterProfile?): Result<List<HotspotProfile>> = onRouter(r) { con ->
        // حقل واحد فقط للعدّ — وليس كل بيانات المستخدمين
        val hotspotUsers = runCatching { con.printLight("/ip/hotspot/user", "profile") }
            .getOrDefault(emptyList())
        val umUsers = con.tryPrintLight("group,actual-profile,profile", "/user-manager/user", "/tool/user-manager/user")

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
            append("/ip/hotspot/user/profile/add name=${q(p.name)}")
            if (p.rateLimit.isNotBlank()) append(" rate-limit=${q(p.rateLimit)}")
            if (p.sessionTimeout.isNotBlank()) append(" session-timeout=${q(p.sessionTimeout)}")
            if (p.sharedUsers.isNotBlank()) append(" shared-users=${q(p.sharedUsers)}")
        }
        con.execute(cmd)
        Unit
    }

    // ===== الرفع والحذف =====

    suspend fun createHotspotUsers(
        r: RouterProfile?,
        users: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onCreated: (UserEntry) -> Unit = {},
    ): Result<Int> = onRouter(r) { con ->
        var ok = 0
        var firstError: Throwable? = null
        users.forEachIndexed { i, u ->
            val cmd = buildString {
                append("/ip/hotspot/user/add name=${q(u.username)}")
                if (u.password.isNotBlank()) append(" password=${q(u.password)}")
                if (u.profile.isNotBlank()) append(" profile=${q(u.profile)}")
                if (u.validity.isNotBlank()) append(" limit-uptime=${q(u.validity)}")
                val tag = u.batchTag.ifBlank { u.comment }
                if (tag.isNotBlank()) append(" comment=${q(tag)}")
            }
            runCatching { con.execute(cmd) }
                .onSuccess { ok++; onCreated(u) }
                .onFailure { if (firstError == null) firstError = it }
            onProgress(i + 1, users.size)
        }
        // كانت النسخة القديمة تُرجع نجاحاً حتى لو رفض الراوتر كل الكروت
        if (ok == 0 && users.isNotEmpty()) {
            throw Exception("رفض الراوتر إنشاء الكروت: ${firstError?.message ?: "سبب غير معروف"}")
        }
        ok
    }

    /**
     * إنشاء المستخدمين في اليوزر منجر.
     * v7: يُنشأ المستخدم ثم تُربط به الباقة في جدول user-profile.
     * v6: أمر واحد create-and-activate-profile، وإلا إضافة عادية.
     */
    suspend fun createUserManagerUsers(
        r: RouterProfile?,
        users: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onCreated: (UserEntry) -> Unit = {},
    ): Result<Int> = onRouter(r) { con ->
        val isV7 = runCatching { con.execute("/user-manager/user/print") }.isSuccess
        val base = if (isV7) "/user-manager" else "/tool/user-manager"
        var ok = 0
        var firstError: Throwable? = null
        users.forEachIndexed { i, u ->
            val cmd = buildString {
                append("$base/user/add name=${q(u.username)}")
                if (u.password.isNotBlank()) append(" password=${q(u.password)}")
                if (isV7) {
                    if (u.profile.isNotBlank()) append(" group=${q(u.profile)}")
                } else {
                    append(" customer=admin")
                }
                if (u.comment.isNotBlank()) append(" comment=${q(u.comment)}")
            }
            val added = runCatching { con.execute(cmd) }
                .onFailure { if (firstError == null) firstError = it }
                .isSuccess
            if (added) {
                ok++
                onCreated(u)
                // ربط الباقة بالمستخدم ليكتسب الصلاحية
                if (u.profile.isNotBlank()) {
                    runCatching {
                        if (isV7) {
                            con.execute("$base/user-profile/add user=${q(u.username)} profile=${q(u.profile)}")
                        } else {
                            // v6: التفعيل بأمره الخاص — جدول user-profile غير موجود في v6
                            con.execute(
                                "$base/user/create-and-activate-profile customer=admin " +
                                    "numbers=${q(u.username)} profile=${q(u.profile)}"
                            )
                        }
                    }
                }
            }
            onProgress(i + 1, users.size)
        }
        if (ok == 0 && users.isNotEmpty()) {
            throw Exception(
                "تعذّر إنشاء أي مستخدم: ${firstError?.message ?: "تأكد من تثبيت حزمة اليوزر منجر ومن الصلاحيات"}"
            )
        }
        ok
    }

    /** تفعيل أو تعطيل كرت على الراوتر */
    suspend fun setUserEnabled(r: RouterProfile?, user: UserEntry, enabled: Boolean): Result<Unit> =
        onRouter(r) { con ->
            if (user.routerId.isBlank()) throw Exception("هذا الكرت غير موجود على الراوتر")
            val path = when (user.source) {
                CardSource.USER_MANAGER ->
                    if (runCatching { con.execute("/user-manager/user/print") }.isSuccess)
                        "/user-manager/user" else "/tool/user-manager/user"
                else -> "/ip/hotspot/user"
            }
            con.execute("$path/set .id=${user.routerId} disabled=${!enabled}")
            Unit
        }

    // ===== العمليات الجماعية =====

    /** نتيجة عملية جماعية */
    data class BulkResult(val ok: Int, val failed: Int) {
        val total: Int get() = ok + failed
    }

    private fun ApiConnection.hotspotPath() = "/ip/hotspot/user"

    private fun ApiConnection.userPathFor(source: CardSource): String = when (source) {
        CardSource.USER_MANAGER ->
            if (runCatching { execute("/user-manager/user/print") }.isSuccess) "/user-manager/user"
            else "/tool/user-manager/user"
        else -> "/ip/hotspot/user"
    }

    /** تنفيذ أمر على مجموعة كروت مع تقرير تقدم */
    private fun ApiConnection.bulk(
        cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit,
        command: (UserEntry, String) -> String?,
    ): BulkResult {
        var ok = 0
        var failed = 0
        // نحسب مسار كل مصدر مرة واحدة بدل مرة لكل كرت
        val paths = cards.map { it.source }.distinct().associateWith { userPathFor(it) }
        cards.forEachIndexed { i, u ->
            val path = paths[u.source] ?: "/ip/hotspot/user"
            val cmd = command(u, path)
            if (cmd == null) { failed++ } else {
                runCatching { execute(cmd) }.fold({ ok++ }, { failed++ })
            }
            onProgress(i + 1, cards.size)
        }
        return BulkResult(ok, failed)
    }

    /** تفعيل أو تعطيل مجموعة كروت */
    suspend fun bulkSetEnabled(
        r: RouterProfile?, cards: List<UserEntry>, enabled: Boolean,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        con.bulk(cards, onProgress) { u, path ->
            if (u.routerId.isBlank()) null else "$path/set .id=${u.routerId} disabled=${!enabled}"
        }
    }

    /** حذف مجموعة كروت — يفصل جلساتها النشطة أولاً */
    suspend fun bulkDelete(
        r: RouterProfile?, cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        val names = cards.map { it.username }.toSet()
        runCatching {
            con.printLight("/ip/hotspot/active", ".id,user")
                .filter { it["user"] in names }
                .forEach { row ->
                    row[".id"]?.let { runCatching { con.execute("/ip/hotspot/active/remove .id=$it") } }
                }
        }
        con.bulk(cards, onProgress) { u, path ->
            if (u.routerId.isBlank()) null else "$path/remove .id=${u.routerId}"
        }
    }

    /** تغيير باقة مجموعة كروت */
    suspend fun bulkSetProfile(
        r: RouterProfile?, cards: List<UserEntry>, profile: String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        val (um, hotspot) = cards.partition { it.source == CardSource.USER_MANAGER }
        var ok = 0
        var failed = 0
        var done = 0
        hotspot.forEach { u ->
            if (u.routerId.isBlank()) failed++
            else runCatching {
                con.execute("/ip/hotspot/user/set .id=${u.routerId} profile=${q(profile)}")
            }.fold({ ok++ }, { failed++ })
            onProgress(++done, cards.size)
        }
        if (um.isNotEmpty()) {
            val isV7 = runCatching { con.execute("/user-manager/user/print") }.isSuccess
            // صفوف الصلاحيات الحالية مرة واحدة — إعادة الربط تحتاج حذف القديم.
            // مجرد set group لا يغيّر الباقة الفعلية في v7
            val existing = if (isV7) {
                runCatching { con.printLight("/user-manager/user-profile", ".id,user") }.getOrDefault(emptyList())
            } else emptyList()
            um.forEach { u ->
                runCatching {
                    if (isV7) {
                        con.execute("/user-manager/user/set .id=${u.routerId} group=${q(profile)}")
                        existing.filter { it["user"] == u.username }.forEach { row ->
                            row[".id"]?.let { con.execute("/user-manager/user-profile/remove .id=$it") }
                        }
                        con.execute("/user-manager/user-profile/add user=${q(u.username)} profile=${q(profile)}")
                    } else {
                        con.execute(
                            "/tool/user-manager/user/create-and-activate-profile customer=admin " +
                                "numbers=${q(u.username)} profile=${q(profile)}"
                        )
                    }
                }.fold({ ok++ }, { failed++ })
                onProgress(++done, cards.size)
            }
        }
        BulkResult(ok, failed)
    }

    /** تصفير عدادات مجموعة كروت */
    suspend fun bulkResetCounters(
        r: RouterProfile?, cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        con.bulk(cards.filter { it.source != CardSource.USER_MANAGER }, onProgress) { u, _ ->
            if (u.routerId.isBlank()) null else "/ip/hotspot/user/reset-counters .id=${u.routerId}"
        }
    }

    /**
     * إرجاع الكروت غير مستهلكة: تصفير العدادات، ومسح علامة MIKHMON،
     * وإعادة الصلاحية الأصلية بدل صفر، وحذف الكوكيز حتى لا يعود الجهاز بجلسته القديمة.
     */
    suspend fun bulkResetToUnused(
        r: RouterProfile?, cards: List<UserEntry>, restoreValidity: String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        val names = cards.map { it.username }.toSet()
        runCatching {
            con.printLight("/ip/hotspot/cookie", ".id,user")
                .filter { it["user"] in names }
                .forEach { row -> row[".id"]?.let { runCatching { con.execute("/ip/hotspot/cookie/remove .id=$it") } } }
        }
        con.bulk(cards.filter { it.source != CardSource.USER_MANAGER }, onProgress) { u, _ ->
            if (u.routerId.isBlank()) return@bulk null
            runCatching { con.execute("/ip/hotspot/user/reset-counters .id=${u.routerId}") }
            // نُعيد الصلاحية المطلوبة: المحددة، أو الأصلية للكرت إن لم تكن علامة انتهاء
            val validity = restoreValidity.ifBlank {
                u.limitUptime.takeIf { it.isNotBlank() && it.trim() != "1s" } ?: ""
            }
            buildString {
                append("/ip/hotspot/user/set .id=${u.routerId} comment=\"\"")
                if (validity.isNotBlank()) append(" limit-uptime=${q(validity)}")
            }
        }
    }

    /** تغيير كلمة المرور لمجموعة كروت */
    suspend fun bulkSetPassword(
        r: RouterProfile?, cards: List<UserEntry>, password: (UserEntry) -> String,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        con.bulk(cards, onProgress) { u, path ->
            if (u.routerId.isBlank()) null else "$path/set .id=${u.routerId} password=${q(password(u))}"
        }
    }

    /** تمديد صلاحية مجموعة كروت بإضافة مدة إلى الحد الحالي */
    suspend fun bulkExtendValidity(
        r: RouterProfile?, cards: List<UserEntry>, addSeconds: Long,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<BulkResult> = onRouter(r) { con ->
        con.bulk(cards.filter { it.source != CardSource.USER_MANAGER }, onProgress) { u, _ ->
            if (u.routerId.isBlank()) null else {
                val current = parseUptime(u.limitUptime.takeIf { it.trim() != "1s" }.orEmpty())
                val next = formatUptime(current + addSeconds)
                "/ip/hotspot/user/set .id=${u.routerId} limit-uptime=${q(next)}"
            }
        }
    }

    /** تحويل ثوانٍ إلى صيغة مايكروتك 1d2h3m4s */
    fun formatUptime(seconds: Long): String {
        if (seconds <= 0) return "0s"
        val d = seconds / 86400
        val h = (seconds % 86400) / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return buildString {
            if (d > 0) append("${d}d")
            if (h > 0) append("${h}h")
            if (m > 0) append("${m}m")
            if (s > 0 || isEmpty()) append("${s}s")
        }
    }

    /** تصفير عدادات كرت واحد وإرجاعه غير مستهلك */
    suspend fun resetCard(r: RouterProfile?, user: UserEntry): Result<Unit> =
        bulkResetToUnused(r, listOf(user), "").mapCatching {
            if (it.failed > 0) error("رفض الراوتر إرجاع الكرت")
        }

    /** سجل الجلسات من سجل الراوتر (يحتاج تفعيل تسجيل الهوتسبوت) */
    suspend fun fetchLogHistory(r: RouterProfile?): Result<List<SessionEntry>> = onRouter(r) { con ->
        val rows = runCatching { con.execute("/log/print") }.getOrDefault(emptyList())
        rows.filter { (it["topics"] ?: "").contains("hotspot") }
            .mapNotNull { row ->
                val msg = row["message"] ?: return@mapNotNull null
                // "user1 (10.5.50.2): logged in" / "logged out: session-timeout, 1h2m3s, 45.6MiB, 12.3MiB"
                val name = msg.substringBefore(" (").takeIf { it.isNotBlank() && !it.contains(":") }
                    ?: return@mapNotNull null
                SessionEntry(
                    username = name,
                    address = msg.substringAfter("(", "").substringBefore(")", ""),
                    uptime = Regex("(\\d+[wdhms])+").find(msg.substringAfter("logged out", ""))?.value.orEmpty(),
                    startedAt = row["time"].orEmpty(),
                    endedAt = if (msg.contains("logged out")) row["time"].orEmpty() else "",
                    active = false,
                )
            }
            .reversed()
    }

    /** تفعيل حفظ سجل الهوتسبوت على الراوتر ليعمل سجل الجلسات */
    suspend fun enableHotspotLogging(r: RouterProfile?): Result<Unit> = onRouter(r) { con ->
        con.execute("/system/logging/add topics=hotspot action=disk")
        Unit
    }

    /** الأجهزة المتصلة: عملاء الواي فاي وحجوزات DHCP */
    suspend fun fetchConnectedDevices(r: RouterProfile?): Result<List<SessionEntry>> = onRouter(r) { con ->
        val wireless = con.tryList(
            "/interface/wireless/registration-table/print",
            "/interface/wifi/registration-table/print",
        ).map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["interface"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                uptime = row["uptime"].orEmpty(),
                bytesIn = row["bytes"]?.substringBefore(",")?.toLongOrNull() ?: 0,
                startedAt = row["signal-strength"] ?: row["signal"].orEmpty(),
                active = true,
            )
        }
        val leases = con.tryList("/ip/dhcp-server/lease/print").map { row ->
            SessionEntry(
                id = row[".id"].orEmpty(),
                username = row["host-name"] ?: row["comment"].orEmpty(),
                address = row["address"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                startedAt = row["status"].orEmpty(),
                active = row["status"] == "bound",
            )
        }
        wireless + leases
    }

    /** حذف الكروت المنتهية أو المعطّلة من الهوتسبوت */
    suspend fun removeExpiredUsers(r: RouterProfile?): Result<Int> = onRouter(r) { con ->
        var removed = 0
        for (row in con.execute("/ip/hotspot/user/print")) {
            val id = row[".id"] ?: continue
            if ((row["name"] ?: "") == "default-trial") continue
            if (classify(row) == CardStatus.EXPIRED) {
                runCatching { con.execute("/ip/hotspot/user/remove .id=$id") }.onSuccess { removed++ }
            }
        }
        removed
    }

    /** حذف كرت واحد من الراوتر */
    suspend fun removeUser(r: RouterProfile?, user: UserEntry): Result<Unit> = onRouter(r) { con ->
        if (user.routerId.isBlank()) throw Exception("هذا الكرت غير موجود على الراوتر")
        val path = if (user.source == CardSource.USER_MANAGER) {
            if (runCatching { con.execute("/user-manager/user/print") }.isSuccess)
                "/user-manager/user/remove" else "/tool/user-manager/user/remove"
        } else "/ip/hotspot/user/remove"
        con.execute("$path .id=${user.routerId}")
        Unit
    }

    /** حذف دفعة كاملة حسب وسم الملاحظة الذي كُتب عند التوليد */
    suspend fun removeBatchByComment(r: RouterProfile?, tag: String): Result<Int> = onRouter(r) { con ->
        var removed = 0
        for (row in con.execute("/ip/hotspot/user/print")) {
            if ((row["comment"] ?: "") != tag) continue
            val id = row[".id"] ?: continue
            runCatching { con.execute("/ip/hotspot/user/remove .id=$id") }.onSuccess { removed++ }
        }
        removed
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

    // ===== إدارة الراوتر =====

    /** تعديل كرت واحد على الراوتر: كلمة المرور، الباقة، الملاحظة، والتعطيل */
    suspend fun updateCard(
        r: RouterProfile?,
        user: UserEntry,
        password: String? = null,
        profile: String? = null,
        comment: String? = null,
        limitUptime: String? = null,
    ): Result<Unit> = onRouter(r) { con ->
        if (user.routerId.isBlank()) error("لا يمكن تعديل هذا الكرت — لم يُجلب من الراوتر")
        if (user.source == CardSource.USER_MANAGER) {
            // اليوزر منجر: الحقول تختلف — group بدل profile، ولا يوجد limit-uptime
            val isV7 = runCatching { con.execute("/user-manager/user/print") }.isSuccess
            val path = if (isV7) "/user-manager/user" else "/tool/user-manager/user"
            val sets = buildString {
                password?.let { append(" password=${q(it)}") }
                comment?.let { append(" comment=${q(it)}") }
                if (isV7) profile?.takeIf { it.isNotBlank() }?.let { append(" group=${q(it)}") }
            }
            if (sets.isNotBlank()) con.execute("$path/set .id=${user.routerId}$sets")
            // تغيير الباقة الفعلية
            profile?.takeIf { it.isNotBlank() }?.let { p ->
                runCatching {
                    if (isV7) {
                        con.printLight("/user-manager/user-profile", ".id,user")
                            .filter { it["user"] == user.username }
                            .forEach { row -> row[".id"]?.let { con.execute("/user-manager/user-profile/remove .id=$it") } }
                        con.execute("/user-manager/user-profile/add user=${q(user.username)} profile=${q(p)}")
                    } else {
                        con.execute(
                            "/tool/user-manager/user/create-and-activate-profile customer=admin " +
                                "numbers=${q(user.username)} profile=${q(p)}"
                        )
                    }
                }
            }
        } else {
            val sets = buildString {
                password?.let { append(" password=${q(it)}") }
                profile?.let { append(" profile=${q(it)}") }
                comment?.let { append(" comment=${q(it)}") }
                limitUptime?.let { append(" limit-uptime=${q(it)}") }
            }
            if (sets.isNotBlank()) con.execute("/ip/hotspot/user/set .id=${user.routerId}$sets")
        }
    }

    /** قائمة عناوين DHCP الممنوحة — تكشف الأجهزة الموجودة على الشبكة */
    suspend fun fetchDhcpLeases(r: RouterProfile?): Result<List<DhcpLease>> = onRouter(r) { con ->
        con.tryPrintLight(
            ".id,address,mac-address,host-name,status,expires-after,dynamic,comment",
            "/ip/dhcp-server/lease",
        ).map { row ->
            DhcpLease(
                id = row[".id"].orEmpty(),
                address = row["address"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                hostName = row["host-name"].orEmpty(),
                status = row["status"].orEmpty(),
                expiresAfter = row["expires-after"].orEmpty(),
                dynamic = row["dynamic"] == "true",
                comment = row["comment"].orEmpty(),
            )
        }
    }

    /** المنافذ وحركة البيانات عليها */
    suspend fun fetchInterfaces(r: RouterProfile?): Result<List<InterfaceStat>> = onRouter(r) { con ->
        con.tryPrintLight(
            ".id,name,type,running,disabled,rx-byte,tx-byte",
            "/interface",
        ).map { row ->
            InterfaceStat(
                name = row["name"].orEmpty(),
                type = row["type"].orEmpty(),
                running = row["running"] == "true",
                disabled = row["disabled"] == "true",
                rxBytes = row["rx-byte"]?.toLongOrNull() ?: 0,
                txBytes = row["tx-byte"]?.toLongOrNull() ?: 0,
            )
        }
    }

    /** أجهزة محجوبة أو مثبّتة في الهوتسبوت (ip-binding) */
    suspend fun fetchIpBindings(r: RouterProfile?): Result<List<IpBinding>> = onRouter(r) { con ->
        con.tryPrintLight(
            ".id,mac-address,address,to-address,type,comment,disabled",
            "/ip/hotspot/ip-binding",
        ).map { row ->
            IpBinding(
                id = row[".id"].orEmpty(),
                macAddress = row["mac-address"].orEmpty(),
                address = row["address"].orEmpty(),
                type = row["type"].orEmpty(),
                comment = row["comment"].orEmpty(),
                disabled = row["disabled"] == "true",
            )
        }
    }

    /** حجب جهاز عن الشبكة بعنوانه الفيزيائي */
    suspend fun blockMac(r: RouterProfile?, mac: String, note: String = ""): Result<Unit> = onRouter(r) { con ->
        val comment = if (note.isBlank()) "" else " comment=${q(note)}"
        con.execute("/ip/hotspot/ip-binding/add mac-address=${q(mac)} type=blocked$comment")
        Unit
    }

    /** السماح لجهاز بالمرور بدون كرت */
    suspend fun bypassMac(r: RouterProfile?, mac: String, note: String = ""): Result<Unit> = onRouter(r) { con ->
        val comment = if (note.isBlank()) "" else " comment=${q(note)}"
        con.execute("/ip/hotspot/ip-binding/add mac-address=${q(mac)} type=bypassed$comment")
        Unit
    }

    suspend fun removeIpBinding(r: RouterProfile?, id: String): Result<Unit> = onRouter(r) { con ->
        con.execute("/ip/hotspot/ip-binding/remove .id=$id")
        Unit
    }

    /** حفظ نسخة احتياطية على ذاكرة الراوتر */
    suspend fun backupRouter(r: RouterProfile?, name: String): Result<String> = onRouter(r) { con ->
        con.execute("/system/backup/save name=${q(name)}")
        "$name.backup"
    }

    /** تصدير الإعدادات نصياً — يعيد الأسطر كما يرسلها الراوتر */
    suspend fun exportConfig(r: RouterProfile?): Result<String> = onRouter(r) { con ->
        val rows = runCatching { con.execute("/export") }.getOrElse { emptyList() }
        rows.joinToString("\n") { row -> row.values.joinToString(" ") }
    }

    /** إعادة تشغيل الراوتر */
    suspend fun rebootRouter(r: RouterProfile?): Result<Unit> = onRouter(r) { con ->
        runCatching { con.execute("/system/reboot") }
        Unit
    }

    /**
     * ربط الكرت بأول جهاز يستخدمه.
     *
     * الراوتر لا يفعل ذلك من نفسه، فنكتب سكربت on-login على بروفايل سيرفر الهوتسبوت:
     * عند أول دخول يُخزَّن عنوان الجهاز في الكرت، فلا يعمل الكرت على جهاز آخر بعدها.
     */
    /** علامة تُذيَّل بها السكربت لنعرف أنه من هذا التطبيق. تعليق في آخر السطر */
    private const val BIND_MARKER = "# cardmanager-bind-first"

    /**
     * سطر واحد لأن مُحلِّل مكتبة الـ API لا يقبل سطراً جديداً داخل قيمة.
     * ونتجنّب علامة التنصيص المفردة لأنها هي التي تُغلِّف القيمة.
     */
    private val bindScript: String = ":local usr ${'$'}user; " +
        ":local mac ${'$'}\"mac-address\"; " +
        ":if ([:len [/ip hotspot user find name=${'$'}usr]] > 0) do={ " +
        ":if ([:len [/ip hotspot user get [find name=${'$'}usr] mac-address]] = 0) do={ " +
        "/ip hotspot user set [find name=${'$'}usr] mac-address=${'$'}mac } }; " +
        BIND_MARKER

    /** نتيجة تشغيل الربط: كم بروفايل تغيّر وكم تُرك لأن عليه سكربت خاص */
    data class BindResult(val changed: Int, val skipped: Int, val total: Int)

    /** هل سكربت الربط مثبَّت على أي بروفايل سيرفر هوتسبوت؟ */
    suspend fun isBindFirstDeviceOn(r: RouterProfile?): Result<Boolean> = onRouter(r) { con ->
        con.tryPrintLight(".id,name,on-login", "/ip/hotspot/profile")
            .any { (it["on-login"] ?: "").contains(BIND_MARKER) }
    }

    /**
     * تشغيل أو إيقاف ربط الكرت بأول جهاز على بروفايلات سيرفر الهوتسبوت.
     * لا نلمس بروفايلاً عليه سكربت on-login من عندك — نتركه ونخبرك بعددها.
     */
    suspend fun setBindFirstDevice(r: RouterProfile?, enabled: Boolean): Result<BindResult> =
        onRouter(r) { con ->
            val profiles = con.tryPrintLight(".id,name,on-login", "/ip/hotspot/profile")
            if (profiles.isEmpty()) error("لا يوجد بروفايل سيرفر هوتسبوت على هذا الراوتر")
            var changed = 0
            var skipped = 0
            profiles.forEach { p ->
                val id = p[".id"].orEmpty()
                if (id.isBlank()) return@forEach
                val current = p["on-login"].orEmpty().trim()
                val hasOurs = current.contains(BIND_MARKER)
                val next: String? = when {
                    enabled && hasOurs -> null
                    enabled && current.isEmpty() -> bindScript
                    enabled -> { skipped++; null }   // عليه سكربت خاص — لا نمسحه
                    hasOurs -> ""
                    else -> null
                }
                if (next != null) {
                    val ok = runCatching {
                        con.execute("/ip/hotspot/profile/set .id=$id on-login='$next'")
                    }.isSuccess
                    if (ok) changed++
                }
            }
            BindResult(changed, skipped, profiles.size)
        }

    /** فك ربط الكروت المحددة بأجهزتها حتى تعمل على جهاز آخر */
    suspend fun clearBoundDevice(
        r: RouterProfile?,
        cards: List<UserEntry>,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> = onRouter(r) { con ->
        var ok = 0
        cards.forEachIndexed { i, c ->
            if (c.routerId.isNotBlank()) {
                val done = runCatching {
                    con.execute("/ip/hotspot/user/set .id=${c.routerId} mac-address=\"\"")
                }.isSuccess
                if (done) ok++
            }
            onProgress(i + 1, cards.size)
        }
        ok
    }

    /** الخدمات المفعّلة (api، www، ssh…) — لتشخيص مشاكل الاتصال */
    suspend fun fetchServices(r: RouterProfile?): Result<List<Triple<String, String, Boolean>>> =
        onRouter(r) { con ->
            con.tryPrintLight("name,port,disabled", "/ip/service").map { row ->
                Triple(row["name"].orEmpty(), row["port"].orEmpty(), row["disabled"] != "true")
            }
        }

    /**
     * نقل كروت بين الهوتسبوت واليوزر منجر.
     * يُنشئ الكروت في الوجهة ثم يحذفها من المصدر إن طُلب ذلك.
     */
    suspend fun moveCards(
        r: RouterProfile?,
        cards: List<UserEntry>,
        to: UploadTarget,
        deleteFromSource: Boolean,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Result<Int> {
        if (cards.isEmpty()) return Result.success(0)
        val created = java.util.Collections.synchronizedList(mutableListOf<UserEntry>())
        val create = when (to) {
            UploadTarget.HOTSPOT ->
                createHotspotUsers(r, cards, { d, t -> onProgress(d, t) }) { created.add(it) }
            UploadTarget.USER_MANAGER ->
                createUserManagerUsers(r, cards, { d, t -> onProgress(d, t) }) { created.add(it) }
        }
        create.onFailure { return Result.failure(it) }
        // لا نحذف من المصدر إلا ما نجح إنشاؤه فعلاً في الوجهة —
        // النسخة القديمة كانت تحذف الكل حتى الكروت التي فشل نقلها
        if (!deleteFromSource) return Result.success(created.size)
        var removed = 0
        created.forEach { c -> if (removeUser(r, c).isSuccess) removed++ }
        return Result.success(removed)
    }
}

/** عنوان DHCP ممنوح لجهاز */
data class DhcpLease(
    val id: String = "",
    val address: String = "",
    val macAddress: String = "",
    val hostName: String = "",
    val status: String = "",
    val expiresAfter: String = "",
    val dynamic: Boolean = true,
    val comment: String = "",
)

/** منفذ على الراوتر وحركة البيانات عليه */
data class InterfaceStat(
    val name: String = "",
    val type: String = "",
    val running: Boolean = false,
    val disabled: Boolean = false,
    val rxBytes: Long = 0,
    val txBytes: Long = 0,
)

/** ربط عنوان فيزيائي في الهوتسبوت — محجوب أو مسموح بدون كرت */
data class IpBinding(
    val id: String = "",
    val macAddress: String = "",
    val address: String = "",
    val type: String = "",
    val comment: String = "",
    val disabled: Boolean = false,
)
