package com.binwaps.cardmanager

import com.binwaps.cardmanager.mikrotik.MikrotikClient
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
    fun `الباقة في v7 تُرسل كـ group وفي v6 تُربط بأمر منفصل`() {
        val v7 = MikrotikClient.umAddCommand(true, "", card(profile = "شهري 10 جيجا"))
        assertTrue(v7.contains("group=\"شهري 10 جيجا\""))

        // v6: الباقة لا تُرسل مع add بل عبر create-and-activate-profile
        val v6 = MikrotikClient.umAddCommand(false, "admin", card(profile = "شهري 10 جيجا"))
        assertFalse(v6.contains("group="))

        val link = MikrotikClient.umLinkProfileCommand(false, "admin", "777888", "شهري 10 جيجا")
        assertTrue(link.contains("create-and-activate-profile"))
        assertTrue(link.contains("customer=\"admin\""))
        assertTrue(link.contains("numbers=\"777888\""))
        assertTrue(link.contains("profile=\"شهري 10 جيجا\""))
    }

    @Test
    fun `ربط الباقة في v7 عبر جدول user-profile`() {
        val link = MikrotikClient.umLinkProfileCommand(true, "", "777888", "باقة")
        assertTrue(link.startsWith("/user-manager/user-profile/add"))
        assertTrue(link.contains("user=\"777888\""))
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
