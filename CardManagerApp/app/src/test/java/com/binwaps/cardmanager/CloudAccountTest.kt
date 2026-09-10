package com.binwaps.cardmanager

import com.binwaps.cardmanager.data.CloudAccount
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * الطلب المعلّق هو ما يظهر في لوحة الأدمن. أي خطأ هنا يعني طلباً لا يراه
 * أحد — والمشترك ينتظر موافقة لن تأتي.
 */
class CloudAccountTest {

    private fun acc(
        status: String = "",
        requestState: String = "",
        requestedAt: Long = 0,
        issuedAt: Long = 0,
        key: String = "",
    ) = CloudAccount(
        id = "a@b.com", email = "a@b.com", name = "علي", phone = "776831921",
        deviceCode = "AB12-CD34", status = status, requestState = requestState,
        key = key, planCode = 1, expiresAt = 0, boundDevice = "AB12-CD34",
        renewal = false, requestedAt = requestedAt, issuedAt = issuedAt,
    )

    @Test
    fun `طلب تجديد من مشترك معتمَد يظهر للأدمن`() {
        // العطل السابق: شرط status != "approved" كان يُخفي كل طلبات التجديد،
        // لأن المجدِّد بطبيعته حالته approved من الإصدار السابق
        val renewing = acc(
            status = "approved", requestState = "pending",
            issuedAt = 1_000_000, requestedAt = 2_000_000, key = "KEY",
        )
        assertTrue(renewing.pending)
    }

    @Test
    fun `طلب جديد بلا إصدار سابق يظهر`() {
        assertTrue(acc(requestState = "pending", requestedAt = 5_000).pending)
    }

    @Test
    fun `مشترك معتمَد بلا طلب جديد لا يظهر كطلب`() {
        val settled = acc(
            status = "approved", requestState = "pending",
            requestedAt = 1_000_000, issuedAt = 2_000_000, key = "KEY",
        )
        assertFalse("الإصدار جاء بعد الطلب — بُتّ فيه", settled.pending)
    }

    @Test
    fun `الموقوف لا يظهر في الطلبات مهما طلب`() {
        val blocked = acc(
            status = "suspended", requestState = "pending",
            requestedAt = 9_000_000, issuedAt = 1_000,
        )
        assertFalse(blocked.pending)
    }

    @Test
    fun `الحالة القديمة pending ما زالت مفهومة`() {
        // توافق مع مستندات كُتبت قبل فصل requestState عن status
        assertTrue(acc(status = "pending", requestedAt = 5_000).pending)
    }

    @Test
    fun `المعتمَد يحتاج مفتاحاً فعلياً`() {
        assertFalse("approved بلا مفتاح ليس تفعيلاً", acc(status = "approved").approved)
        assertTrue(acc(status = "approved", key = "ABCD-EFGH").approved)
    }
}
