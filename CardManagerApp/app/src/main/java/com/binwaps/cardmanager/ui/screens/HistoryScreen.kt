package com.binwaps.cardmanager.ui.screens

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.print.PdfExporter
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.components.StatTile
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.NeonGradient
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** سجل الدفعات المطبوعة + تقارير المبيعات + إعادة الطباعة */
@Composable
fun HistoryScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val batches by Store.batches.collectAsState()
    val settings by Store.settings.collectAsState()
    var busy by remember { mutableStateOf(false) }

    val fmt = remember { SimpleDateFormat("yyyy/MM/dd — HH:mm", Locale.US) }

    val cal = remember { Calendar.getInstance() }
    val todayStart = remember {
        Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0)
        }.timeInMillis
    }
    val monthStart = remember {
        Calendar.getInstance().apply {
            set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        }.timeInMillis
    }

    val today = batches.filter { it.createdAt >= todayStart }
    val month = batches.filter { it.createdAt >= monthStart }

    // أعلى الباقات مبيعاً هذا الشهر
    val topProfiles = month
        .filter { it.profile.isNotBlank() }
        .groupBy { it.profile }
        .map { (name, list) -> name to list.sumOf { it.users.size } }
        .sortedByDescending { it.second }
        .take(5)
    val maxSold = topProfiles.maxOfOrNull { it.second } ?: 1

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        SectionHeader("التقارير والسجل", "${batches.size} دفعة محفوظة", Icons.Filled.Analytics)
        Spacer(Modifier.height(14.dp))

        // ملخص المبيعات
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            StatTile("كروت اليوم", today.sumOf { it.users.size }.toString(), Modifier.weight(1f), Neon)
            StatTile("مبيعات اليوم", today.sumOf { it.total }.toLong().toString(), Modifier.weight(1f), Lime, settings.currency)
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            StatTile("كروت الشهر", month.sumOf { it.users.size }.toString(), Modifier.weight(1f), Violet)
            StatTile("مبيعات الشهر", month.sumOf { it.total }.toLong().toString(), Modifier.weight(1f), Warn, settings.currency)
        }

        // الأكثر مبيعاً
        if (topProfiles.isNotEmpty()) {
            Spacer(Modifier.height(18.dp))
            Text("الأكثر مبيعاً هذا الشهر", fontSize = 13.sp, color = TextLow)
            Spacer(Modifier.height(8.dp))
            GlassCard(Modifier.fillMaxWidth()) {
                topProfiles.forEach { (name, sold) ->
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 5.dp)) {
                        Text(name, fontSize = 12.sp, color = TextHi, modifier = Modifier.width(90.dp))
                        Box(
                            Modifier
                                .weight(1f)
                                .height(9.dp)
                                .background(Stroke.copy(alpha = 0.4f), RoundedCornerShape(999.dp))
                        ) {
                            Box(
                                Modifier
                                    .fillMaxWidth(sold.toFloat() / maxSold)
                                    .height(9.dp)
                                    .background(NeonGradient, RoundedCornerShape(999.dp))
                            )
                        }
                        Spacer(Modifier.width(8.dp))
                        Text("$sold", fontSize = 12.sp, color = Neon, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        SectionHeader("سجل الدفعات", null, Icons.Filled.History)
        Spacer(Modifier.height(10.dp))

        if (batches.isEmpty()) {
            EmptyState(Icons.Filled.History, "لا توجد دفعات مطبوعة", "كل دفعة تطبعها تُحفظ هنا لإعادة طباعتها لاحقاً")
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                batches.forEach { b ->
                    GlassCard(Modifier.fillMaxWidth(), padding = 13) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    "${b.users.size} كرت — ${b.templateName}",
                                    fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi,
                                )
                                Text(fmt.format(Date(b.createdAt)), fontSize = 11.sp, color = TextLow)
                                Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    if (b.profile.isNotBlank()) Chip(b.profile, Lime)
                                    if (b.unitPrice.isNotBlank()) Chip("${b.total.toLong()} ${settings.currency}", Warn)
                                    Chip(b.paper.labelAr.take(14), Neon)
                                    if (b.printCount > 1) Chip("طُبعت ${b.printCount}×", Violet)
                                }
                            }
                            Column {
                                IconButton(onClick = {
                                    // إعادة تحميل كروت الدفعة في القائمة الحالية للطباعة
                                    Store.setUsers(b.users)
                                    Toast.makeText(context, "تم تحميل ${b.users.size} كرت — اذهب لتبويب الطباعة", Toast.LENGTH_LONG).show()
                                }) { Icon(Icons.Filled.Restore, "إعادة تحميل", tint = Neon, modifier = Modifier.size(19.dp)) }
                                IconButton(enabled = !busy, onClick = {
                                    val t = Store.template(b.templateId) ?: Store.templates.value.firstOrNull() ?: return@IconButton
                                    busy = true
                                    scope.launch {
                                        val file = withContext(Dispatchers.IO) {
                                            PdfExporter.export(context, t, b.users, Store.settings.value)
                                        }
                                        busy = false
                                        Store.markReprinted(b.id)
                                        PdfExporter.share(context, file)
                                    }
                                }) { Icon(Icons.Filled.Share, "مشاركة PDF", tint = Violet, modifier = Modifier.size(19.dp)) }
                                IconButton(onClick = { Store.deleteBatch(b.id) }) {
                                    Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(19.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Chip(text: String, color: androidx.compose.ui.graphics.Color) {
    Text(
        text,
        fontSize = 10.5.sp,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.11f), RoundedCornerShape(999.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}
