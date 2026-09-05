package com.binwaps.cardmanager

import com.binwaps.cardmanager.fake.FakeRouterOsServer
import com.binwaps.cardmanager.fake.FakeRouterOsServer.Variant
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.model.UserEntry
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

/**
 * اختبارات تكامل حقيقية: MikrotikClient كاملاً (الجلسة الدائمة، القفل، pipeline،
 * كشف الإصدار، count-only، الاستعلامات) ضد راوتر وهمي يتكلم بروتوكول API
 * الثنائي على مقبس محلي. تُثبت أن الجلب والرفع يعملان **فعلاً** لا أن الصيغة
 * صحيحة فقط، وأن إعادة الرفع لا تُكرّر شيئاً.
 */
class MikrotikIntegrationTest {

    private val servers = mutableListOf<FakeRouterOsServer>()

    private fun router(
        variant: Variant = Variant.V7,
        legacy: Boolean = false,
        password: String = "1234",
    ): Pair<FakeRouterOsServer, RouterProfile> {
        val s = FakeRouterOsServer(variant = variant, legacyLogin = legacy).start()
        servers += s
        val r = RouterProfile(
            id = s.port.toLong(), name = "fake", host = "127.0.0.1", port = s.port,
            username = "admin", password = password, useSsl = false, timeoutSec = 5,
        )
        return s to r
    }

    @After
    fun tearDown() {
        servers.forEach { it.close() }
        servers.clear()
    }

    private fun cards(n: Int, prefix: String = "u", profile: String = "default", tag: String = "vc-test") =
        (1..n).map { UserEntry(username = "$prefix%05d".format(it), password = "p$it", profile = profile, batchTag = tag) }

    // ===== الاتصال والدخول =====

    @Test
    fun `الاتصال يقرأ الهوية والإصدار وعدد المتصلين`() = runBlocking<Unit> {
        val (s, r) = router()
        s.add("/ip/hotspot/active", "user" to "a", "address" to "10.0.0.2")
        s.add("/ip/hotspot/active", "user" to "b", "address" to "10.0.0.3")
        val st = MikrotikClient.connect(r).getOrThrow()
        assertEquals("FAKE-ROUTER", st.identity)
        assertTrue(st.version.startsWith("7."))
        assertEquals(2, st.activeUsers)
    }

    @Test
    fun `كلمة مرور خاطئة تعطي رسالة عربية مفهومة`() = runBlocking<Unit> {
        val (_, r) = router(password = "wrong")
        val res = MikrotikClient.connect(r)
        assertTrue(res.isFailure)
        assertEquals("اسم المستخدم أو كلمة المرور غير صحيحة", res.exceptionOrNull()?.message)
    }

    @Test
    fun `الدخول بتحدي MD5 على راوتر قديم يعمل`() = runBlocking<Unit> {
        val (_, r) = router(variant = Variant.V6, legacy = true)
        val st = MikrotikClient.connect(r).getOrThrow()
        assertEquals("FAKE-ROUTER", st.identity)
    }

    @Test
    fun `منفذ مغلق يعطي رسالة عربية لا تعليقاً`() = runBlocking<Unit> {
        val (s, r) = router()
        s.close()
        val res = MikrotikClient.connect(r)
        assertTrue(res.isFailure)
        val msg = res.exceptionOrNull()?.message.orEmpty()
        assertTrue(msg, msg.contains("رفض الاتصال") || msg.contains("مهلة"))
    }

    // ===== الإحصائيات والجلب =====

