package com.binwaps.cardmanager.fake

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * راوتر RouterOS وهمي يتكلم بروتوكول API الثنائي الحقيقي على مقبس TCP محلي.
 *
 * الغرض: تنفيذ كود [com.binwaps.cardmanager.mikrotik.MikrotikClient] **فعلياً**
 * في CI — الدخول، الجلب بـ count-only والاستعلامات، الرفع المتدفق، يوزر منجر
 * v6/v7 — بدل الاعتماد على اختبارات صيغة الأوامر وحدها. كل عطل سبق أن أوقف
 * الرفع على جهاز المستخدم (name بدل username، customer مفقود، ازدواج الباقة،
 * إصدار مخزّن من راوتر سابق) يُكتشف هنا قبل النشر.
 *
 * يحاكي سلوك RouterOS المؤثر في التطبيق:
 * - كلمات بطول مسبوق، جملة تنتهي بكلمة فارغة، وردّ `.tag` يعكس الأمر
 * - `!re` لكل صف، `!done` (مع `=ret=` للعدّ والإضافة)، `!trap` للأخطاء
 * - `.proplist` يقصّ الحقول؛ استعلامات `?` مع مكدّس `?#` (و/أو/نفي)
 * - v6: `/tool/user-manager` بحقل `username` و`customer` إلزامي، والباقة عبر
 *   `create-and-activate-profile`؛ v7: `/user-manager` بحقل `name` وجدول
 *   `user-profile` **يقبل التكرار** كما الراوتر الحقيقي
 * - مسار غير موجود ⇒ `no such command prefix`؛ حقل غير معروف ⇒ `unknown parameter`
 */
