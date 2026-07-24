package com.binwaps.cardmanager.license

import android.annotation.SuppressLint
import android.content.Context
import android.provider.Settings
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * نظام الترخيص: مفتاح موقّع رقمياً (ECDSA P-256) مربوط بجهاز واحد.
 *
 * - تطبيق المشترك يحمل المفتاح العام فقط ويتحقق من التوقيع، فلا يستطيع توليد تراخيص.
 * - تطبيق الأدمن يحمل المفتاح الخاص ويولّد التراخيص.
 * - الترخيص يحتوي بصمة الجهاز، فلا يعمل على جوال آخر.
 */
object LicenseCore {

    /** المفتاح العام — موجود في التطبيقين */
    const val PUBLIC_KEY_B64 =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE8rdqHVV9w9xPNFTN/TgZzNhggW7i8EfQuszvulAxSmDtl82XXb5twL16gXUu/L8RyflEgS9j8DaD0Q8XBFg+2g=="

    /** بداية حساب أيام الصلاحية: 2026-01-01 */
    private const val EPOCH_DAY_BASE = 20454L // أيام منذ 1970 حتى 2026-01-01
    private const val DAY_MS = 86_400_000L

    private const val PAYLOAD_SIZE = 8 // 5 بصمة + 2 انتهاء + 1 خطة

    /** أبجدية Base32 بدون الأحرف الملتبسة (0/O و1/I) */
    private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    enum class Plan(val code: Int, val labelAr: String) {
        TRIAL(0, "تجريبي"),
        MONTH(1, "شهر"),
        QUARTER(2, "ثلاثة أشهر"),
        YEAR(3, "سنة"),
        LIFETIME(4, "دائم"),
        ;

        companion object {
            fun of(code: Int) = entries.firstOrNull { it.code == code } ?: MONTH
        }
    }

    /** بصمة الجهاز: 5 بايت مشتقة من معرّف أندرويد — تُعرض كـ 8 أحرف */
    @SuppressLint("HardwareIds")
    fun deviceFingerprint(context: Context): ByteArray {
        val androidId = runCatching {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        }.getOrNull().orEmpty().ifBlank { "unknown-device" }
        val seed = "$androidId|cardmanager"
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(seed.toByteArray())
        return digest.copyOf(5)
    }

    /** رمز الجهاز المعروض للمستخدم: XXXX-XXXX */
    fun deviceCode(context: Context): String = formatGroups(base32Encode(deviceFingerprint(context)), 4)

    /** تحويل رمز الجهاز المكتوب يدوياً إلى بصمة */
    fun fingerprintFromCode(code: String): ByteArray? {
        val clean = normalize(code)
        if (clean.length < 8) return null
        val decoded = runCatching { base32Decode(clean.take(8)) }.getOrNull() ?: return null
        return if (decoded.size >= 5) decoded.copyOf(5) else null
    }

    // ===== بناء وقراءة الحمولة =====

    private fun buildPayload(fingerprint: ByteArray, expiryMillis: Long, plan: Plan): ByteArray {
        val days = if (plan == Plan.LIFETIME) 0xFFFF else
            ((expiryMillis / DAY_MS) - EPOCH_DAY_BASE).coerceIn(0, 0xFFFE).toInt()
        return byteArrayOf(
            fingerprint[0], fingerprint[1], fingerprint[2], fingerprint[3], fingerprint[4],
            ((days shr 8) and 0xFF).toByte(),
            (days and 0xFF).toByte(),
            plan.code.toByte(),
        )
    }

    data class LicenseInfo(val expiryMillis: Long, val plan: Plan, val lifetime: Boolean)

    private fun readPayload(payload: ByteArray): LicenseInfo {
        val days = ((payload[5].toInt() and 0xFF) shl 8) or (payload[6].toInt() and 0xFF)
        val plan = Plan.of(payload[7].toInt() and 0xFF)
        val lifetime = days == 0xFFFF || plan == Plan.LIFETIME
        val expiry = if (lifetime) Long.MAX_VALUE else (EPOCH_DAY_BASE + days) * DAY_MS
        return LicenseInfo(expiry, plan, lifetime)
    }

    // ===== توليد الترخيص (تطبيق الأدمن) =====