    @Test
    fun `الإحصائيات تُعدّ على الراوتر بـ count-only مع استعلام المستعمل`() = runBlocking<Unit> {
        val (s, r) = router()
        s.addHotspotUser("default-trial")
        repeat(200) { s.addHotspotUser("n%03d".format(it)) }
        repeat(40) { s.addHotspotUser("used%03d".format(it), uptime = "1h2m") }
        repeat(10) { s.addHotspotUser("dis%03d".format(it), disabled = true) }
        repeat(5) { s.addHotspotUser("exp%03d".format(it), limitUptime = "1s") }
        s.add("/user-manager/user", "name" to "um1")
        s.add("/user-manager/user", "name" to "um2")

        val st = MikrotikClient.fetchCardStats(r).getOrThrow()
        assertEquals(256, st.hotspotUsers)
        assertEquals(55, st.usedUsers)
        assertEquals(2, st.userManagerUsers)
        // لم تُنقل أي قائمة كاملة لمجرد العدّ
        assertTrue(s.commands.none { it[0] == "/ip/hotspot/user/print" && it.none { w -> w.startsWith("=count-only") } })
    }

    @Test
    fun `جلب كل الكروت يصنّف الحالة ويستثني default-trial ويضم يوزر منجر v7`() = runBlocking<Unit> {
        val (s, r) = router()
        s.addHotspotUser("default-trial")
        s.addHotspotUser("fresh", comment = "vc-b1")
        s.addHotspotUser("inuse", uptime = "5m")
        s.addHotspotUser("off", disabled = true)
        s.addHotspotUser("expired", limitUptime = "1s")
        s.add("/user-manager/profile", "name" to "P1")
        s.add("/user-manager/user", "name" to "umfresh")
        s.add("/user-manager/user", "name" to "umused")
        s.add("/user-manager/user-profile", "user" to "umfresh", "profile" to "P1", "state" to "waiting")
        s.add("/user-manager/user-profile", "user" to "umused", "profile" to "P1", "state" to "used", "end-time" to "jan/01/2020 00:00:00")

        val all = MikrotikClient.fetchAllCards(r, foreground = true).getOrThrow()
        val byName = all.associateBy { it.username }
        assertFalse(byName.containsKey("default-trial"))
        assertEquals(CardStatus.UNUSED, byName["fresh"]!!.status)
        assertEquals("vc-b1", byName["fresh"]!!.batchTag)
        assertEquals(CardStatus.IN_USE, byName["inuse"]!!.status)
        assertEquals(CardStatus.DISABLED, byName["off"]!!.status)
        assertEquals(CardStatus.EXPIRED, byName["expired"]!!.status)
        assertEquals(CardSource.USER_MANAGER, byName["umfresh"]!!.source)
        assertEquals("P1", byName["umfresh"]!!.profile)
        assertEquals(CardStatus.UNUSED, byName["umfresh"]!!.status)
        assertEquals(CardStatus.EXPIRED, byName["umused"]!!.status)
        assertTrue(byName["umfresh"]!!.routerId.startsWith("*"))
    }

    @Test
    fun `الباقات من المصدرين — جدولا الباقات فقط بلا نقل قائمة المستخدمين`() = runBlocking<Unit> {
        val (s, r) = router()
        s.add("/ip/hotspot/user/profile", "name" to "A", "rate-limit" to "2M/2M")
        s.add("/ip/hotspot/user/profile", "name" to "B")
        repeat(30) { s.addHotspotUser("a$it", profile = "A") }
        s.add("/user-manager/profile", "name" to "P1", "validity" to "30d")
        repeat(7) {
            s.add("/user-manager/user", "name" to "p$it")
            s.add("/user-manager/user-profile", "user" to "p$it", "profile" to "P1")
        }
        val profiles = MikrotikClient.fetchProfiles(r, foreground = true).getOrThrow().associateBy { it.name }
        assertEquals(setOf("default", "A", "B", "P1"), profiles.keys)
        assertEquals("2M/2M", profiles["A"]!!.rateLimit)
        assertEquals(CardSource.HOTSPOT, profiles["A"]!!.source)
        assertEquals(CardSource.USER_MANAGER, profiles["P1"]!!.source)
        assertEquals("30d", profiles["P1"]!!.sessionTimeout)
        // عدد كروت كل باقة يُحسب محلياً — لا يُنقل صف واحد من المستخدمين هنا
        assertTrue(s.commands.none { it[0] == "/ip/hotspot/user/print" || it[0] == "/user-manager/user-profile/print" })
    }