class FakeRouterOsServer(
    val variant: Variant = Variant.V7,
    private val username: String = "admin",
    private val password: String = "1234",
    /** يحاكي راوتراً قديماً (قبل 6.43) يطلب تحدّي MD5 عند الدخول */
    private val legacyLogin: Boolean = false,
) : AutoCloseable {

    enum class Variant { V6, V7, NONE }

    /** الجداول بالمسار ⇒ صفوف (كل صف خريطة حقل ⇒ قيمة، منها `.id`) */
    val tables = ConcurrentHashMap<String, MutableList<MutableMap<String, String>>>()

    /** كل جملة استلمها الخادم — للتحقق من الصيغة المُرسلة فعلياً */
    val commands = CopyOnWriteArrayList<List<String>>()

    private val nextId = AtomicInteger(0)
    private lateinit var server: ServerSocket
    @Volatile private var running = false
    private val threads = CopyOnWriteArrayList<Thread>()

    val port: Int get() = server.localPort

    init {
        listOf(
            "/system/resource", "/system/identity", "/ip/hotspot", "/ip/hotspot/user",
            "/ip/hotspot/user/profile", "/ip/hotspot/active", "/ip/hotspot/cookie", "/log",
        ).forEach { table(it) }
        when (variant) {
            Variant.V6 -> listOf("user", "customer", "profile", "session").forEach { table("/tool/user-manager/$it") }
            Variant.V7 -> listOf("user", "user-profile", "profile", "session").forEach { table("/user-manager/$it") }
            Variant.NONE -> {}
        }
        add(
            "/system/resource",
            "version" to if (variant == Variant.V6) "6.49.13 (long-term)" else "7.15.3 (stable)",
            "board-name" to "hAP ac2", "uptime" to "1d2h3m4s", "cpu-load" to "3",
            "free-memory" to "100000000", "total-memory" to "256000000",
        )
        add("/system/identity", "name" to "FAKE-ROUTER")
        add("/ip/hotspot", "name" to "hotspot1", "interface" to "bridge")
        add("/ip/hotspot/user/profile", "name" to "default", "shared-users" to "1")
        if (variant == Variant.V6) add("/tool/user-manager/customer", "login" to "shop", "password" to "x")
    }

    // ===== واجهة التهيئة والفحص للاختبارات =====

    fun table(path: String): MutableList<MutableMap<String, String>> =
        tables.getOrPut(path) { Collections.synchronizedList(mutableListOf()) }

    fun add(path: String, vararg kv: Pair<String, String>): String {
        val row = LinkedHashMap<String, String>()
        row[".id"] = newId()
        kv.forEach { (k, v) -> row[k] = v }
        table(path).add(row)
        return row[".id"]!!
    }

    fun rows(path: String): List<Map<String, String>> = synchronized(table(path)) { table(path).map { it.toMap() } }
    fun count(path: String): Int = table(path).size

    /** يضيف كرت هوتسبوت بالحقول الافتراضية كما ينشئه الراوتر */
    fun addHotspotUser(
        name: String, profile: String = "default", password: String = "",
        uptime: String = "0s", limitUptime: String = "", disabled: Boolean = false,
        comment: String = "", bytesIn: Long = 0, bytesOut: Long = 0,
    ): String = add(
        "/ip/hotspot/user",
        *buildList {
            add("name" to name); add("profile" to profile)
            if (password.isNotEmpty()) add("password" to password)
            if (limitUptime.isNotEmpty()) add("limit-uptime" to limitUptime)
            add("uptime" to uptime); add("bytes-in" to "$bytesIn"); add("bytes-out" to "$bytesOut")
            add("disabled" to if (disabled) "true" else "false")
            if (comment.isNotEmpty()) add("comment" to comment)
        }.toTypedArray(),
    )

    fun start(): FakeRouterOsServer {
        server = ServerSocket(0, 50, java.net.InetAddress.getLoopbackAddress())
        running = true
        val acceptor = Thread({
            while (running) {
                val sock = runCatching { server.accept() }.getOrNull() ?: break
                val t = Thread({ runCatching { serve(sock) } }, "fake-ros-conn").apply { isDaemon = true }
                threads += t
                t.start()
            }
        }, "fake-ros-accept").apply { isDaemon = true }
        threads += acceptor
        acceptor.start()
        return this
    }

    override fun close() {
        running = false
        runCatching { server.close() }
        threads.forEach { runCatching { it.interrupt() } }
    }

    // ===== البروتوكول =====

    private fun serve(sock: Socket) {
        sock.use { s ->
            s.tcpNoDelay = true
            val inp = BufferedInputStream(s.getInputStream())
            val out = BufferedOutputStream(s.getOutputStream())
            var loggedIn = false
            var challenge: ByteArray? = null
            while (running) {
                val sentence = readSentence(inp) ?: break
                if (sentence.isEmpty()) continue
                commands.add(sentence)
                val tag = sentence.firstOrNull { it.startsWith(".tag=") }?.substringAfter("=")
                val params = paramsOf(sentence)
                val replies: List<List<String>> = if (sentence[0] == "/login") {
                    val name = params["name"]
                    if (legacyLogin) {
                        val resp = params["response"]
                        if (resp == null) {
                            // تحدّي MD5: بايتات كلها < 0x80 حتى لا يؤثر ترميز المكتبة للنص
                            challenge = "0123456789abcdef".toByteArray(Charsets.US_ASCII)
                            listOf(listOf("!done", "=ret=" + challenge!!.toHex()))
                        } else {
                            val md = MessageDigest.getInstance("MD5")
                            md.update(0.toByte())
                            md.update(password.toByteArray(Charsets.UTF_8))
                            md.update(challenge ?: ByteArray(0))
                            val expected = "00" + md.digest().toHex()
                            if (name == username && resp == expected) { loggedIn = true; listOf(listOf("!done")) }
                            else trap("invalid user name or password (6)")
                        }
                    } else {
                        if (name == username && params["password"] == password) { loggedIn = true; listOf(listOf("!done")) }
                        else trap("invalid user name or password (6)")
                    }
                } else if (!loggedIn) {
                    trap("not logged in (9)")
                } else {
                    runCatching { handle(sentence, params) }.getOrElse { trap("internal: ${it.message}") }
                }
                for (r in replies) writeSentence(out, if (tag != null) r + ".tag=$tag" else r)
                out.flush()
            }
        }
    }

    private fun paramsOf(words: List<String>): LinkedHashMap<String, String> {
        val params = LinkedHashMap<String, String>()
        for (w in words.drop(1)) {
            if (!w.startsWith("=") || w.startsWith("=.proplist=")) continue
            val body = w.substring(1)
            val i = body.indexOf('=')
            if (i > 0) params[body.substring(0, i)] = body.substring(i + 1) else params[body] = ""
        }
        return params
    }

    private fun handle(words: List<String>, params: LinkedHashMap<String, String>): List<List<String>> {
        val cmd = words[0]
        var proplist: List<String>? = null
        var countOnly = false
        val queries = mutableListOf<String>()
        for (w in words.drop(1)) {
            when {
                w.startsWith("=.proplist=") ->
                    proplist = w.removePrefix("=.proplist=").split(",").map { it.trim() }.filter { it.isNotEmpty() }
                w == "=count-only=" || w == "=count-only" -> countOnly = true
                w.startsWith("?") -> queries.add(w)
            }
        }
        params.remove("count-only")
        val slash = cmd.lastIndexOf('/')
        if (slash <= 0) return trap("no such command prefix")
        val path = cmd.substring(0, slash)
        val action = cmd.substring(slash + 1)
        val rows = tables[path] ?: return trap("no such command prefix")
        return synchronized(rows) {
            when (action) {
                "print" -> print(rows, proplist, countOnly, queries)
                "add" -> add(path, rows, params)
                "set" -> set(rows, params)
                "remove" -> remove(rows, params)
                "reset-counters" -> resetCounters(rows, params)
                "create-and-activate-profile" ->
                    if (path == "/tool/user-manager/user") createAndActivate(rows, params) else trap("no such command")
                else -> trap("no such command")
            }
        }
    }

    private fun print(
        rows: List<MutableMap<String, String>>, proplist: List<String>?, countOnly: Boolean, queries: List<String>,
    ): List<List<String>> {
        val filtered = rows.filter { matches(it, queries) }
        if (countOnly) return listOf(listOf("!done", "=ret=${filtered.size}"))
        val out = filtered.map { row ->
            val fields = if (proplist == null) row.map { "=${it.key}=${it.value}" }
            else proplist.mapNotNull { k -> row[k]?.let { "=$k=$it" } }
            listOf("!re") + fields
        }
        return out + listOf(listOf("!done"))
    }

    private val v6UserFields = setOf("username", "password", "customer", "comment", "disabled", "email", "phone", "caller-id", "shared-users", "wireless-psk", "copy-from")
    private val v7UserFields = setOf("name", "password", "group", "comment", "disabled", "attributes", "shared-users", "otp-secret", "caller-id", "copy-from")

    private fun add(path: String, rows: MutableList<MutableMap<String, String>>, params: Map<String, String>): List<List<String>> {
        val row = LinkedHashMap<String, String>()
        when (path) {
            "/ip/hotspot/user" -> {
                val name = params["name"] ?: return trap("failure: name is required")
                if (rows.any { it["name"] == name }) return trap("failure: already have user with this name")
                val profile = params["profile"] ?: "default"
                if (table("/ip/hotspot/user/profile").none { it["name"] == profile }) {
                    return trap("input does not match any value of profile")
                }
                row.putAll(params)
                row["profile"] = profile
                row.putIfAbsent("uptime", "0s"); row.putIfAbsent("bytes-in", "0"); row.putIfAbsent("bytes-out", "0")
                row.putIfAbsent("disabled", "false")
            }
            "/tool/user-manager/user" -> {
                params.keys.firstOrNull { it !in v6UserFields }?.let { return trap("unknown parameter $it") }
                val name = params["username"] ?: return trap("failure: username is required")
                if (rows.any { it["username"] == name }) return trap("failure: already have user with this name")
                val customer = params["customer"] ?: return trap("failure: customer is required")
                if (table("/tool/user-manager/customer").none { it["login"] == customer }) {
                    return trap("input does not match any value of customer")
                }
                row.putAll(params)
                row.putIfAbsent("disabled", "false"); row.putIfAbsent("uptime-used", "0s")
                row.putIfAbsent("download-used", "0"); row.putIfAbsent("upload-used", "0")
            }
            "/user-manager/user" -> {
                params.keys.firstOrNull { it !in v7UserFields }?.let { return trap("unknown parameter $it") }
                val name = params["name"] ?: return trap("failure: name is required")
                if (rows.any { it["name"] == name }) return trap("failure: already have user with this name")
                row.putAll(params)
                row.putIfAbsent("disabled", "false")
            }
            "/user-manager/user-profile" -> {
                val user = params["user"] ?: return trap("failure: user is required")
                val profile = params["profile"] ?: return trap("failure: profile is required")
                if (table("/user-manager/user").none { it["name"] == user }) return trap("input does not match any value of user")
                if (table("/user-manager/profile").none { it["name"] == profile }) return trap("input does not match any value of profile")
                // الراوتر الحقيقي يقبل صفوفاً متعددة لنفس المستخدم (باقات متتالية)
                row.putAll(params)
                row.putIfAbsent("state", "waiting")
            }
            "/ip/hotspot/user/profile", "/user-manager/profile", "/tool/user-manager/profile" -> {
                val name = params["name"] ?: return trap("failure: name is required")
                if (rows.any { it["name"] == name }) return trap("failure: already have profile with this name")
                row.putAll(params)
            }
            else -> row.putAll(params)
        }
        row[".id"] = newId()
        rows.add(row)
        return listOf(listOf("!done", "=ret=${row[".id"]}"))
    }

    private fun find(rows: List<MutableMap<String, String>>, params: Map<String, String>): MutableMap<String, String>? {
        val id = params[".id"] ?: params["numbers"] ?: return null
        return rows.firstOrNull { it[".id"] == id }
    }

    private fun set(rows: MutableList<MutableMap<String, String>>, params: Map<String, String>): List<List<String>> {
        val row = find(rows, params) ?: return trap("no such item")
        params.forEach { (k, v) -> if (k != ".id" && k != "numbers") row[k] = v }
        return listOf(listOf("!done"))
    }

    private fun remove(rows: MutableList<MutableMap<String, String>>, params: Map<String, String>): List<List<String>> {
        val row = find(rows, params) ?: return trap("no such item")
        rows.remove(row)
        return listOf(listOf("!done"))
    }

    private fun resetCounters(rows: MutableList<MutableMap<String, String>>, params: Map<String, String>): List<List<String>> {
        val row = find(rows, params) ?: return trap("no such item")
        row["uptime"] = "0s"; row["bytes-in"] = "0"; row["bytes-out"] = "0"
        return listOf(listOf("!done"))
    }

    /** v6: يفعّل باقة على مستخدم — كل تفعيل يُحسب (للكشف عن الازدواج) */
    private fun createAndActivate(rows: MutableList<MutableMap<String, String>>, params: Map<String, String>): List<List<String>> {
        val profile = params["profile"] ?: return trap("failure: profile is required")
        val customer = params["customer"] ?: return trap("failure: customer is required")
        val numbers = params["numbers"] ?: return trap("failure: numbers is required")
        if (table("/tool/user-manager/profile").none { it["name"] == profile }) {
            return trap("input does not match any value of profile")
        }
        if (table("/tool/user-manager/customer").none { it["login"] == customer }) {
            return trap("input does not match any value of customer")
        }
        val row = rows.firstOrNull { it["username"] == numbers || it[".id"] == numbers }
            ?: return trap("no such item")
        row["actual-profile"] = profile
        row["activations"] = ((row["activations"]?.toIntOrNull() ?: 0) + 1).toString()
        return listOf(listOf("!done"))
    }

    // ===== الاستعلامات (مكدّس RouterOS) =====

    private fun matches(row: Map<String, String>, queries: List<String>): Boolean {
        if (queries.isEmpty()) return true
        val stack = ArrayDeque<Boolean>()
        fun pop() = stack.removeLastOrNull() ?: false
        for (q in queries) {
            val body = q.substring(1)
            when {
                body.startsWith("#") -> for (ch in body.substring(1)) when (ch) {
                    '!' -> stack.addLast(!pop())
                    '&' -> { val a = pop(); val b = pop(); stack.addLast(a && b) }
                    '|' -> { val a = pop(); val b = pop(); stack.addLast(a || b) }
                    '.' -> stack.addLast(stack.lastOrNull() ?: false)
                }
                body.startsWith("-") -> stack.addLast(!row.containsKey(body.substring(1)))
                body.startsWith("<") || body.startsWith(">") -> {
                    val rest = body.substring(1)
                    val i = rest.indexOf('=')
                    val key = rest.substring(0, i); val value = rest.substring(i + 1)
                    val v = row[key]
                    val c = if (v == null) null else compareValues(v, value)
                    stack.addLast(c != null && if (body[0] == '<') c < 0 else c > 0)
                }
                body.contains('=') -> {
                    val i = body.indexOf('=')
                    val key = body.substring(0, i); val value = body.substring(i + 1)
                    val v = row[key]
                    stack.addLast(v != null && (v == value || compareValues(v, value) == 0))
                }
                else -> stack.addLast(row.containsKey(body))
            }
        }
        return stack.all { it }
    }

    private val durationRe = Regex("^(\\d+[wdhms])+$")

    private fun compareValues(a: String, b: String): Int {
        a.toLongOrNull()?.let { x -> b.toLongOrNull()?.let { y -> return x.compareTo(y) } }
        if (durationRe.matches(a) && durationRe.matches(b)) return seconds(a).compareTo(seconds(b))
        return a.compareTo(b)
    }

    private fun seconds(v: String): Long {
        var total = 0L
        for (m in Regex("(\\d+)([wdhms])").findAll(v)) {
            val n = m.groupValues[1].toLong()
            total += when (m.groupValues[2]) {
                "w" -> n * 604800; "d" -> n * 86400; "h" -> n * 3600; "m" -> n * 60; else -> n
            }
        }
        return total
    }

    // ===== ترميز الكلمات =====

    private fun newId() = "*" + Integer.toHexString(nextId.incrementAndGet()).uppercase()

    /**
     * ردّ فشل كامل: `!trap` ثم `!done`. RouterOS يُنهي كل أمر فاشل بـ `!done`، والمكتبة
     * لا توقظ المنتظر إلا عنده — `!trap` وحده كان يعلّق الأمر حتى انتهاء مهلته.
     */
    private fun trap(message: String): List<List<String>> =
        listOf(listOf("!trap", "=category=0", "=message=$message"), listOf("!done"))

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }

    private fun readByte(inp: InputStream): Int {
        val c = inp.read()
        if (c < 0) throw java.io.EOFException()
        return c
    }

    private fun readLen(inp: InputStream): Int {
        val c = inp.read()
        if (c < 0) return -1
        return when {
            c and 0x80 == 0 -> c
            c and 0xC0 == 0x80 -> ((c and 0x3F) shl 8) or readByte(inp)
            c and 0xE0 == 0xC0 -> ((c and 0x1F) shl 16) or (readByte(inp) shl 8) or readByte(inp)
            c and 0xF0 == 0xE0 -> ((c and 0x0F) shl 24) or (readByte(inp) shl 16) or (readByte(inp) shl 8) or readByte(inp)
            else -> (readByte(inp) shl 24) or (readByte(inp) shl 16) or (readByte(inp) shl 8) or readByte(inp)
        }
    }

    /** يقرأ جملة كاملة؛ null عند انتهاء المقبس */
    private fun readSentence(inp: InputStream): List<String>? {
        val words = mutableListOf<String>()
        while (true) {
            val len = try { readLen(inp) } catch (e: java.io.EOFException) { return null }
            if (len < 0) return if (words.isEmpty()) null else words
            if (len == 0) return words
            val buf = ByteArray(len)
            var off = 0
            while (off < len) {
                val n = inp.read(buf, off, len - off)
                if (n < 0) return null
                off += n
            }
            words.add(String(buf, Charsets.UTF_8))
        }
    }

    private fun writeLen(out: OutputStream, len: Int) {
        when {
            len < 0x80 -> out.write(len)
            len < 0x4000 -> { val v = len or 0x8000; out.write(v shr 8); out.write(v and 0xFF) }
            len < 0x200000 -> { val v = len or 0xC00000; out.write(v shr 16); out.write((v shr 8) and 0xFF); out.write(v and 0xFF) }
            len < 0x10000000 -> {
                val v = len or 0xE0000000.toInt()
                out.write(v ushr 24); out.write((v shr 16) and 0xFF); out.write((v shr 8) and 0xFF); out.write(v and 0xFF)
            }
            else -> {
                out.write(0xF0)
                out.write(len ushr 24); out.write((len shr 16) and 0xFF); out.write((len shr 8) and 0xFF); out.write(len and 0xFF)
            }
        }
    }

    private fun writeSentence(out: OutputStream, words: List<String>) {
        for (w in words) {
            val bytes = w.toByteArray(Charsets.UTF_8)
            writeLen(out, bytes.size)
            out.write(bytes)
        }
        out.write(0)
    }
}
