package com.binwaps.cardmanager

import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.*
import com.binwaps.cardmanager.print.PdfExporter
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class ProductionPlanTest {
    @Test
    fun `نطاق الطباعة وموضع أول خلية يحافظان على ترتيب الكروت`() {
        val cards = (1..20).map { UserEntry(username = "card-$it") }
        val settings = AppSettings(
            printFrom = 3, printTo = 8, startCell = 12, copies = 2,
            layout = PageLayout(autoFit = false, columns = 4, rows = 3),
        )
        val plan = PdfExporter.plan(CardTemplate(1, "test"), cards, settings)
        assertEquals(6, plan.totalCards)
        assertEquals(2, plan.copies)
        assertEquals(2, plan.pages.size)
        assertTrue(plan.pages[0].take(11).all { it == null })
        assertEquals("card-3", plan.pages[0][11]?.username)
        assertEquals(cards.subList(2, 8), plan.pages.flatten().filterNotNull())
        assertEquals(0, plan.cardsBefore(0))
        assertEquals(1, plan.cardsBefore(1))
        assertEquals(6, plan.cardsBefore(2))
    }

    @Test
    fun `قائمة فارغة لا تنتج صفحة حتى مع إزاحة الخلية`() {
        val plan = PdfExporter.plan(CardTemplate(1, "test"), emptyList(), AppSettings(startCell = 6))
        assertEquals(0, plan.totalCards)
        assertTrue(plan.pages.isEmpty())
    }

    @Test
    fun `مهمة الطباعة تحفظ القالب والإعدادات ورقم الطباعة`() {
        val meta = Store.PrintJobMeta(
            kind = "PDF", templateId = 3, next = 12, total = 200, createdAt = 123L,
            cardsFile = "print_job_cards_test-123.json",
            templateSnapshot = CardTemplate(3, "snapshot", widthMm = 50f),
            settingsSnapshot = AppSettings(startCell = 4, offsetXMm = 2.5f, copies = 3),
            printNo = 91, dateText = "2026/09/07", timeText = "15:30",
            pdfParts = listOf(Store.PdfPart("cards_test_0001.pdf", "a".repeat(64), 0, 12)),
        )
        val restored = Json.decodeFromString<Store.PrintJobMeta>(Json.encodeToString(meta))
        assertEquals(meta, restored)
    }

    @Test
    fun `مهمة قديمة دون لقطات تظل قابلة للقراءة`() {
        val restored = Json.decodeFromString<Store.PrintJobMeta>(
            """{"kind":"PDF","templateId":1,"next":5,"total":20,"createdAt":1}""",
        )
        assertEquals("print_job_cards.json", restored.cardsFile)
        assertNull(restored.templateSnapshot)
        assertNull(restored.settingsSnapshot)
        assertEquals(0, restored.printNo)
        assertTrue(restored.pdfParts.isEmpty())
        assertTrue(AppSettings().splitLargePdf)
    }
}
