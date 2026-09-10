package com.binwaps.cardmanager.ui.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.performance.PdfParts
import com.binwaps.cardmanager.print.PdfExporter
import com.binwaps.cardmanager.print.PrintEngine
import com.binwaps.cardmanager.ui.theme.*
import java.io.File

@Composable
fun PdfOutputOptions(split: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            AppChip("تقسيم الدفعات الكبيرة", split) { if (enabled) onChange(true) }
            AppChip("ملف واحد", !split) { if (enabled) onChange(false) }
        }
        Text(if (split) "حتى ${PdfParts.MAX_PHYSICAL_PAGES} صفحة مطبوعة في كل ملف؛ تُحفظ الأجزاء المكتملة لاستكمال الباقي."
            else "ملف يجمع الدفعة كاملة؛ يحتاج ذاكرة أكثر ويُعاد تجهيزه عند الانقطاع.",
            fontSize = 12.sp, color = TextMid)
    }
}

/** Android supports one print dialog at a time. The user chooses each ordered part. */
@Composable
fun PdfDeliveryActions(files: List<File>) {
    if (files.isEmpty()) return
    val context = LocalContext.current
    var choosing by remember(files) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        Text("${files.size} ملف PDF جاهز", fontSize = 13.sp, color = TextMid)
        NeonButton(if (files.size == 1) "مشاركة PDF" else "مشاركة كل الملفات", Modifier.fillMaxWidth()) {
            PdfExporter.shareAll(context, files)
        }
        GhostButton(if (files.size == 1) "طباعة عبر النظام" else "اختيار جزء للطباعة", Modifier.fillMaxWidth()) {
            if (files.size == 1) PdfExporter.printViaSystem(context, files.first()) else choosing = true
        }
    }
    if (choosing) AlertDialog(
        onDismissRequest = { choosing = false }, containerColor = Panel,
        title = { Text("اختر ملف الطباعة", color = TextHi) },
        text = {
            LazyColumn(Modifier.heightIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                itemsIndexed(files, key = { _, file -> file.name }) { index, file ->
                    GhostButton("طباعة الجزء ${index + 1} من ${files.size}", Modifier.fillMaxWidth()) {
                        choosing = false
                        PdfExporter.printViaSystem(context, file)
                    }
                }
            }
        },
        confirmButton = { GhostButton("إغلاق") { choosing = false } },
    )
}

@Composable
fun DiscardPrintJobButton(modifier: Modifier = Modifier) {
    var confirming by remember { mutableStateOf(false) }
    GhostButton("إلغاء المهمة", modifier, color = Danger) { confirming = true }
    if (confirming) ConfirmDialog(
        title = "إلغاء المهمة المحفوظة؟",
        body = "ستُزال نقطة الاستكمال لتتمكن من بدء دفعة جديدة. تبقى الكروت محفوظة في قائمة الكروت.",
        confirmLabel = "إلغاء المهمة",
        onConfirm = { PrintEngine.cancel() },
        onDismiss = { confirming = false },
    )
}
