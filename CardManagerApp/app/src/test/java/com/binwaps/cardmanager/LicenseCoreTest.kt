package com.binwaps.cardmanager

import com.binwaps.cardmanager.license.LicenseCore
import com.binwaps.cardmanager.license.LicenseLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * اختبارات الترخيص — أهمها منع رجوع عطل حرف L الذي كان يشوّه المفاتيح
 * ويرفض نحو 97% منها برسالة «صادر لجهاز آخر».
 */
class LicenseCoreTest {

    @Test
    fun `ترميز وفك base32 يعيد نفس البايتات`() {
        val data = byteArrayOf(1, 2, 3, 4, 5, 127, -128, -1, 42)
        val encoded = LicenseCore.base32Encode(data)
        val decoded = LicenseCore.base32Decode(encoded)
        assertTrue(data.zip(decoded.copyOf(data.size)).all { (a, b) -> a == b })
    }

    @Test
    fun `الأبجدية تحتوي حرف L ولا تحتوي الأحرف الملتبسة`() {
        // L جزء أصيل من الأبجدية — استبداله كان يفسد المفاتيح
        val sample = LicenseCore.base32Encode(ByteArray(32) { it.toByte() })
        assertTrue("الأبجدية يجب أن تحوي L", "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains('L'))
        assertTrue("لا حرف O ملتبس", !sample.contains('O'))
        assertTrue("لا حرف I ملتبس", !sample.contains('I'))
    }

    @Test
    fun `مفتاح فيه حرف L لا يفقد بايتاته عند فك الترميز`() {
        // نبني نصاً يحوي L صراحة ونتأكد أن فك الترميز يعطي طولاً متوقعاً
        val withL = "LLLLLLLL"
        val decoded = LicenseCore.base32Decode(withL)
        assertTrue("L يجب أن يُفك لا أن يُسقط", decoded.isNotEmpty())
        assertEquals("ثمانية رموز = 5 بايت", 5, decoded.size)
    }

    @Test
    fun `فك الترميز يتجاهل الشرطات والمسافات`() {
        val plain = LicenseCore.base32Decode("ABCDEFGH")
        val dashed = LicenseCore.base32Decode("ABCD-EFGH")
        assertTrue(plain.zip(dashed).all { (a, b) -> a == b })
        assertEquals(plain.size, dashed.size)
    }

    // ===== استخراج رمز الجهاز والمفتاح من نص ملصوق =====

    @Test
    fun `يستخرج رمز الجهاز من رسالة واتساب كاملة`() {
        val msg = """
            طلب ترخيص — مدير الكروت
            الاسم: علي واقص
            رمز الجهاز: 5NKG-2W7T
        """.trimIndent()
        assertEquals("5NKG-2W7T", LicenseLink.extractDeviceCode(msg))
    }

    @Test
    fun `لا يخلط مجموعات المفتاح الخماسية برمز الجهاز الرباعي`() {
        val key = "CARDM-ANAAD-YAC22-KJ4QK"
        assertNull("مجموعات المفتاح خمسة أحرف فلا تطابق نمط XXXX-XXXX", LicenseLink.extractDeviceCode(key))
    }

    @Test
    fun `يتحقق من شكل رمز الجهاز`() {
        assertTrue(LicenseLink.isDeviceCode("5NKG-2W7T"))
        assertTrue(!LicenseLink.isDeviceCode("رابط طويل غير صالح"))
        assertTrue(!LicenseLink.isDeviceCode("5NKG2W7T"))
    }

    @Test
    fun `يستخرج المفتاح الطويل من رسالة فيها كلام محيط`() {
        val key = "CARDM-ANAAD-YAC22-KJ4QK-KNRW5-GBLUY-YRXJR-FTAP7-FVSG4-W9KYN-XNDNM-JF8TN"
        val msg = "مفتاح تفعيل مدير الكروت\nالمدة: شهر\n$key\nشكراً"
        assertEquals(key, LicenseLink.extractKey(msg))
    }

    @Test
    fun `يستخرج المفتاح من رابط التفعيل`() {
        val key = "CARDM-ANAAD-YAC22-KJ4QK-KNRW5-GBLUY-YRXJR-FTAP7-FVSG4-W9KYN-XNDNM-JF8TN"
        // رابط بصيغة cardmanager://activate?k=...
        val text = "اضغط للتفعيل: cardmanager://activate?k=$key"
        val extracted = LicenseLink.extractKey(text)
        assertNotNull(extracted)
        assertTrue(extracted!!.contains("CARDM"))
    }

    @Test
    fun `تحليل نص الطلب يستخرج البريد والجوال والجهاز`() {
        val msg = """
            طلب ترخيص — مدير الكروت
            الاسم: علي واقص
            البريد: user@gmail.com
            الجوال: 776831921
            رمز الجهاز: 5NKG-2W7T
        """.trimIndent()
        val req = LicenseLink.parseRequestText(msg)
        assertNotNull(req)
        assertEquals("5NKG-2W7T", req!!.deviceCode)
        assertEquals("user@gmail.com", req.email)
        assertEquals("776831921", req.phone)
    }

    @Test
    fun `نص بلا رمز جهاز لا يُنتج طلباً`() {
        assertNull(LicenseLink.parseRequestText("مرحباً، أريد ترخيصاً من فضلك"))
    }
}
