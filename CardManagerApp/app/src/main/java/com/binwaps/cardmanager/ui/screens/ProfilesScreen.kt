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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.HotspotProfile
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.SectionHeader
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
import kotlinx.coroutines.launch

/** إدارة الباقات: جلبها من الهوتسبوت واليوزر منجر، تسعيرها، وإنشاء باقة جديدة */
@Composable
fun ProfilesScreen() {
    val scope = rememberCoroutineScope()
    val profiles by Store.profiles.collectAsState()
    val settings by Store.settings.collectAsState()
    var busy by remember { mutableStateOf(false) }
    var showAdd by remember { mutableStateOf(false) }
    var priceEditing by remember { mutableStateOf<HotspotProfile?>(null) }
    var message by remember { mutableStateOf<Pair<String, Boolean>?>(null) }

    fun refresh() {
        busy = true; message = null
        scope.launch {
            MikrotikClient.fetchProfiles(Store.activeRouter(), foreground = true)
                .onSuccess {
                    Store.setProfiles(it)
                    val hs = it.count { p -> p.source == CardSource.HOTSPOT }
                    val um = it.count { p -> p.source == CardSource.USER_MANAGER }
                    message = "تم جلب ${it.size} باقة — $hs من الهوتسبوت، $um من اليوزر منجر" to false
                }
                .onFailure { message = (it.message ?: "فشل الجلب") to true }
            busy = false
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        SectionHeader("الباقات والأسعار", "${profiles.size} باقة", Icons.Filled.Speed)
        Spacer(Modifier.height(13.dp))

        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            GhostButton("جلب من الراوتر", icon = Icons.Filled.Refresh, enabled = !busy) { refresh() }
            GhostButton("باقة جديدة", icon = Icons.Filled.Add, color = Violet, enabled = !busy) { showAdd = true }
        }

        message?.let { (text, isError) ->
            Spacer(Modifier.height(11.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .background((if (isError) Danger else Lime).copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                    .border(1.dp, (if (isError) Danger else Lime).copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                    .clickable { message = null }
                    .padding(11.dp)
            ) { Text(text, fontSize = 12.sp, color = if (isError) Danger else Lime) }
        }

        Spacer(Modifier.height(16.dp))

        if (profiles.isEmpty()) {
            EmptyState(
                Icons.Filled.Speed, "لا توجد باقات",
                "اضغط \"جلب من الراوتر\" لعرض باقات الهوتسبوت واليوزر منجر",
            )
        } else {
            listOf(CardSource.HOTSPOT, CardSource.USER_MANAGER).forEach { src ->
                val group = profiles.filter { it.source == src }
                if (group.isEmpty()) return@forEach
                Text(
                    if (src == CardSource.HOTSPOT) "باقات الهوتسبوت" else "باقات اليوزر منجر",
                    fontSize = 12.sp, color = TextLow, modifier = Modifier.padding(bottom = 7.dp),
                )
                group.forEach { p ->
                    GlassCard(
                        Modifier.fillMaxWidth().padding(bottom = 8.dp),
                        glow = (if (src == CardSource.HOTSPOT) Lime else Violet).copy(alpha = 0.3f),
                        padding = 13,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier
                                    .size(36.dp)
                                    .background(
                                        (if (src == CardSource.HOTSPOT) Lime else Violet).copy(alpha = 0.12f),
                                        RoundedCornerShape(11.dp),
                                    ),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(
                                    Icons.Filled.Wifi, null,
                                    tint = if (src == CardSource.HOTSPOT) Lime else Violet,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(
                                    buildList {
                                        if (p.rateLimit.isNotBlank()) add("السرعة: ${p.rateLimit}")
                                        if (p.sessionTimeout.isNotBlank()) add("المدة: ${p.sessionTimeout}")
                                        add("أجهزة: ${p.sharedUsers}")
                                    }.joinToString("  •  "),
                                    fontSize = 11.sp, color = TextMid,
                                )
                                Text("${p.userCount} كرت في هذه الباقة", fontSize = 11.5.sp, color = TextLow)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    if (p.price.isBlank()) "بدون سعر" else "${p.price} ${settings.currency}",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (p.price.isBlank()) TextLow else Warn,
                                )
                                if (p.cost.isNotBlank()) {
                                    Text("تكلفة ${p.cost}", fontSize = 11.sp, color = TextLow)
                                }
                                TextButton(onClick = { priceEditing = p }) {
                                    Text("تعديل الأسعار", fontSize = 11.sp, color = Neon)
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
        Spacer(Modifier.height(24.dp))
    }

    priceEditing?.let { p ->
        var price by remember(p.name) { mutableStateOf(p.price) }
        var cost by remember(p.name) { mutableStateOf(p.cost) }
        AlertDialog(
            onDismissRequest = { priceEditing = null },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("أسعار باقة ${p.name}", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    AppField(price, { price = it }, "سعر البيع بـ ${settings.currency}", Modifier.fillMaxWidth(), numeric = true)
                    AppField(cost, { cost = it }, "تكلفة الكرت عليك (لحساب الربح)", Modifier.fillMaxWidth(), numeric = true)
                    val margin = (price.toDoubleOrNull() ?: 0.0) - (cost.toDoubleOrNull() ?: 0.0)
                    if (cost.isNotBlank()) {
                        Text(
                            "ربح الكرت الواحد: ${margin.toLong()} ${settings.currency}",
                            fontSize = 12.5.sp,
                            color = if (margin >= 0) Lime else Danger,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    Store.updateProfilePricing(p.name, price, cost)
                    priceEditing = null
                }) { Text("حفظ", color = Neon, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { priceEditing = null }) { Text("إلغاء", color = TextLow) } },
        )
    }

    if (showAdd) {
        var name by remember { mutableStateOf("") }
        var rate by remember { mutableStateOf("") }
        var timeout by remember { mutableStateOf("") }
        var shared by remember { mutableStateOf("1") }
        var price by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAdd = false },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("باقة جديدة على الراوتر", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    AppField(name, { name = it }, "اسم الباقة", Modifier.fillMaxWidth(), code = true)
                    AppField(rate, { rate = it }, "السرعة (مثال: 2M/2M)", Modifier.fillMaxWidth(), code = true)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppField(timeout, { timeout = it }, "المدة (مثال: 1d)", Modifier.weight(1f), code = true)
                        AppField(shared, { shared = it.filter { c -> c.isDigit() } }, "عدد الأجهزة", Modifier.weight(1f), numeric = true)
                    }
                    AppField(price, { price = it }, "السعر (يُحفظ في التطبيق)", Modifier.fillMaxWidth(), numeric = true)
                    Text(
                        "تُنشأ الباقة في هوتسبوت الراوتر، والسعر يُحفظ داخل التطبيق لأن الراوتر لا يخزّن الأسعار.",
                        fontSize = 11.5.sp, color = TextLow,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (name.isBlank()) return@TextButton
                    val p = HotspotProfile(
                        name = name, rateLimit = rate, sessionTimeout = timeout,
                        sharedUsers = shared, price = price, source = CardSource.HOTSPOT,
                    )
                    showAdd = false
                    busy = true; message = null
                    scope.launch {
                        MikrotikClient.createProfile(Store.activeRouter(), p)
                            .onSuccess {
                                Store.setProfiles(Store.profiles.value + p)
                                Store.updateProfilePrice(p.name, price)
                                message = "تم إنشاء الباقة ${p.name}" to false
                            }
                            .onFailure { message = (it.message ?: "فشل الإنشاء") to true }
                        busy = false
                    }
                }) { Text("إنشاء", color = Neon, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { showAdd = false }) { Text("إلغاء", color = TextLow) } },
        )
    }
}
