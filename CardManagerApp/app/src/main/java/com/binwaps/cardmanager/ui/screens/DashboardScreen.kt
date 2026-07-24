package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Router
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.InfoRow
import com.binwaps.cardmanager.ui.components.NeonProgress
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.components.StatTile
import com.binwaps.cardmanager.ui.components.StatusPill
import com.binwaps.cardmanager.ui.components.formatBytes
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** لوحة التحكم: حالة الراوتر، المتصلون الآن، وإحصائيات المبيعات */
@Composable
fun DashboardScreen(navController: NavController) {
    val scope = rememberCoroutineScope()
    val connected by Store.connected.collectAsState()
    val status by Store.status.collectAsState()
    val actives by Store.activeUsers.collectAsState()
    val users by Store.users.collectAsState()
    val batches by Store.batches.collectAsState()
    val settings by Store.settings.collectAsState()
    var refreshing by remember { mutableStateOf(false) }

    fun refresh() {
        val router = Store.activeRouter() ?: return
        refreshing = true
        scope.launch {
            MikrotikClient.connect(router).onSuccess { Store.setStatus(it); Store.setConnected(true) }
                .onFailure { Store.setConnected(false) }
            MikrotikClient.fetchActiveUsers(router).onSuccess { Store.setActiveUsers(it) }
            refreshing = false
        }
    }

    // تحديث تلقائي كل 20 ثانية
    LaunchedEffect(connected) {
        while (connected) {
            refresh()
            delay(20_000)
        }
    }

    val todayStart = remember {
        java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0); set(java.util.Calendar.SECOND, 0)
        }.timeInMillis
    }
    val todayBatches = batches.filter { it.createdAt >= todayStart }
    val todayCards = todayBatches.sumOf { it.users.size }
    val todayRevenue = todayBatches.sumOf { it.total }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        // رأس الصفحة
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    Store.activeRouter()?.name ?: "غير متصل",
                    fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi,
                )
                Text(
                    Store.activeRouter()?.let { "${it.host}:${it.port}" } ?: "الوضع المحلي",
                    fontSize = 12.sp, color = TextLow,
                )
            }
            StatusPill(connected, if (connected) "متصل" else "غير متصل")
            IconButton(onClick = { refresh() }, enabled = connected && !refreshing) {
                Icon(Icons.Filled.Refresh, "تحديث", tint = if (refreshing) TextLow else Neon)
            }
        }

        // حالة الراوتر
        if (connected) {
            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.4f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(34.dp).background(Neon.copy(alpha = 0.12f), RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Filled.Router, null, tint = Neon, modifier = Modifier.size(18.dp)) }
                    Spacer(Modifier.width(9.dp))
                    Column {
                        Text(status.identity.ifBlank { "الراوتر" }, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextHi)
                        Text(
                            listOf(status.board, status.version).filter { it.isNotBlank() }.joinToString(" • "),
                            fontSize = 11.sp, color = TextLow,
                        )
                    }
                }
                Spacer(Modifier.height(10.dp))
                InfoRow("مدة التشغيل", status.uptime.ifBlank { "—" })
                InfoRow("حِمل المعالج", status.cpuLoad.ifBlank { "—" }.let { if (it == "—") it else "$it%" })
                val free = status.freeMemory.toLongOrNull() ?: 0
                val total = status.totalMemory.toLongOrNull() ?: 0
                if (total > 0) {
                    InfoRow("الذاكرة الحرة", "${formatBytes(free)} من ${formatBytes(total)}")
                    Spacer(Modifier.height(5.dp))
                    NeonProgress(1f - free.toFloat() / total)
                }
            }
        }

        // إحصائيات
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            StatTile("متصل الآن", actives.size.toString(), Modifier.weight(1f), Lime)
            StatTile("كروت جاهزة", users.size.toString(), Modifier.weight(1f), Neon)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            StatTile("مطبوع اليوم", todayCards.toString(), Modifier.weight(1f), Violet)
            StatTile(
                "مبيعات اليوم",
                if (todayRevenue > 0) "${todayRevenue.toLong()}" else "0",
                Modifier.weight(1f), Warn,
                hint = settings.currency,
            )
        }

        // إجراءات سريعة
        Text("إجراءات سريعة", fontSize = 13.sp, color = TextLow)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            QuickAction("كروت جديدة", Icons.Filled.CreditCard, Modifier.weight(1f)) { navController.navigate("users") }
            QuickAction("طباعة", Icons.Filled.Print, Modifier.weight(1f)) { navController.navigate("print") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            QuickAction("القوالب", Icons.Filled.Layers, Modifier.weight(1f)) { navController.navigate("templates") }
            QuickAction("التقارير", Icons.Filled.Analytics, Modifier.weight(1f)) { navController.navigate("history") }
        }

        // المتصلون الآن
        SectionHeader("المتصلون الآن", "${actives.size} مستخدم", Icons.Filled.People)
        if (!connected) {
            EmptyState(Icons.Filled.Router, "غير متصل بالراوتر", "اتصل من الإعدادات لعرض المستخدمين المتصلين")
        } else if (actives.isEmpty()) {
            EmptyState(Icons.Filled.People, "لا يوجد مستخدمون متصلون", "سيظهرون هنا فور اتصالهم بالشبكة")
        } else {
            actives.forEach { a ->
                GlassCard(Modifier.fillMaxWidth(), padding = 11) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).background(Lime, CircleShape))
                        Spacer(Modifier.width(9.dp))
                        Column(Modifier.weight(1f)) {
                            Text(a.username, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextHi)
                            Text(
                                "${a.address}  •  ${a.uptime}",
                                fontSize = 11.sp, color = TextLow,
                            )
                            Text(
                                "↓ ${formatBytes(a.bytesIn)}   ↑ ${formatBytes(a.bytesOut)}",
                                fontSize = 10.5.sp, color = TextMid,
                            )
                        }
                        IconButton(onClick = {
                            val r = Store.activeRouter() ?: return@IconButton
                            scope.launch {
                                MikrotikClient.disconnectActive(r, a.id)
                                MikrotikClient.fetchActiveUsers(r).onSuccess { Store.setActiveUsers(it) }
                            }
                        }) {
                            Icon(Icons.Filled.LinkOff, "فصل", tint = Danger, modifier = Modifier.size(19.dp))
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun QuickAction(label: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .background(Panel, RoundedCornerShape(15.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 15.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, null, tint = Neon, modifier = Modifier.size(23.dp))
        Spacer(Modifier.height(6.dp))
        Text(label, fontSize = 12.sp, color = TextHi, fontWeight = FontWeight.SemiBold)
    }
}