    @Test
    fun `باقات v6 تُقرأ من مسار tool`() = runBlocking<Unit> {
        val (s, r) = router(variant = Variant.V6)
        s.add("/tool/user-manager/profile", "name" to "M1")
        val profiles = MikrotikClient.fetchProfiles(r, foreground = true).getOrThrow().associateBy { it.name }
        assertEquals(CardSource.USER_MANAGER, profiles["M1"]!!.source)
        assertTrue(profiles.containsKey("default"))
    }

    // ===== الرفع =====

    @Test
    fun `رفع ٢٠٠٠ كرت هوتسبوت متدفقاً — كلها تصل وإعادة الرفع لا تكرّر`() = runBlocking<Unit> {
        val (s, r) = router()
        s.add("/ip/hotspot/user/profile", "name" to "شهري 10 جيجا")
        val users = cards(2000, profile = "شهري 10 جيجا", tag = "vc-260903")
        val progress = mutableListOf<Pair<Int, Int>>()
        val created = AtomicInteger(0)

        val ok = MikrotikClient.createHotspotUsers(r, users, { d, t -> progress += d to t }, { created.incrementAndGet() }).getOrThrow()
        assertEquals(2000, ok)
        assertEquals(2000, created.get())
        assertEquals(2000, s.count("/ip/hotspot/user"))
        assertEquals(2000 to 2000, progress.last())
        val row = s.rows("/ip/hotspot/user").first { it["name"] == "u00001" }
        assertEquals("شهري 10 جيجا", row["profile"])
        assertEquals("p1", row["password"])
        assertEquals("vc-260903", row["comment"])

        // إعادة رفع نفس الدفعة (انقطاع ثم إعادة): موجود مسبقاً = نجاح، ولا كرت مكرّر
        val again = MikrotikClient.createHotspotUsers(r, users).getOrThrow()
        assertEquals(2000, again)
        assertEquals(2000, s.count("/ip/hotspot/user"))
    }

    @Test
    fun `باقة غير موجودة تُفشل الرفع بسبب واضح لا شريطاً متجمداً`() = runBlocking<Unit> {
        val (s, r) = router()
        val res = MikrotikClient.createHotspotUsers(r, cards(50, profile = "لا وجود لها"))
        assertTrue(res.isFailure)
        assertEquals(0, s.count("/ip/hotspot/user"))
        assertTrue(res.exceptionOrNull()?.message.orEmpty().contains("رفض الراوتر إنشاء الكروت"))
    }

    @Test
    fun `رفع يوزر منجر v6 — username والعميل من الجدول وتفعيل الباقة مرة واحدة`() = runBlocking<Unit> {
        val (s, r) = router(variant = Variant.V6)
        s.add("/tool/user-manager/profile", "name" to "Monthly")
        val users = cards(300, prefix = "v6", profile = "Monthly")

        val ok = MikrotikClient.createUserManagerUsers(r, users).getOrThrow()
        assertEquals(300, ok)
        val rows = s.rows("/tool/user-manager/user")
        assertEquals(300, rows.size)
        assertTrue(rows.all { it["customer"] == "shop" })
        assertTrue(rows.all { it["actual-profile"] == "Monthly" })
        assertTrue(rows.all { it["activations"] == "1" })
        assertTrue(rows.all { it["username"]!!.startsWith("v6") && !it.containsKey("name") })

        // إعادة الرفع: لا مستخدم مكرّر ولا تفعيل مكرّر للباقة
        val again = MikrotikClient.createUserManagerUsers(r, users).getOrThrow()
        assertEquals(300, again)
        val rows2 = s.rows("/tool/user-manager/user")
        assertEquals(300, rows2.size)
        assertTrue("تفعيل الباقة تكرّر عند إعادة الرفع", rows2.all { it["activations"] == "1" })

        val fetched = MikrotikClient.fetchAllCards(r, foreground = true).getOrThrow()
        assertEquals(300, fetched.count { it.source == CardSource.USER_MANAGER && it.profile == "Monthly" })
    }

