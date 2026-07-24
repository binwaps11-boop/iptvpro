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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CleaningServices
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
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
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn
import kotlinx.coroutines.launch

/** إدارة الباقات: جلبها من الراوتر، تسعيرها، إنشاء باقة جديدة، وتنظيف المنتهية */
@Composable
fun ProfilesScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val profiles by Store.profiles.collectAsState()
    val settings by Store.settings.collectAsState()
    val connected by Store.connected.collectAsState()
    var busy by remember { mutableStateOf(false) }
    var showAdd by remember { mutableStateOf(false) }
    var priceEditing by remember { mutableStateOf<HotspotProfile?>(null) }

    fun refresh() {
        val r = Store.activeRouter() ?: run {
            Toast.makeText(context, "اتصل بالراوتر أولاً", Toast.LENGTH_LONG).show(); return
        }
        busy = true
        scope.launch {
            MikrotikClient.fetchProfiles(r)
                .onSuccess { Store.setProfiles(it); Toast.makeText(context, "تم جلب ${it.size} باقة", Toast.LENGTH_SHORT).show() }
                .onFailure { Toast.makeText(context, "فشل: ${it.message}", Toast.LENGTH_LONG).show() }
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

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            GhostButton("جلب من الراوتر", icon = Icons.Filled.Refresh, enabled = !busy) { refresh() }
            GhostButton("باقة جديدة", icon = Icons.Filled.Add, color = Violet, enabled = !busy) { showAdd = true }
        }
        Spacer(Modifier.height(8.dp))
        GhostButton(
            "حذف المستخدمين المنتهية صلاحيتهم",
            Modifier.fillMaxWidth(),
            icon = Icons.Filled.CleaningServices,
            color = Warn,
            enabled = !busy && connected,
        ) {
            val r = Store.activeRouter() ?: return@GhostButton
            busy = true
            scope.launch {
                MikrotikClient.removeExpiredUsers(r)
                    .onSuccess { Toast.makeText(context, "تم حذف $it مستخدم منتهي", Toast.LENGTH_LONG).show() }
                    .onFailure { Toast.makeText(context, "فشل: ${it.message}", Toast.LENGTH_LONG).show() }
                busy = false
            }
        }

        Spacer(Modifier.height(16.dp))

        if (profiles.isEmpty()) {
            EmptyState(Icons.Filled.Speed, "لا توجد باقات", "اضغط \"جلب من الراوتر\" لعرض باقات الهوتسبوت")
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                profiles.forEach { p ->
                    GlassCard(Modifier.fillMaxWidth(), glow = Lime.copy(alpha = 0.3f), padding = 13) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier.size(36.dp).background(Lime.copy(alpha = 0.12f), RoundedCornerShape(11.dp)),
                                contentAlignment = Alignment.Center,
                            ) { Icon(Icons.Filled.Wifi, null, tint = Lime, modifier = Modifier.size(18.dp)) }
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(
                                    buildList {
                                        if (p.rateLimit.isNotBlank()) add("السرعة: ${p.rateLimit}")
                                        if (p.sessionTimeout.isNotBlank()) add("المدة: ${p.sessionTimeout}")
                                        add("مشاركة: ${p.sharedUsers}")
                                    }.joinToString("  •  "),
                                    fontSize = 11.sp, color = TextMid,
                                )
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    if (p.price.isBlank()) "بدون سعر" else "${p.price} ${settings.currency}",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (p.price.isBlank()) TextLow else Warn,
                                )
                                TextButton(onClick = { priceEditing = p }) {
                                    Text("تعديل السعر", fontSize = 11.sp, color = Neon)
                                }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }

    // حوار تعديل السعر
    priceEditing?.let { p ->
        var price by remember(p.name) { mutableStateOf(p.price) }
        AlertDialog(
            onDismissRequest = { priceEditing = null },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("سعر باقة ${p.name}", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                AppField(price, { price = it }, "السعر بـ ${settings.currency}", Modifier.fillMaxWidth(), numeric = true)
            },
            confirmButton = {
                TextButton(onClick = {
                    Store.updateProfilePrice(p.name, price)
                    priceEditing = null
                }) { Text("حفظ", color = Neon, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { priceEditing = null }) { Text("إلغاء", color = TextLow) } },
        )
    }

    // حوار إنشاء باقة
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
            title = { Text("باقة جديدة", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    AppField(name, { name = it }, "اسم الباقة", Modifier.fillMaxWidth())
                    AppField(rate, { rate = it }, "السرعة (مثال: 2M/2M)", Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppField(timeout, { timeout = it }, "المدة (مثال: 1d)", Modifier.weight(1f))
                        AppField(shared, { shared = it.filter { c -> c.isDigit() } }, "عدد الأجهزة", Modifier.weight(1f), numeric = true)
                    }
                    AppField(price, { price = it }, "السعر (يُحفظ في التطبيق)", Modifier.fillMaxWidth(), numeric = true)
                    Text(
                        "تُنشأ الباقة على الراوتر مباشرة، والسعر يُحفظ داخل التطبيق لأن الراوتر لا يخزّن الأسعار.",
                        fontSize = 10.5.sp, color = TextLow,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val r = Store.activeRouter()
                    if (r == null || name.isBlank()) {
                        Toast.makeText(context, "اتصل بالراوتر وأدخل اسم الباقة", Toast.LENGTH_LONG).show()
                        return@TextButton
                    }
                    val p = HotspotProfile(name = name, rateLimit = rate, sessionTimeout = timeout, sharedUsers = shared, price = price)
                    showAdd = false
                    scope.launch {
                        MikrotikClient.createProfile(r, p)
                            .onSuccess {
                                Store.setProfiles(Store.profiles.value + p)
                                Store.updateProfilePrice(p.name, price)
                                Toast.makeText(context, "تم إنشاء الباقة", Toast.LENGTH_LONG).show()
                            }
                            .onFailure { Toast.makeText(context, "فشل: ${it.message}", Toast.LENGTH_LONG).show() }
                    }
                }) { Text("إنشاء", color = Neon, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { showAdd = false }) { Text("إلغاء", color = TextLow) } },
        )
    }
}
