package com.binwaps.cardmanager

import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.UserEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * اختبارات صيغة أوامر RouterOS — تغطي الأعطال التي أفشلت الرفع فعلياً:
 * حقل الدخول في يوزر منجر v6، والاقتباس، والعميل الإلزامي.
 */
class MikrotikCommandsTest {

    private fun card(
        name: String = "123456",
        password: String = "",
        profile: String = "",
        validity: String = "",
        comment: String = "",
        batchTag: String = "",
    ) = UserEntry(
        username = name, password = password, profile = profile,
        validity = validity, comment = comment, batchTag = batchTag,
    )

    // ===== يوزر منجر =====

    @Test
    fun `v6 يستخدم username لا name`() {
        val cmd = MikrotikClient.umAddCommand(isV7 = false, customer = "admin", u = card("777888"))
        assertTrue("v6 يجب أن يستعمل username", cmd.contains("username=\"777888\""))
        assertFalse("v6 لا يقبل name — كان سبب فشل كل الرفع", cmd.contains(" name="))
        assertTrue("v6 يجب أن يبدأ بمسار /tool", cmd.startsWith("/tool/user-manager/user/add"))
    }

    @Test
    fun `v7 يستخدم name لا username`() {
        val cmd = MikrotikClient.umAddCommand(isV7 = true, customer = "", u = card("777888"))
        assertTrue(cmd.contains("name=\"777888\""))
        assertFalse(cmd.contains("username="))
        assertTrue(cmd.startsWith("/user-manager/user/add"))
    }

    @Test
    fun `v6 يضيف customer دائماً و v7 لا يضيفه`() {
        val v6 = MikrotikClient.umAddCommand(false, "myshop", card())
        assertTrue("customer إلزامي في v6", v6.contains("customer=\"myshop\""))

        val v7 = MikrotikClient.umAddCommand(true, "myshop", card())
        assertFalse("customer لا وجود له في v7", v7.contains("customer="))
    }

    @Test
    fun `الباقة تُربط بأمر منفصل في الإصدارين ولا تُرسل مع add`() {
        // v7: لا group= مع add — الربط عبر جدول user-profile وحده (منع الازدواج)
        val v7 = MikrotikClient.umAddCommand(true, "", card(profile = "شهري 10 جيجا"))
        assertFalse("v7 يجب ألا يرسل group= مع add", v7.contains("group="))

        // v6: الباقة لا تُرسل مع add بل عبر create-and-activate-profile
        val v6 = MikrotikClient.umAddCommand(false, "admin", card(profile = "شهري 10 جيجا"))
        assertFalse(v6.contains("group="))

        val link = MikrotikClient.umLinkProfileCommand(false, "admin", "777888", "شهري 10 جيجا")
        assertTrue(link.contains("create-and-activate-profile"))
        assertTrue(link.contains("customer=\"admin\""))
        assertTrue(link.contains("numbers=\"777888\""))
        assertTrue(link.contains("profile=\"شهري 10 جيجا\""))

        val linkV7 = MikrotikClient.umLinkProfileCommand(true, "", "777888", "شهري 10 جيجا")
        assertTrue(linkV7.startsWith("/user-manager/user-profile/add"))
        assertTrue(linkV7.contains("profile=\"شهري 10 جيجا\""))
    }

    @Test
    fun `ربط الباقة في v7 عبر جدول user-profile`() {
        val link = MikrotikClient.umLinkProfileCommand(true, "", "777888", "باقة")
        assertTrue(link.startsWith("/user-manager/user-profile/add"))
        assertTrue(link.contains("user=\"777888\""))
    }

    // ===== كشف الإصدار الموحّد (umPath) =====

    @Test
    fun `umPath يبني مسار v7 بلا tool ومسار v6 بـ tool`() {
        assertEquals("/user-manager/user", MikrotikClient.umPath(MikrotikClient.UmVariant.V7, "user"))
        assertEquals("/tool/user-manager/user", MikrotikClient.umPath(MikrotikClient.UmVariant.V6, "user"))
        assertEquals(
            "/user-manager/user-profile",
            MikrotikClient.umPath(MikrotikClient.UmVariant.V7, "user-profile"),
        )
        assertEquals(
            "/tool/user-manager/customer",
            MikrotikClient.umPath(MikrotikClient.UmVariant.V6, "customer"),
        )
    }

    @Test
    fun `umPath عند غياب الحزمة يبني مسار v6 ليعطي خطأ مفهوماً`() {
        // NONE = الحزمة غير مثبّتة؛ مسار v6 يُنتج «لا أمر» واضحاً بدل مسار فارغ
        assertEquals("/tool/user-manager/user", MikrotikClient.umPath(MikrotikClient.UmVariant.NONE, "user"))
    }

    // ===== تصنيف اليوزر منجر v6/v7 =====

    private val NOW = 1_800_000_000_000L // مرجع زمني ثابت للاختبار

    @Test
    fun `v6 يقرأ الاستهلاك من سجل المستخدم`() {
        val user = mapOf("download-used" to "500", "upload-used" to "300")
        assertEquals(800L, MikrotikClient.umBytesUsed(MikrotikClient.UmVariant.V6, user, null))
    }