    @Test
    fun `رفع يوزر منجر v7 — name وربط الباقة في user-profile بلا ازدواج`() = runBlocking<Unit> {
        val (s, r) = router(variant = Variant.V7)
        s.add("/user-manager/profile", "name" to "Weekly")
        val users = cards(300, prefix = "v7", profile = "Weekly")

        val ok = MikrotikClient.createUserManagerUsers(r, users).getOrThrow()
        assertEquals(300, ok)
        assertEquals(300, s.count("/user-manager/user"))
        assertEquals(300, s.count("/user-manager/user-profile"))
        assertTrue(s.rows("/user-manager/user").none { it.containsKey("group") })
        assertTrue(s.rows("/user-manager/user-profile").all { it["profile"] == "Weekly" })

        // إعادة الرفع: الراوتر الحقيقي يقبل صف user-profile ثانياً لنفس المستخدم —
        // التطبيق هو من يجب أن يمنع الازدواج
        val again = MikrotikClient.createUserManagerUsers(r, users).getOrThrow()
        assertEquals(300, again)
        assertEquals(300, s.count("/user-manager/user"))
        assertEquals("ربط الباقة تكرّر عند إعادة الرفع", 300, s.count("/user-manager/user-profile"))
    }

    @Test
    fun `رفع انقطع بين الموجتين — إعادة الرفع تكمل ربط الباقة للناقصين فقط`() = runBlocking<Unit> {
        val (s, r) = router(variant = Variant.V7)
        s.add("/user-manager/profile", "name" to "Weekly")
        // ٥٠ مستخدماً موجودين بلا باقة (كأن الرفع السابق مات بعد الموجة الأولى)
        repeat(50) { s.add("/user-manager/user", "name" to "x%05d".format(it + 1)) }
        // و٢٠ موجودين بباقتهم
        repeat(20) {
            val n = "x%05d".format(it + 51)
            s.add("/user-manager/user", "name" to n)
            s.add("/user-manager/user-profile", "user" to n, "profile" to "Weekly")
        }
        val users = cards(100, prefix = "x", profile = "Weekly")
        val ok = MikrotikClient.createUserManagerUsers(r, users).getOrThrow()
        assertEquals(100, ok)
        assertEquals(100, s.count("/user-manager/user"))
        assertEquals(100, s.count("/user-manager/user-profile"))
        assertEquals(100, s.rows("/user-manager/user-profile").map { it["user"] }.toSet().size)
    }

    @Test
    fun `التبديل من راوتر v6 إلى v7 يعيد كشف الإصدار ولا يستعمل المسار القديم`() = runBlocking<Unit> {
        val (s6, r6) = router(variant = Variant.V6)
        s6.add("/tool/user-manager/profile", "name" to "M")
        assertEquals(5, MikrotikClient.createUserManagerUsers(r6, cards(5, prefix = "a", profile = "M")).getOrThrow())

        val (s7, r7) = router(variant = Variant.V7)
        s7.add("/user-manager/profile", "name" to "M")
        val res = MikrotikClient.createUserManagerUsers(r7, cards(5, prefix = "b", profile = "M"))
        assertTrue(res.exceptionOrNull()?.message.orEmpty(), res.isSuccess)
        assertEquals(5, s7.count("/user-manager/user"))
        assertEquals(5, s7.count("/user-manager/user-profile"))
        assertTrue(s7.commands.none { it[0].startsWith("/tool/user-manager/user/add") })
    }

