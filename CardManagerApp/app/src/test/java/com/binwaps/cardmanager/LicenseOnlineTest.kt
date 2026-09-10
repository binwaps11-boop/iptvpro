package com.binwaps.cardmanager

import com.binwaps.cardmanager.license.LicenseCore
import com.binwaps.cardmanager.license.LicenseManager
import com.binwaps.cardmanager.license.LicenseServer
import com.binwaps.cardmanager.license.LicenseState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * اختبارات الطبقة الأونلاين للترخيص — الجزء الذي يقرر من يدخل ومن يُمنع.
 * كلها منطق نقي بلا Context فتعمل على JVM في CI.
 */
class LicenseOnlineTest {

    private val DAY = 86_400_000L

    // ===== حارس الساعة =====

    @Test
    fun `إرجاع الساعة سنة كاملة يُكشف`() {
        val lastSeen = 1_800_000_000_000L
        assertTrue(LicenseManager.rolledBack(lastSeen - 365 * DAY, lastSeen))
    }

    @Test
    fun `الإرجاع الكبير لا يُتجاوز مهما كبر`() {
        // الخلل السابق: أي انحراف يفوق أسبوعاً كان يُقبل ويُمسح المرجع،
        // فيصير إرجاع الساعة عشر سنوات أسهل من إرجاعها يوماً واحداً.
        val lastSeen = 1_800_000_000_000L
        for (years in 1..10) {
            assertTrue(
                "إرجاع $years سنة يجب أن يُكشف",
                LicenseManager.rolledBack(lastSeen - years * 365 * DAY, lastSeen),
            )
        }
    }

    @Test
    fun `فروق الضبط الصغيرة مقبولة`() {
        val lastSeen = 1_800_000_000_000L
        assertFalse(LicenseManager.rolledBack(lastSeen - 3600_000L, lastSeen))
        assertFalse(LicenseManager.rolledBack(lastSeen, lastSeen))
        assertFalse(LicenseManager.rolledBack(lastSeen + DAY, lastSeen))
    }

    @Test
    fun `أول تشغيل بلا مرجع لا يُعتبر إرجاعاً`() {
        assertFalse(LicenseManager.rolledBack(1_000_000L, 0))
    }

    // ===== ترجمة قرار الخادم =====

    @Test
    fun `الرفض نافذ حتى بعد انقضاء مهلة السماح`() {
        // جوهر الحماية: قطع الإنترنت يجب ألا يعيد صلاحية سحبها الخادم
        assertEquals(LicenseState.TrialEnded, LicenseManager.fromOnline("trial_ended", false, "", 0))
        assertEquals(LicenseState.Expired, LicenseManager.fromOnline("expired", false, "", 0))
        assertEquals(LicenseState.Suspended, LicenseManager.fromOnline("blocked", false, "", 0))
        assertEquals(LicenseState.Suspended, LicenseManager.fromOnline("wrong_device", false, "", 0))
    }

    @Test
    fun `القبول تنتهي صلاحيته بانقضاء المهلة`() {
        assertNull(LicenseManager.fromOnline("active", false, "month", 30))
        assertNull(LicenseManager.fromOnline("trial", false, "trial", 5))
    }

    @Test
    fun `القبول الطازج يُترجم لخطة صحيحة`() {
        assertEquals(LicenseState.Trial(5), LicenseManager.fromOnline("trial", true, "trial", 5))
        assertEquals(
            LicenseState.Licensed(LicenseCore.Plan.MONTH, 30, false),
            LicenseManager.fromOnline("active", true, "month", 30),
        )
        assertEquals(
            LicenseState.Licensed(LicenseCore.Plan.YEAR, 300, false),
            LicenseManager.fromOnline("active", true, "year", 300),
        )
    }

    @Test
    fun `الخطة الدائمة لا تنتهي بعدد أيام`() {
        val s = LicenseManager.fromOnline("active", true, "lifetime", 36500)
        assertEquals(LicenseState.Licensed(LicenseCore.Plan.LIFETIME, Int.MAX_VALUE, true), s)
    }

    @Test
    fun `حالة غير معروفة تترك القرار للحساب المحلي`() {
        assertNull(LicenseManager.fromOnline("unknown", true, "", 0))
        assertNull(LicenseManager.fromOnline("", true, "", 0))
        assertNull(LicenseManager.fromOnline("شيء غريب", true, "", 0))
    }

    // ===== تحويل التوقيع =====

    @Test
    fun `توقيع الخادم الخام يُقبل بعد التحويل إلى DER`() {
        // الخادم يوقّع بصيغة P-1363 (٦٤ بايت) وجافا تفهم DER فقط —
        // لو انكسر التحويل رفض التطبيق كل رد صحيح من الخادم.
        val gen = KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        val pair = gen.generateKeyPair()
        val data = "{\"status\":\"active\",\"valid\":true}".toByteArray()

        val signer = Signature.getInstance("SHA256withECDSAinP1363Format")
        signer.initSign(pair.private)
        signer.update(data)
        val raw = signer.sign()
        assertEquals("توقيع P-1363 على P-256 طوله ٦٤ بايت", 64, raw.size)

        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(pair.public)
        verifier.update(data)
        assertTrue(verifier.verify(LicenseServer.rawToDer(raw)))
    }

    @Test
    fun `حمولة معدَّلة تُرفض بعد التحويل`() {
        val gen = KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        val pair = gen.generateKeyPair()

        val signer = Signature.getInstance("SHA256withECDSAinP1363Format")
        signer.initSign(pair.private)
        signer.update("{\"valid\":false}".toByteArray())
        val raw = signer.sign()

        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(pair.public)
        verifier.update("{\"valid\":true}".toByteArray())
        assertFalse("تزوير الحمولة يجب أن يُكشف", verifier.verify(LicenseServer.rawToDer(raw)))
    }

    @Test
    fun `التحويل يتعامل مع الأصفار البادئة والبت الأعلى`() {
        // حالتان تكسران DER الساذج: r يبدأ بأصفار، و s بتُه الأعلى مضبوط
        // فيُقرأ رقماً سالباً. نكرّر توقيعات كثيرة حتى تظهرا طبيعياً.
        val gen = KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        val pair = gen.generateKeyPair()
        var highBitSeen = false
        repeat(60) { i ->
            val data = "payload-$i".toByteArray()
            val signer = Signature.getInstance("SHA256withECDSAinP1363Format")
            signer.initSign(pair.private)
            signer.update(data)
            val raw = signer.sign()
            if (raw[0].toInt() and 0x80 != 0 || raw[32].toInt() and 0x80 != 0) highBitSeen = true
            val verifier = Signature.getInstance("SHA256withECDSA")
            verifier.initVerify(pair.public)
            verifier.update(data)
            assertTrue("فشل التحقق عند التوقيع رقم $i", verifier.verify(LicenseServer.rawToDer(raw)))
        }
        assertTrue("لم تظهر حالة البت الأعلى — الاختبار لم يغطِّ الحالة الحرجة", highBitSeen)
    }
}