    @Test
    fun `v7 يقرأ الاستهلاك من جدول user-profile لا من حقول v6`() {
        // العطل: قراءة v7 بأسماء v6 كانت تعطي صفراً فيظهر المستهلك UNUSED
        val user = mapOf<String, String>() // v7 لا يحمل العدّادات على سجل المستخدم
        val profile = mapOf("download" to "1000", "upload" to "500")
        assertEquals(1500L, MikrotikClient.umBytesUsed(MikrotikClient.UmVariant.V7, user, profile))
    }

    @Test
    fun `v7 كرت مستهلك يُصنَّف مستخدَماً لا فارغاً`() {
        val user = mapOf<String, String>()
        val profile = mapOf("state" to "running", "download" to "2000")
        assertEquals(
            CardStatus.IN_USE,
            MikrotikClient.classifyUm(MikrotikClient.UmVariant.V7, user, profile, NOW),
        )
    }

    @Test
    fun `المعطّل يُصنَّف معطّلاً في الإصدارين`() {
        val user = mapOf("disabled" to "true")
        assertEquals(CardStatus.DISABLED, MikrotikClient.classifyUm(MikrotikClient.UmVariant.V6, user, null, NOW))
        assertEquals(CardStatus.DISABLED, MikrotikClient.classifyUm(MikrotikClient.UmVariant.V7, user, mapOf("state" to "running"), NOW))
    }

    @Test
    fun `انتهاء الوقت يُصنَّف منتهياً`() {
        val profile = mapOf("end-time" to "jan/01/2020 00:00:00")
        assertEquals(
            CardStatus.EXPIRED,
            MikrotikClient.classifyUm(MikrotikClient.UmVariant.V7, emptyMap(), profile, NOW),
        )
    }

    @Test
    fun `كرت جديد بلا استهلاك يُصنَّف فارغاً`() {
        val user = mapOf("download-used" to "0", "upload-used" to "0")
        assertEquals(
            CardStatus.UNUSED,
            MikrotikClient.classifyUm(MikrotikClient.UmVariant.V6, user, mapOf("state" to "waiting"), NOW),
        )
    }

    // ===== الاقتباس =====

    @Test
    fun `القيم التي فيها مسافات تُقتبس فلا تتقطع`() {
        // بدون اقتباس كان الراوتر يقرأ «شهري» فقط ويرفض الباقي
        val cmd = MikrotikClient.hotspotAddCommand(card(profile = "باقة 10 جيجا"))
        assertTrue(cmd.contains("profile=\"باقة 10 جيجا\""))
    }

    @Test
    fun `الأسطر الجديدة تُزال من القيم`() {
        val cmd = MikrotikClient.hotspotAddCommand(card(comment = "سطر\nثانٍ", batchTag = ""))
        assertFalse("سطر جديد داخل القيمة يكسر محلّل البروتوكول", cmd.contains("\n"))
    }

    @Test
    fun `القيمة التي فيها تنصيص مزدوج تُقتبس بمفرد`() {
        val q = MikrotikClient.q("قيمة \"مقتبسة\"")
        assertTrue("يجب ألا ينكسر الاقتباس", q.startsWith("'") && q.endsWith("'"))
    }

    // ===== الهوتسبوت و PPPoE =====

    @Test
    fun `كرت الهوتسبوت بلا كلمة مرور لا يرسل حقل password`() {
        val cmd = MikrotikClient.hotspotAddCommand(card(password = ""))
        assertFalse(cmd.contains("password="))
        assertTrue(cmd.contains("name=\"123456\""))
    }

    @Test
    fun `وسم الدفعة يُرسل كملاحظة وله أولوية على التعليق`() {
        val cmd = MikrotikClient.hotspotAddCommand(card(comment = "تعليق", batchTag = "vc-260730"))
        assertTrue(cmd.contains("comment=\"vc-260730\""))
    }

    @Test
    fun `أمر PPPoE يحدد الخدمة ويستعمل الباقة المختارة`() {
        val cmd = MikrotikClient.pppAddCommand(card(profile = "باقة الكرت"), profile = "باقة مختارة")
        assertTrue(cmd.startsWith("/ppp/secret/add"))
        assertTrue(cmd.contains("service=pppoe"))
        assertTrue("الباقة الممرّرة تسبق باقة الكرت", cmd.contains("profile=\"باقة مختارة\""))
    }

    @Test
    fun `أمر PPPoE يرجع لباقة الكرت إن لم تُمرَّر باقة`() {
        val cmd = MikrotikClient.pppAddCommand(card(profile = "باقة الكرت"), profile = "")
        assertTrue(cmd.contains("profile=\"باقة الكرت\""))
    }

    @Test
    fun `الأمر لا يحتوي أبداً صيغة المساواة المزدوجة`() {
        // صيغة =key=value خاطئة لهذه المكتبة وكانت تُفشل كل الأوامر
        val cmds = listOf(
            MikrotikClient.hotspotAddCommand(card(password = "1", profile = "p", validity = "30d")),
            MikrotikClient.umAddCommand(false, "admin", card(password = "1")),
            MikrotikClient.pppAddCommand(card(password = "1"), "p"),
        )
        cmds.forEach { assertFalse(it, it.contains("==")) }
        assertEquals(3, cmds.size)
    }
}
