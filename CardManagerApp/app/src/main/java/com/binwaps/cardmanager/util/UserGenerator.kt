package com.binwaps.cardmanager.util

import com.binwaps.cardmanager.model.CardMode
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
    ): List<UserEntry> {
        val used = mutableSetOf<String>()
        return (0 until count).map { i ->
            var name: String
            do {
                name = prefix + randomString(length, charset)
            } while (!used.add(name))
            val password = when (mode) {
                // الهوتسبوت يقبل كلمة مرور فارغة عند الدخول بالاسم فقط
                CardMode.USERNAME_ONLY -> ""
                CardMode.SAME -> name
                CardMode.USER_PASS -> randomString(passwordLength, charset)
            }
            UserEntry(
                username = name,
                password = password,
                profile = profile,
                price = price,
                validity = validity,
                serial = (serialStart + i).toString().padStart(4, '0'),
            )
        }
    }

    private fun randomString(length: Int, charset: Charset): String =
        (1..length).map { charset.chars[Random.nextInt(charset.chars.length)] }.joinToString("")
}
