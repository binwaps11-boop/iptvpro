package com.binwaps.cardmanager

import com.binwaps.cardmanager.util.CsvImporter
import org.junit.Assert.*
import org.junit.Test

class CsvImporterTest {
    @Test fun headerlessUsernamesAreNotMistakenForHeaders() {
        val cards = CsvImporter.parse("user001,p1\nusername002,p2\n")
        assertEquals(listOf("user001", "username002"), cards.map { it.username })
    }
    @Test fun bomAndReorderedHeadersAreSupported() {
        val card = CsvImporter.parse("\uFEFFprofile,username,password,batch\r\nWeekly,001,p,vc-1").single()
        assertEquals("001", card.username)
        assertEquals("Weekly", card.profile)
        assertEquals("vc-1", card.batchTag)
    }
    @Test fun quotedFieldsPreserveQuotesNewlinesAndPasswordSpaces() {
        val card = CsvImporter.parse("username,password,comment\r\n001,\" p\"\"x \",\"سطر أول\r\nسطر, ثانٍ\"").single()
        assertEquals(" p\"x ", card.password)
        assertEquals("سطر أول\r\nسطر, ثانٍ", card.comment)
    }
    @Test fun missingPasswordDoesNotUseAnotherColumn() {
        val card = CsvImporter.parse("username,profile\n001,Weekly").single()
        assertEquals("", card.password)
        assertEquals("Weekly", card.profile)
    }
    @Test fun quotedSeparatorsDoNotChangeDelimiter() {
        val card = CsvImporter.parse("\"u,,,,\";secret").single()
        assertEquals("u,,,,", card.username)
        assertEquals("secret", card.password)
    }
    @Test fun arabicAndTabHeadersWork() {
        assertEquals("p", CsvImporter.parse("اسم المستخدم،كلمة المرور\n001،p").single().password)
        assertEquals("P1", CsvImporter.parse("username\tuserprofname\n001\tP1").single().profile)
    }
    @Test(expected = IllegalArgumentException::class)
    fun unfinishedQuotedFieldIsRejected() { CsvImporter.parse("username,password\n001,\"broken") }
    @Test fun emptyAndBlankRowsAreIgnored() {
        assertTrue(CsvImporter.parse("\uFEFF\r\n\n").isEmpty())
        assertEquals(1, CsvImporter.parse("username,password\r\n,\r\n001,p\r\n").size)
    }
}
