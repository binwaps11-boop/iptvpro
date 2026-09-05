package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Warning
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.ui.components.InfoRow
import com.binwaps.cardmanager.ui.components.NeonProgress
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

/**
 * الرئيسية — على نمط برامج الكروت المعروفة:
 * حالة الراوتر في الأعلى، صف عدادات، ثم شبكة أقسام كبيرة.
 */
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
    var statsBusy by remember { mutableStateOf(false) }
    var vitalsOpen by remember { mutableStateOf(false) }

    /** جلب عدادات الكروت — عملية ثقيلة تُطلب يدوياً أو مرة عند الدخول */
    fun refreshStats() {
        if (statsBusy) return
        statsBusy = true
        scope.launch {
            MikrotikClient.fetchCardStats(Store.activeRouter()).onSuccess { Store.setStatus(it) }
            statsBusy = false
        }
    }

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

    // التحديث الدوري كله يتولاه SyncEngine منذ فتح التطبيق — لا حلقة هنا

    // يُحسب في كل إعادة تركيب — remember كان يترك "اليوم" على يوم أمس بعد منتصف الليل
    val todayStart = java.util.Calendar.getInstance().apply {
        set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
        set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
    }.timeInMillis
    val sales by Store.sales.collectAsState()
    val todayRevenue = remember(sales, todayStart) {
        sales.filter { it.at >= todayStart && it.kind == com.binwaps.cardmanager.model.SaleKind.SALE }.sumOf { it.total }
    }

    fun n(v: Int) = if (v < 0) "…" else v.toString()

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // الرأس
        val connectError by com.binwaps.cardmanager.data.SyncEngine.connectError.collectAsState()
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    Store.activeRouter()?.name ?: "غير متصل",
                    fontSize = 20.sp, fontWeight = FontWeight.Bold, color = TextHi,
                )
                Text(
                    Store.activeRouter()?.let { "${it.host}:${it.port}" } ?: "الوضع المحلي",
                    fontSize = 11.5.sp, color = TextLow,
                )
            }
            // «جاري الاتصال…» أثناء الاتصال التلقائي بدل «غير متصل» الصامتة، والسبب عند الفشل
            val autoConnecting = !connected && connectError == null &&
                Store.activeRouter() != null && com.binwaps.cardmanager.data.SyncEngine.isRunning()
            StatusPill(connected, if (connected) "متصل" else if (autoConnecting) "جاري الاتصال…" else "غير متصل")
            IconButton(onClick = { refresh() }, enabled = connected && !refreshing) {
                Icon(Icons.Filled.Refresh, "تحديث", tint = if (refreshing) TextLow else Neon)
            }
        }
        if (!connected && connectError != null) {
            GlassCard(Modifier.fillMaxWidth(), glow = Danger.copy(alpha = 0.35f), padding = 10) {
                Text(
                    "تعذّر الاتصال بالراوتر: $connectError",
                    fontSize = 12.5.sp, color = TextHi, lineHeight = 19.sp,
                )
                Text(
                    "تُعاد المحاولة تلقائياً كل ١٥ ثانية. لتغيير العنوان أو كلمة المرور افتح «الإعدادات ← الراوتر».",
                    fontSize = 11.5.sp, color = TextMid, lineHeight = 17.sp,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }

        // حالة الراوتر — سطران وقابلة للتوسيع
        if (connected) {
            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 12) {
                Row(
                    Modifier.clickable { vitalsOpen = !vitalsOpen },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Router, null, tint = Neon, modifier = Modifier.size(19.dp))
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            status.identity.ifBlank { "الراوتر" },
                            fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi,
                        )
                        Text(
                            listOf(status.board, status.version, status.uptime)
                                .filter { it.isNotBlank() }.joinToString(" • "),
                            fontSize = 11.5.sp, color = TextLow,
                        )
                    }
                    Icon(
                        if (vitalsOpen) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                        null, tint = TextLow, modifier = Modifier.size(20.dp),
                    )
                }
                if (vitalsOpen) {
                    Spacer(Modifier.height(8.dp))
                    InfoRow("حِمل المعالج", status.cpuLoad.ifBlank { "—" }.let { if (it == "—") it else "$it%" })
                    val free = status.freeMemory.toLongOrNull() ?: 0
                    val total = status.totalMemory.toLongOrNull() ?: 0
                    if (total > 0) {
                        InfoRow("الذاكرة الحرة", "${formatBytes(free)} من ${formatBytes(total)}")
                        Spacer(Modifier.height(4.dp))
                        NeonProgress(1f - free.toFloat() / total)
                    }
                    Spacer(Modifier.height(6.dp))
                    InfoRow("إجمالي كروت الهوتسبوت", n(status.hotspotUsers))
                    InfoRow("مستخدمو اليوزر منجر", n(status.userManagerUsers))
                    Text(
                        if (statsBusy) "جاري العدّ…" else "تحديث العدادات",
                        fontSize = 11.5.sp, color = if (statsBusy) TextLow else Neon,
                        modifier = Modifier.clickable(enabled = !statsBusy) { refreshStats() }.padding(4.dp),
                    )
                }
            }
        }

        // صف العدادات
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            MiniStat("متصل الآن", actives.size.toString(), Lime, Modifier.weight(1f))
            MiniStat(
                "غير مستهلكة",
                if (status.hotspotUsers < 0) "…" else status.unusedUsers.toString(),
                Neon, Modifier.weight(1f),
            )
            MiniStat("مستهلكة", n(status.usedUsers), Warn, Modifier.weight(1f))
            MiniStat("مبيعات اليوم", com.binwaps.cardmanager.util.Ledger.money(todayRevenue), Violet, Modifier.weight(1f))
        }

        // تنبيهات — باقات على وشك النفاد، وديون معلّقة
        run {
            val threshold = settings.lowStockThreshold
            // remember: الشاشة تُعاد تركيبها كل دورة مزامنة (حالة الراوتر تتغيّر)،
            // وتجميع عشرات آلاف الكروت على الخيط الرئيسي كل ١٥ ثانية كان تجمّداً محسوساً
            val lowProfiles = remember(users, threshold) {
                users
                    .filter { it.status == com.binwaps.cardmanager.model.CardStatus.UNUSED && it.profile.isNotBlank() }
                    .groupingBy { it.profile }.eachCount()
                    // العتبة صفر تعطّل التنبيه بدل إظهار باقات فارغة بلا داعٍ
                    .filter { com.binwaps.cardmanager.util.CardUtils.isLowStock(it.value, threshold) }
                    .toList().sortedBy { it.second }
            }
            // لكل زبون على حدة — الدفعة الزائدة لزبون لا تُخفي دين زبون آخر
            val openDebt = com.binwaps.cardmanager.util.Ledger.totalDebt(sales)
            if (lowProfiles.isNotEmpty() || openDebt > 0) {
                GlassCard(Modifier.fillMaxWidth(), glow = Warn.copy(alpha = 0.3f), padding = 12) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Warning, null, tint = Warn, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(7.dp))
                        Text("تنبيهات", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                    }
                    lowProfiles.take(4).forEach { (profile, count) ->
                        Text(
                            "الباقة $profile — بقي منها $count كرت غير مستهلك",
                            fontSize = 11.5.sp, color = Warn, modifier = Modifier.padding(top = 5.dp),
                        )
                    }
                    if (openDebt > 0) {
                        Text(
                            "ديون غير مسدّدة: ${com.binwaps.cardmanager.util.Ledger.money(openDebt)} ${settings.currency}",
                            fontSize = 11.5.sp, color = Danger, modifier = Modifier.padding(top = 5.dp),
                        )
                    }
                }
            }
        }

        // مركز الوجهات الثانوية: الكروت/القوالب/الطباعة/الإعدادات في الشريط
        // السفلي، وهنا ما لا مكان له فيه — بلا تكرار بينهما.
        Text("عملية سريعة", fontSize = 13.sp, color = TextLow)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            HomeTile("توليد وطباعة ورفع ⚡", Icons.Filled.AutoAwesome, Neon, null, Modifier.weight(1f)) {
                navController.navigate("express")
            }
            HomeTile("المتصلون الآن", Icons.Filled.People, Neon, actives.size.takeIf { it > 0 }, Modifier.weight(1f)) {
                navController.navigate("active")
            }
        }

        Spacer(Modifier.height(6.dp))
        Text("الإدارة والتقارير", fontSize = 13.sp, color = TextLow)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            HomeTile("الباقات والأسعار", Icons.Filled.Speed, Lime, null, Modifier.weight(1f)) {
                navController.navigate("profiles")
            }
            HomeTile("التقارير", Icons.Filled.Analytics, Warn, null, Modifier.weight(1f)) {
                navController.navigate("reports")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            HomeTile("المبيعات والصندوق", Icons.Filled.Payments, Lime, null, Modifier.weight(1f)) {
                navController.navigate("sales")
            }
            HomeTile("سجل الدفعات", Icons.Filled.History, Violet, batches.size.takeIf { it > 0 }, Modifier.weight(1f)) {
                navController.navigate("history")
            }
        }

        Spacer(Modifier.height(6.dp))
        Text("النظام", fontSize = 13.sp, color = TextLow)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            HomeTile("إدارة الراوتر", Icons.Filled.Router, Neon, null, Modifier.weight(1f)) {
                navController.navigate("router")
            }
            HomeTile("الترخيص", Icons.Filled.VerifiedUser, TextMid, null, Modifier.weight(1f)) {
                navController.navigate("license")
            }
        }
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun MiniStat(label: String, value: String, accent: Color, modifier: Modifier) {
    Column(
        modifier
            .background(Panel, RoundedCornerShape(13.dp))
            .border(1.dp, accent.copy(alpha = 0.35f), RoundedCornerShape(13.dp))
            .padding(vertical = 10.dp, horizontal = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = accent)
        Text(label, fontSize = 11.sp, color = TextLow)
    }
}

@Composable
private fun HomeTile(
    label: String,
    icon: ImageVector,
    accent: Color,
    badge: Int?,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier
            .background(Panel, RoundedCornerShape(16.dp))
            .border(1.dp, Stroke, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 17.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.TopEnd) {
            Box(
                Modifier
                    .size(46.dp)
                    .background(accent.copy(alpha = 0.13f), RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center,
            ) { Icon(icon, null, tint = accent, modifier = Modifier.size(24.dp)) }
            if (badge != null) {
                Text(
                    if (badge > 999) "999+" else badge.toString(),
                    fontSize = 11.sp, fontWeight = FontWeight.Bold, color = com.binwaps.cardmanager.ui.theme.Ink,
                    modifier = Modifier
                        .padding(top = 0.dp)
                        .background(accent, RoundedCornerShape(999.dp))
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
    }
}
