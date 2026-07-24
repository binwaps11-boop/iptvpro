package com.binwaps.cardmanager.ui.screens

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.NeonProgress
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.util.Charset
import com.binwaps.cardmanager.util.CsvImporter
import com.binwaps.cardmanager.util.UserGenerator
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
import kotlinx.coroutines.launch

@Composable
fun UsersScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val users by Store.users.collectAsState()
    val connected by Store.connected.collectAsState()
    var showGenerate by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var busyLabel by remember { mutableStateOf("") }

    val csvPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val imported = CsvImporter.import(context, uri)
            Store.addUsers(imported)
            Toast.makeText(context, "تم استيراد ${imported.size} مستخدم", Toast.LENGTH_LONG).show()
        }
    }

    fun requireRouter(): com.binwaps.cardmanager.model.RouterProfile? {
        val r = Store.activeRouter()
        if (r == null) Toast.makeText(context, "لا يوجد راوتر محفوظ — اتصل أولاً", Toast.LENGTH_LONG).show()
        return r
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .padding(16.dp),
    ) {
        SectionHeader("الكروت والمستخدمون", "${users.size} كرت في القائمة", Icons.Filled.CreditCard)
        Spacer(Modifier.height(14.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f)) {
                NeonButton("توليد كروت", icon = Icons.Filled.AutoAwesome) { showGenerate = true }
            }
            GhostButton("استيراد CSV", icon = Icons.Filled.FileOpen) {
                csvPicker.launch(arrayOf("text/*", "text/csv", "text/comma-separated-values", "application/*"))
            }
        }
        Spacer(Modifier.height(9.dp))
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            GhostButton("جلب الهوتسبوت", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                val r = requireRouter() ?: return@GhostButton
                busy = true; busyLabel = "جاري الجلب من الهوتسبوت…"
                scope.launch {
                    MikrotikClient.fetchHotspotUsers(r)
                        .onSuccess { Store.addUsers(it); Toast.makeText(context, "تم جلب ${it.size} مستخدم", Toast.LENGTH_LONG).show() }
                        .onFailure { Toast.makeText(context, "فشل: ${it.message}", Toast.LENGTH_LONG).show() }
                    busy = false
                }
            }
            GhostButton("جلب اليوزر منجر", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                val r = requireRouter() ?: return@GhostButton
                busy = true; busyLabel = "جاري الجلب من اليوزر منجر…"
                scope.launch {
                    MikrotikClient.fetchUserManagerUsers(r)
                        .onSuccess { Store.addUsers(it); Toast.makeText(context, "تم جلب ${it.size} مستخدم", Toast.LENGTH_LONG).show() }
                        .onFailure { Toast.makeText(context, "فشل: ${it.message}", Toast.LENGTH_LONG).show() }
                    busy = false
                }
            }
            GhostButton("رفع إلى الراوتر", icon = Icons.Filled.CloudUpload, color = Violet, enabled = !busy && users.isNotEmpty()) {
                val r = requireRouter() ?: return@GhostButton
                busy = true; busyLabel = "جاري رفع الكروت إلى الراوتر…"; progress = 0 to users.size
                scope.launch {
                    MikrotikClient.createHotspotUsers(r, users) { d, t -> progress = d to t }
                        .onSuccess { Toast.makeText(context, "تم رفع $it كرت إلى الراوتر", Toast.LENGTH_LONG).show() }
                        .onFailure { Toast.makeText(context, "فشل الرفع: ${it.message}", Toast.LENGTH_LONG).show() }
                    busy = false; progress = null
                }
            }
        }

        if (busy) {
            Spacer(Modifier.height(10.dp))
            Text(busyLabel, fontSize = 12.sp, color = Neon)
            Spacer(Modifier.height(5.dp))
            progress?.let { (d, t) -> NeonProgress(d.toFloat() / t.coerceAtLeast(1)) }
                ?: NeonProgress(0.35f)
        }

        if (!connected) {
            Spacer(Modifier.height(10.dp))
            Text(
                "أنت في الوضع المحلي — الجلب والرفع يحتاجان اتصالاً بالراوتر",
                fontSize = 11.5.sp, color = TextLow,
            )
        }

        Spacer(Modifier.height(14.dp))

        if (users.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("القائمة", fontSize = 13.sp, color = TextLow, modifier = Modifier.weight(1f))
                TextButton(onClick = { Store.clearUsers() }) {
                    Icon(Icons.Filled.Delete, null, tint = Danger, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("مسح الكل", color = Danger, fontSize = 12.sp)
                }
            }
        }

        if (users.isEmpty()) {
            EmptyState(Icons.Filled.CreditCard, "لا توجد كروت بعد", "ولّد دفعة جديدة أو استورد ملف CSV")
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                items(users.size) { i ->
                    val u = users[i]
                    GlassCard(Modifier.fillMaxWidth(), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier
                                    .size(34.dp)
                                    .background(Neon.copy(alpha = 0.10f), RoundedCornerShape(9.dp))
                                    .border(1.dp, Stroke, RoundedCornerShape(9.dp)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    u.serial.ifBlank { (i + 1).toString() },
                                    fontSize = 11.sp, color = Neon, fontWeight = FontWeight.Bold,
                                )
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(u.username, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(
                                    buildList {
                                        add("الرمز: ${u.password}")
                                        if (u.profile.isNotBlank()) add(u.profile)
                                        if (u.price.isNotBlank()) add("${u.price}")
                                        if (u.validity.isNotBlank()) add(u.validity)
                                    }.joinToString("  •  "),
                                    fontSize = 11.sp, color = TextMid,
                                )
                            }
                            IconButton(onClick = { Store.setUsers(users - u) }) {
                                Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
        }
    }

    if (showGenerate) {
        GenerateDialog(onDismiss = { showGenerate = false }) { generated ->
            Store.addUsers(generated)
            showGenerate = false
            Toast.makeText(context, "تم توليد ${generated.size} كرت", Toast.LENGTH_LONG).show()
        }
    }
}

@Composable
private fun GenerateDialog(onDismiss: () -> Unit, onGenerate: (List<UserEntry>) -> Unit) {
    val profiles by Store.profiles.collectAsState()
    var count by remember { mutableStateOf("50") }
    var prefix by remember { mutableStateOf("") }
    var length by remember { mutableStateOf("6") }
    var charset by remember { mutableStateOf(Charset.DIGITS) }
    var samePassword by remember { mutableStateOf(true) }
    var passwordLength by remember { mutableStateOf("4") }
    var profile by remember { mutableStateOf("") }
    var price by remember { mutableStateOf("") }
    var validity by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        titleContentColor = TextHi,
        textContentColor = TextMid,
        shape = RoundedCornerShape(20.dp),
        title = { Text("توليد دفعة كروت", fontWeight = FontWeight.Bold) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppField(count, { count = it.filter { c -> c.isDigit() } }, "عدد الكروت", Modifier.weight(1f), numeric = true)
                    AppField(length, { length = it.filter { c -> c.isDigit() } }, "طول الاسم", Modifier.weight(1f), numeric = true)
                }
                AppField(prefix, { prefix = it }, "بادئة الاسم (اختياري)", Modifier.fillMaxWidth())

                Text("نوع الرموز", fontSize = 12.sp, color = TextLow)
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Charset.entries.forEach { c ->
                        val on = charset == c
                        Text(
                            c.labelAr,
                            fontSize = 11.sp,
                            color = if (on) Neon else TextMid,
                            fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                            modifier = Modifier
                                .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                                .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                                .clickable { charset = c }
                                .padding(horizontal = 11.dp, vertical = 6.dp),
                        )
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        samePassword, { samePassword = it },
                        colors = CheckboxDefaults.colors(checkedColor = Neon, checkmarkColor = com.binwaps.cardmanager.ui.theme.Ink),
                    )
                    Text("كلمة المرور = اسم المستخدم (كرت برمز واحد)", fontSize = 12.sp, color = TextMid)
                }
                if (!samePassword) {
                    AppField(passwordLength, { passwordLength = it.filter { c -> c.isDigit() } }, "طول كلمة المرور", Modifier.fillMaxWidth(), numeric = true)
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppField(price, { price = it }, "السعر", Modifier.weight(1f))
                    AppField(validity, { validity = it }, "الصلاحية (مثل 30d)", Modifier.weight(1f))
                }
                AppField(profile, { profile = it }, "الباقة / البروفايل", Modifier.fillMaxWidth())
                if (profiles.isNotEmpty()) {
                    Row(
                        Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        profiles.forEach { p ->
                            Text(
                                p.name, fontSize = 11.sp, color = Lime,
                                modifier = Modifier
                                    .background(Lime.copy(alpha = 0.10f), RoundedCornerShape(999.dp))
                                    .clickable { profile = p.name; if (p.price.isNotBlank()) price = p.price }
                                    .padding(horizontal = 10.dp, vertical = 5.dp),
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onGenerate(
                    UserGenerator.generate(
                        count = count.toIntOrNull()?.coerceIn(1, 5000) ?: 50,
                        prefix = prefix,
                        length = length.toIntOrNull()?.coerceIn(3, 20) ?: 6,
                        charset = charset,
                        samePassword = samePassword,
                        passwordLength = passwordLength.toIntOrNull()?.coerceIn(3, 20) ?: 4,
                        profile = profile,
                        price = price,
                        validity = validity,
                        serialStart = Store.users.value.size + 1,
                    )
                )
            }) { Text("توليد", color = Neon, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("إلغاء", color = TextLow) } },
    )
}
