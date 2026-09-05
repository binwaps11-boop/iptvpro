package com.binwaps.cardmanager

import com.binwaps.cardmanager.model.CardMode
import com.binwaps.cardmanager.model.FreeCardRules
import com.binwaps.cardmanager.util.Charset
import com.binwaps.cardmanager.util.UserGenerator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * اختبارات مولّد الكروت — أهمها منع الحلقة اللانهائية التي كانت تجمّد
 * التطبيق أبداً عندما يتجاوز العدد المطلوب فضاء الرموز الممكن.
 */
class UserGeneratorTest {

    private fun gen(
        count: Int,
        length: Int,
        charset: Charset = Charset.DIGITS,
        mode: CardMode = CardMode.SAME,
        prefix: String = "",
        suffix: String = "",
    ) = UserGenerator.generate(
        count = count, prefix = prefix, length = length, charset = charset,
        mode = mode, passwordLength = 4, profile = "", price = "", validity = "",
        suffix = suffix,
    )

    @Test(timeout = 20_000)
    fun `عدد أكبر من فضاء الرموز لا يسبب حلقة لا نهائية`() {
        // 5000 كرت بثلاث خانات = 1000 احتمال فقط — كان يدور للأبد
        val cards = gen(count = 5000, length = 3)
        assertEquals(5000, cards.size)
        assertEquals("كل الأسماء يجب أن تكون فريدة", 5000, cards.map { it.username }.toSet().size)
    }

    @Test(timeout = 20_000)
    fun `عشرة آلاف كرت بأربع خانات تنتهي وتبقى فريدة`() {
        val cards = gen(count = 10_000, length = 4)
        assertEquals(10_000, cards.size)
        assertEquals(10_000, cards.map { it.username }.toSet().size)
    }

    @Test
    fun `الطول يتوسع تلقائياً ليتسع للعدد المطلوب`() {
        // السعة المطلوبة عشرة أضعاف العدد: 1000 كرت ⇒ 10000 احتمال ⇒ 4 خانات
        assertEquals(4, UserGenerator.minLengthFor(1000, Charset.DIGITS))
        // 5000 كرت ⇒ 50000 احتمال ⇒ 5 خانات (10000 لا تكفي)
        assertEquals(5, UserGenerator.minLengthFor(5000, Charset.DIGITS))
        assertEquals(1, UserGenerator.minLengthFor(0, Charset.DIGITS))
        // أبجدية أوسع تحتاج خانات أقل
        assertTrue(
            UserGenerator.minLengthFor(5000, Charset.MIXED) <
                UserGenerator.minLengthFor(5000, Charset.DIGITS),
        )
    }

    @Test
    fun `الطول المطلوب يُحترم إن كان كافياً`() {
        val cards = gen(count = 10, length = 8)
        assertTrue(cards.all { it.username.length == 8 })
    }

    @Test
    fun `البادئة واللاحقة تُطبَّقان`() {
        val cards = gen(count = 20, length = 5, prefix = "A", suffix = "Z")
        assertTrue(cards.all { it.username.startsWith("A") && it.username.endsWith("Z") })
    }

    @Test
    fun `وضع رمز فقط يترك كلمة المرور فارغة`() {
        val cards = gen(count = 10, length = 6, mode = CardMode.USERNAME_ONLY)
        assertTrue(cards.all { it.password.isEmpty() })
    }

    @Test
    fun `وضع متطابق يجعل كلمة المرور نفس الاسم`() {
        val cards = gen(count = 10, length = 6, mode = CardMode.SAME)
        assertTrue(cards.all { it.password == it.username })
    }

    @Test
    fun `وضع مختلف ينتج كلمة مرور مغايرة`() {
        val cards = gen(count = 30, length = 6, mode = CardMode.USER_PASS)
        assertTrue(cards.all { it.password.isNotEmpty() })
        assertTrue("يجب ألا تتطابق كل كلمات المرور مع الأسماء", cards.any { it.password != it.username })
    }

    @Test
    fun `الأرقام فقط لا تحتوي حروفاً`() {
        val cards = gen(count = 50, length = 6, charset = Charset.DIGITS)
        assertTrue(cards.all { it.username.all { c -> c.isDigit() } })
    }

    // ===== الكروت المجانية =====

    @Test
    fun `كل كرت رقم N يُحدَّد مجاناً`() {
        val free = UserGenerator.freePositions(
            30, FreeCardRules(everyNEnabled = true, everyN = 10),
        )
        assertEquals(setOf(9, 19, 29), free)
    }

    @Test
    fun `العدد العشوائي لا يتجاوز عدد الكروت`() {
        val free = UserGenerator.freePositions(
            5, FreeCardRules(randomEnabled = true, randomCount = 50),
        )
        assertTrue(free.size <= 5)
        assertTrue(free.all { it in 0 until 5 })
    }

    @Test
    fun `بلا قواعد لا توجد كروت مجانية`() {
        assertTrue(UserGenerator.freePositions(100, FreeCardRules()).isEmpty())
    }

    @Test
    fun `الكروت المجانية تُوسم ولا تحمل سعراً`() {
        val cards = UserGenerator.generate(
            count = 20, prefix = "", length = 6, charset = Charset.DIGITS,
            mode = CardMode.SAME, passwordLength = 4, profile = "", price = "500",
            validity = "", freeRules = FreeCardRules(everyNEnabled = true, everyN = 5),
        )
        val free = cards.filter { it.isFree }
        assertEquals(4, free.size)
        assertTrue("الكرت المجاني لا يحمل سعراً", free.all { it.price.isEmpty() })
        assertTrue("غير المجاني يحمل السعر", cards.filterNot { it.isFree }.all { it.price == "500" })
    }
}