    @Test
    fun `راوتر بلا حزمة يوزر منجر — رسالة عربية والهوتسبوت يُجلب رغم ذلك`() = runBlocking<Unit> {
        val (s, r) = router(variant = Variant.NONE)
        s.addHotspotUser("h1")
        val res = MikrotikClient.createUserManagerUsers(r, cards(50, prefix = "n", profile = "M"))
        assertTrue(res.isFailure)
        assertTrue(res.exceptionOrNull()?.message.orEmpty().contains("اليوزر منجر"))
        val all = MikrotikClient.fetchAllCards(r, foreground = true).getOrThrow()
        assertEquals(listOf("h1"), all.map { it.username })
    }

    // ===== العمليات الجماعية =====

    @Test
    fun `تغيير الباقة جماعياً — هوتسبوت وv7 معاً بلا صفوف باقة مكرّرة`() = runBlocking<Unit> {
        val (s, r) = router(variant = Variant.V7)
        s.add("/ip/hotspot/user/profile", "name" to "NEW")
        s.add("/user-manager/profile", "name" to "OLD")
        s.add("/user-manager/profile", "name" to "NEW")
        repeat(200) { s.addHotspotUser("h%03d".format(it)) }
        repeat(100) {
            s.add("/user-manager/user", "name" to "m%03d".format(it))
            s.add("/user-manager/user-profile", "user" to "m%03d".format(it), "profile" to "OLD")
        }
        val all = MikrotikClient.fetchAllCards(r, foreground = true).getOrThrow()
        assertEquals(300, all.size)
        val progress = mutableListOf<Pair<Int, Int>>()
        val res = MikrotikClient.bulkSetProfile(r, all, "NEW") { d, t -> progress += d to t }.getOrThrow()
        assertEquals(300, res.ok)
        assertEquals(0, res.failed)
        assertEquals(300 to 300, progress.last())
        assertTrue(s.rows("/ip/hotspot/user").all { it["profile"] == "NEW" })
        assertEquals(100, s.count("/user-manager/user-profile"))
        assertTrue(s.rows("/user-manager/user-profile").all { it["profile"] == "NEW" })
    }

    @Test
    fun `الحذف الجماعي يفصل الجلسات النشطة ثم يحذف`() = runBlocking<Unit> {
        val (s, r) = router()
        repeat(20) { s.addHotspotUser("d%02d".format(it)) }
        s.add("/ip/hotspot/active", "user" to "d01", "address" to "10.0.0.5")
        val all = MikrotikClient.fetchAllCards(r, foreground = true).getOrThrow()
        val res = MikrotikClient.bulkDelete(r, all.take(10)).getOrThrow()
        assertEquals(10, res.ok)
        assertEquals(10, s.count("/ip/hotspot/user"))
        assertEquals(0, s.count("/ip/hotspot/active"))
    }

    @Test
    fun `تعطيل وتفعيل كرت واحد بالمعرّف`() = runBlocking<Unit> {
        val (s, r) = router()
        s.addHotspotUser("one")
        val card = MikrotikClient.fetchAllCards(r, foreground = true).getOrThrow().single()
        MikrotikClient.setUserEnabled(r, card, enabled = false).getOrThrow()
        assertEquals("true", s.rows("/ip/hotspot/user").single()["disabled"])
        MikrotikClient.setUserEnabled(r, card, enabled = true).getOrThrow()
        assertEquals("false", s.rows("/ip/hotspot/user").single()["disabled"])
    }

    @Test
    fun `التشخيص يعيد سطوراً بنتائج حقيقية`() = runBlocking<Unit> {
        val (s, r) = router()
        repeat(3) { s.addHotspotUser("t$it") }
        val lines = MikrotikClient.diagnose(r).getOrThrow()
        assertTrue(lines.size >= 10)
        val count = lines.first { it.label.contains("count-only") && it.label.contains("الهوتسبوت") }
        assertTrue(count.ok)
        assertEquals("3", count.value)
        assertNotNull(lines.firstOrNull { it.label == "هوية الراوتر" && it.value == "FAKE-ROUTER" })
    }
}