    fun generate(privateKeyB64: String, deviceCodeText: String, expiryMillis: Long, plan: Plan): String? {
        val fp = fingerprintFromCode(deviceCodeText) ?: return null
        return runCatching {
            val payload = buildPayload(fp, expiryMillis, plan)
            val keySpec = java.security.spec.PKCS8EncodedKeySpec(Base64.getDecoder().decode(privateKeyB64))
            val key = KeyFactory.getInstance("EC").generatePrivate(keySpec)
            val signer = Signature.getInstance("SHA256withECDSA")
            signer.initSign(key)
            signer.update(payload)
            val raw = derToRaw(signer.sign())
            formatGroups(base32Encode(payload + raw), 5)
        }.getOrNull()
    }

    // ===== التحقق (تطبيق المشترك) =====

    fun verify(context: Context, licenseText: String): LicenseInfo? {
        return runCatching {
            val bytes = base32Decode(normalize(licenseText))
            if (bytes.size < PAYLOAD_SIZE + 64) return@runCatching null
            val payload = bytes.copyOfRange(0, PAYLOAD_SIZE)
            val raw = bytes.copyOfRange(PAYLOAD_SIZE, PAYLOAD_SIZE + 64)

            // البصمة يجب أن تطابق هذا الجهاز
            val fp = deviceFingerprint(context)
            var matches = true
            for (i in 0 until 5) if (payload[i] != fp[i]) matches = false
            if (!matches) return@runCatching null

            val keySpec = X509EncodedKeySpec(Base64.getDecoder().decode(PUBLIC_KEY_B64))
            val key = KeyFactory.getInstance("EC").generatePublic(keySpec)
            val verifier = Signature.getInstance("SHA256withECDSA")
            verifier.initVerify(key)
            verifier.update(payload)
            if (!verifier.verify(rawToDer(raw))) return@runCatching null

            readPayload(payload)
        }.getOrNull()
    }

    // ===== أدوات =====

    private fun normalize(s: String) = s.uppercase()
        .replace('O', '0').replace('I', '1').replace('L', '1')
        .filter { it in ALPHABET }

    private fun formatGroups(s: String, size: Int) =
        s.chunked(size).joinToString("-")

    fun base32Encode(data: ByteArray): String {
        val sb = StringBuilder()
        var buffer = 0
        var bits = 0
        for (b in data) {
            buffer = (buffer shl 8) or (b.toInt() and 0xFF)
            bits += 8
            while (bits >= 5) {
                sb.append(ALPHABET[(buffer shr (bits - 5)) and 0x1F])
                bits -= 5
            }
        }
        if (bits > 0) sb.append(ALPHABET[(buffer shl (5 - bits)) and 0x1F])
        return sb.toString()
    }

    fun base32Decode(s: String): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        var buffer = 0
        var bits = 0
        for (c in s) {
            val idx = ALPHABET.indexOf(c)
            if (idx < 0) continue
            buffer = (buffer shl 5) or idx
            bits += 5
            if (bits >= 8) {
                out.write((buffer shr (bits - 8)) and 0xFF)
                bits -= 8
            }
        }
        return out.toByteArray()
    }

    /** تحويل توقيع DER إلى 64 بايت خام (r || s) */
    private fun derToRaw(der: ByteArray): ByteArray {
        var i = 2
        if (der[1].toInt() and 0xFF > 0x80) i = 3
        require(der[i] == 0x02.toByte())
        val rLen = der[i + 1].toInt()
        val r = der.copyOfRange(i + 2, i + 2 + rLen)
        val j = i + 2 + rLen
        require(der[j] == 0x02.toByte())
        val sLen = der[j + 1].toInt()
        val s = der.copyOfRange(j + 2, j + 2 + sLen)
        val out = ByteArray(64)
        val rTrim = r.dropWhile { it == 0.toByte() }.toByteArray()
        val sTrim = s.dropWhile { it == 0.toByte() }.toByteArray()
        System.arraycopy(rTrim, 0, out, 32 - rTrim.size, rTrim.size)
        System.arraycopy(sTrim, 0, out, 64 - sTrim.size, sTrim.size)
        return out
    }

    /** تحويل 64 بايت خام إلى توقيع DER */
    private fun rawToDer(raw: ByteArray): ByteArray {
        fun trim(b: ByteArray): ByteArray {
            var v = b.dropWhile { it == 0.toByte() }.toByteArray()
            if (v.isEmpty()) v = byteArrayOf(0)
            return if (v[0].toInt() and 0x80 != 0) byteArrayOf(0) + v else v
        }
        val r = trim(raw.copyOfRange(0, 32))
        val s = trim(raw.copyOfRange(32, 64))
        val body = byteArrayOf(0x02, r.size.toByte()) + r + byteArrayOf(0x02, s.size.toByte()) + s
        return byteArrayOf(0x30, body.size.toByte()) + body
    }
}
