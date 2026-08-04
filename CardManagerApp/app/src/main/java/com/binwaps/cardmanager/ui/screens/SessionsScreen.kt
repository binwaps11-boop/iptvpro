package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.People
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.model.SessionEntry
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.SectionHeader
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class SessionTab(val labelAr: String) {
    ACTIVE("المتصلون الآن"),
    HISTORY("سجل الجلسات"),
    DEVICES("الأجهزة المتصلة"),
}

/**
 * شاشة المتصلين — قسم مستقل كما في برامج الكروت المعروفة:
 * المتصلون الآن مع فصل فوري، سجل الجلسات، والأجهزة المتصلة بالراوتر.
 */
@Composable
fun SessionsScreen() {
    val scope = rememberCoroutineScope()
    val connected by Store.connected.collectAsState()
    val actives by Store.activeUsers.collectAsState()

    var tab by remember { mutableStateOf(SessionTab.ACTIVE) }
    var query by remember { mutableStateOf("") }
    var history by remember { mutableStateOf<List<SessionEntry>>(emptyList()) }
    var devices by remember { mutableStateOf<List<SessionEntry>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // تحديث المتصلين كل 20 ثانية
    LaunchedEffect(connected) {
        while (connected) {
            MikrotikClient.fetchActiveUsers(Store.activeRouter()).onSuccess { Store.setActiveUsers(it) }
            delay(20_000)
        }
    }

    fun load(t: SessionTab) {
        tab = t
        error = null
        if (t == SessionTab.HISTORY && history.isEmpty()) {
            busy = true
            scope.launch {
                // أولوية على المزامنة + مهلة فلا يعلق «جاري الجلب» أبداً
                val res = kotlinx.coroutines.withTimeoutOrNull(40_000) {
                    MikrotikClient.fetchSessionHistory(Store.activeRouter(), foreground = true)
                }
                when {
                    res == null -> error = "الجلب بطيء عبر الشبكة — حاول مجدداً"
                    res.isSuccess -> history = res.getOrNull().orEmpty()
                    else -> error = res.exceptionOrNull()?.message
                }
                busy = false
            }
        }
        if (t == SessionTab.DEVICES && devices.isEmpty()) {
            busy = true
            scope.launch {
                val res = kotlinx.coroutines.withTimeoutOrNull(40_000) {
                    MikrotikClient.fetchConnectedDevices(Store.activeRouter(), foreground = true)
                }
                when {
                    res == null -> error = "الجلب بطيء عبر الشبكة — حاول مجدداً"
                    res.isSuccess -> devices = res.getOrNull().orEmpty()
                    else -> error = res.exceptionOrNull()?.message
                }
                busy = false
            }
        }
    }

    val q = query.trim()
    fun match(s: SessionEntry) = q.isBlank() ||
        s.username.contains(q, true) || s.macAddress.contains(q, true) || s.address.contains(q, true)

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .padding(16.dp),
    ) {
        SectionHeader(
            "المتصلون",
            when (tab) {
                SessionTab.ACTIVE -> "${actives.size} متصل الآن"
                SessionTab.HISTORY -> "${history.size} جلسة"
                SessionTab.DEVICES -> "${devices.size} جهاز"
            },
            Icons.Filled.People,
        )
        Spacer(Modifier.height(11.dp))

        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SessionTab.entries.forEach { t ->
                val on = tab == t
                Text(
                    t.labelAr, fontSize = 12.sp,
                    color = if (on) Neon else TextMid,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier
                        .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                        .clickable { load(t) }
                        .padding(horizontal = 13.dp, vertical = 7.dp),
                )
            }
        }
        Spacer(Modifier.height(9.dp))
        AppField(query, { query = it }, "بحث بالاسم أو MAC أو IP", Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))

        if (busy) Text("جاري الجلب…", fontSize = 12.sp, color = Neon)
        error?.let { Text(it, fontSize = 12.sp, color = Danger) }

        when (tab) {
            SessionTab.ACTIVE -> {
                val shown = actives.filter {
                    q.isBlank() || it.username.contains(q, true) ||
                        it.macAddress.contains(q, true) || it.address.contains(q, true)
                }
                if (shown.isEmpty()) {
                    EmptyState(Icons.Filled.People, "لا يوجد متصلون", "سيظهرون هنا فور اتصالهم بالشبكة")
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(shown.size) { i ->
                            val a = shown[i]
                            GlassCard(Modifier.fillMaxWidth(), padding = 10) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(8.dp).background(Lime, CircleShape))
                                    Spacer(Modifier.width(9.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(a.username, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                        Text(
                                            "${a.uptime}  •  ${a.address}",
                                            fontSize = 10.5.sp, color = TextLow,
                                        )
                                        Text(
                                            "↓ ${formatBytes(a.bytesIn)}   ↑ ${formatBytes(a.bytesOut)}",
                                            fontSize = 10.sp, color = TextMid,
                                        )
                                    }
                                    IconButton(onClick = {
                                        scope.launch {
                                            MikrotikClient.disconnectActive(Store.activeRouter(), a.id)
                                            MikrotikClient.fetchActiveUsers(Store.activeRouter())
                                                .onSuccess { Store.setActiveUsers(it) }
                                        }
                                    }) { Icon(Icons.Filled.LinkOff, "فصل", tint = Danger, modifier = Modifier.size(18.dp)) }
                                }
                            }
                        }
                    }
                }
            }

            SessionTab.HISTORY -> {
                val shown = history.filter(::match)
                if (shown.isEmpty() && !busy) {
                    Column {
                        EmptyState(
                            Icons.Filled.People, "لا يوجد سجل",
                            "السجل يأتي من اليوزر منجر أو من سجل الراوتر",
                        )
                        GhostButton("تفعيل حفظ سجل الهوتسبوت على الراوتر", Modifier.fillMaxWidth()) {
                            scope.launch {
                                MikrotikClient.enableHotspotLogging(Store.activeRouter())
                                    .onSuccess { error = null }
                                    .onFailure { error = it.message }
                            }
                        }
                    }
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(shown.size.coerceAtMost(300)) { i ->
                            val s = shown[i]
                            GlassCard(Modifier.fillMaxWidth(), padding = 10) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(8.dp).background(TextLow, CircleShape))
                                    Spacer(Modifier.width(9.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(s.username, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = TextHi)
                                        Text(
                                            listOf(s.uptime, s.startedAt, s.macAddress)
                                                .filter { it.isNotBlank() }.joinToString("  •  "),
                                            fontSize = 10.sp, color = TextLow,
                                        )
                                        if (s.bytesIn > 0 || s.bytesOut > 0) {
                                            Text(
                                                "↓ ${formatBytes(s.bytesIn)}   ↑ ${formatBytes(s.bytesOut)}",
                                                fontSize = 10.sp, color = TextMid,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SessionTab.DEVICES -> {
                val shown = devices.filter(::match)
                if (shown.isEmpty() && !busy) {
                    EmptyState(Icons.Filled.Devices, "لا توجد أجهزة", "أجهزة الواي فاي وحجوزات DHCP تظهر هنا")
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(shown.size.coerceAtMost(300)) { i ->
                            val d = shown[i]
                            GlassCard(Modifier.fillMaxWidth(), padding = 10) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(
                                        Modifier.size(8.dp)
                                            .background(if (d.active) Lime else TextLow, CircleShape)
                                    )
                                    Spacer(Modifier.width(9.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            d.username.ifBlank { d.macAddress },
                                            fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = TextHi,
                                        )
                                        Text(
                                            listOf(d.address, d.macAddress, d.startedAt)
                                                .filter { it.isNotBlank() }.joinToString("  •  "),
                                            fontSize = 10.sp, color = TextLow,
                                        )
                                    }
                                    Icon(Icons.Filled.Devices, null, tint = Violet, modifier = Modifier.size(17.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
