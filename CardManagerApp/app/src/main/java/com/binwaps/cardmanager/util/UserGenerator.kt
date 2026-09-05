package com.binwaps.cardmanager.util

import com.binwaps.cardmanager.model.CardMode
import com.binwaps.cardmanager.model.FreeCardRules
import com.binwaps.cardmanager.model.UserEntry
import kotlin.random.Random

enum class Charset(val labelAr: String, val chars: String) {
    DIGITS("أرقام فقط", "0123456789"),
    LOWER("حروف صغيرة", "abcdefghjkmnpqrstuvwxyz"),
    MIXED("أرقام وحروف", "abcdefghjkmnpqrstuvwxyz23456789"),
    UPPER_DIGITS("حروف كبيرة وأرقام", "ABCDEFGHJKMNPQRSTUVWXYZ23456789"),
}

/** توليد دفعة كروت عشوائية */
object UserGenerator {

    /**
     * أدنى عدد خانات يكفي لتوليد [count] رمزاً فريداً براحة.
     * نطلب سعةً تعادل عشرة أضعاف المطلوب: التصادم العشوائي يتضاعف كلما
     * امتلأ الفضاء، وملء 100% منه يعني دوراناً لا ينتهي عملياً.
     */
    fun minLengthFor(count: Int, charset: Charset): Int {
        if (count <= 0) return 1
        val base = charset.chars.length.toDouble()
        var len = 1
        var capacity = base
        while (capacity < count * 10.0 && len < 24) {
            len++
            capacity *= base
        }
        return len
    }

    fun generate(
        count: Int,
        prefix: String,
        length: Int,
        charset: Charset,
        mode: CardMode,
        passwordLength: Int,
        profile: String,
        price: String,
        validity: String,
        serialStart: Int = 1,
        batchTag: String = "",
        freeRules: FreeCardRules = FreeCardRules(),
        /** لاحقة تُضاف بعد الرمز — تُستخدم في أكواد البونص */
        suffix: String = "",
    ): List<UserEntry> {
        // مواضع الكروت المجانية داخل الدفعة
        val freeIdx = freePositions(count, freeRules)
        val used = HashSet<String>(count * 2)
        // توسيع الطول تلقائياً إن كان فضاء الرموز أضيق من العدد المطلوب —
        // بدونه كانت حلقة البحث عن اسم فريد تدور بلا نهاية وتجمّد التطبيق
        val safeLength = maxOf(length, minLengthFor(count, charset))
        return (0 until count).map { i ->
            var name = ""
            var attempts = 0
            // حدّ محاولات ثم لاحقة تسلسلية مضمونة التفرد — لا دوران أبدي
            while (true) {
                name = prefix + randomString(safeLength, charset) + suffix
                if (used.add(name)) break
                if (++attempts >= 60) {
                    name = prefix + randomString(safeLength, charset) + suffix + "-" + (i + 1)
                    used.add(name)
                    break
                }
            }
            val password = when (mode) {
                // الهوتسبوت يقبل كلمة مرور فارغة عند الدخول بالاسم فقط
                CardMode.USERNAME_ONLY -> ""
                CardMode.SAME -> name
                CardMode.USER_PASS -> randomString(passwordLength, charset)
            }
            val free = i in freeIdx
            UserEntry(
                username = name,
                password = password,
                profile = if (free && freeRules.useDifferentProfile && freeRules.freeProfile.isNotBlank())
                    freeRules.freeProfile else profile,
                price = if (free) "" else price,
                validity = validity,
                serial = (serialStart + i).toString().padStart(4, '0'),
                batchTag = batchTag,
                comment = batchTag,
                isFree = free,
            )
        }
    }

    /**
     * يحسب مواضع الكروت المجانية.
     * "كل رقم N" حتمية، والعشوائية إما موزّعة بالتساوي على قطاعات أو حرّة.
     */
    fun freePositions(count: Int, rules: FreeCardRules): Set<Int> {
        if (count <= 0 || !rules.enabled) return emptySet()
        val out = mutableSetOf<Int>()
        if (rules.everyNEnabled && rules.everyN > 0) {
            var i = rules.everyN - 1
            while (i < count) { out.add(i); i += rules.everyN }
        }
        if (rules.randomEnabled && rules.randomCount > 0) {
            val target = rules.randomCount.coerceAtMost(count)
            if (rules.distributeEvenly) {
                // قطاع لكل كرت مجاني، وموضع عشوائي داخل القطاع
                val seg = count.toDouble() / target
                for (k in 0 until target) {
                    val from = (k * seg).toInt()
                    val to = (((k + 1) * seg).toInt() - 1).coerceAtLeast(from)
                    var pos = from + Random.nextInt(to - from + 1)
                    var guard = 0
                    while (pos in out && guard++ < count) pos = (pos + 1) % count
                    out.add(pos)
                }
            } else {
                var guard = 0
                while (out.size < target + (if (rules.everyNEnabled) out.size else 0) && guard++ < count * 4) {
                    out.add(Random.nextInt(count))
                    if (out.size >= target) break
                }
            }
        }
        return out
    }

    private fun randomString(length: Int, charset: Charset): String =
        (1..length).map { charset.chars[Random.nextInt(charset.chars.length)] }.joinToString("")
}
