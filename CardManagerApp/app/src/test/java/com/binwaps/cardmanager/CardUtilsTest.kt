package com.binwaps.cardmanager

import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.util.CardUtils
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CardUtilsTest {

    private fun u(name: String) = UserEntry(username = name, password = name)

    // ===== عتبة نفاد الكروت =====

    @Test
    fun `تحت العتبة يُنبّه وفوقها لا`() {
        assertTrue(CardUtils.isLowStock(unusedCount = 5, threshold = 10))
        assertTrue("المساواة تُعدّ نفاداً", CardUtils.isLowStock(10, 10))
        assertFalse(CardUtils.isLowStock(11, 10))
    }

    @Test
    fun `النفاد التام يُنبّه والعتبة صفر تُعطّل التنبيه`() {
        assertTrue(CardUtils.isLowStock(0, 10))
        assertFalse("العتبة صفر = معطّل", CardUtils.isLowStock(0, 0))
        assertFalse(CardUtils.isLowStock(3, -1))
    }

    // ===== كشف التكرار =====

    @Test
    fun `يكشف الأسماء الموجودة مسبقاً بلا حساسية للحالة والمسافات`() {
        val existing = listOf(u("Ali01"), u("net-2"))
        val incoming = listOf(u(" ali01 "), u("NEW"), u("NET-2"))
        val dup = CardUtils.duplicateUsernames(incoming, existing)
        assertEquals(setOf("ali01", "net-2"), dup)
    }

    @Test
    fun `يزيل المكرّر من القائمة القائمة ومن داخل الواردة`() {
        val existing = listOf(u("a"))
        val incoming = listOf(u("a"), u("b"), u("b"), u("c"))
        val clean = CardUtils.dropDuplicates(incoming, existing)
        assertEquals(listOf("b", "c"), clean.map { it.username })
    }

    @Test
    fun `بلا تكرار تعود القائمة كما هي`() {
        val incoming = listOf(u("x"), u("y"))
        assertEquals(2, CardUtils.dropDuplicates(incoming, emptyList()).size)
        assertTrue(CardUtils.duplicateUsernames(incoming, emptyList()).isEmpty())
    }
}
