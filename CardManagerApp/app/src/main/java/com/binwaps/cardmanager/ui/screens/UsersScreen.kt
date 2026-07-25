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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.model.CardMode
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.UploadTarget
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.NeonProgress
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
import com.binwaps.cardmanager.ui.theme.Warn
import com.binwaps.cardmanager.util.Charset
import com.binwaps.cardmanager.util.CsvImporter
import com.binwaps.cardmanager.util.UserGenerator
import kotlinx.coroutines.launch

private enum class CardFilter(val labelAr: String) {
    ALL("الكل"),
    UNUSED("غير مستهلك"),
    IN_USE("قيد الاستخدام"),
    EXPIRED("منتهي"),
    HOTSPOT("هوتسبوت"),
    USER_MANAGER("يوزر منجر"),
    LOCAL("محلي"),
}

@Composable
fun UsersScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val users by Store.users.collectAsState()
    val settings by Store.settings.collectAsState()
    var showGenerate by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var busyLabel by remember { mutableStateOf("") }
    var progress by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var message by remember { mutableStateOf<Pair<String, Boolean>?>(null) } // النص، هل هو خطأ
    var filter by remember { mutableStateOf(CardFilter.ALL) }

    val csvPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val imported = CsvImporter.import(context, uri)
            Store.addUsers(imported)
            message = "تم استيراد ${imported.size} كرت من الملف" to false
        }
    }

    fun run(label: String, block: suspend () -> Result<String>) {
        busy = true; busyLabel = label; message = null
        scope.launch {
            val r = block()
            busy = false; progress = null
            r.onSuccess { message = it to false }
                .onFailure { message = (it.message ?: "فشلت العملية") to true }
        }
    }

    val shown = remember(users, filter) {
        when (filter) {
            CardFilter.ALL -> users
            CardFilter.UNUSED -> users.filter { it.status == CardStatus.UNUSED }
            CardFilter.IN_USE -> users.filter { it.status == CardStatus.IN_USE }
            CardFilter.EXPIRED -> users.filter { it.status == CardStatus.EXPIRED || it.status == CardStatus.DISABLED }
            CardFilter.HOTSPOT -> users.filter { it.source == CardSource.HOTSPOT }
            CardFilter.USER_MANAGER -> users.filter { it.source == CardSource.USER_MANAGER }
            CardFilter.LOCAL -> users.filter { it.source == CardSource.LOCAL }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .padding(16.dp),
    ) {
        SectionHeader("الكروت", "${users.size} كرت — يُعرض ${shown.size}", Icons.Filled.CreditCard)
        Spacer(Modifier.height(12.dp))

        // نوع الكرت
        Text("نوع الكرت", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CardMode.entries.forEach { m ->
                Chip(m.labelAr, settings.cardMode == m) { Store.updateSettings(settings.copy(cardMode = m)) }
            }
        }
        Text(settings.cardMode.hintAr, fontSize = 10.5.sp, color = TextLow, modifier = Modifier.padding(top = 4.dp))

        Spacer(Modifier.height(10.dp))
        Text("مكان الرفع على الراوتر", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            UploadTarget.entries.forEach { t ->
                Chip(t.labelAr, settings.uploadTarget == t) { Store.updateSettings(settings.copy(uploadTarget = t)) }
            }
        }

        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f)) {
                NeonButton("توليد كروت", icon = Icons.Filled.AutoAwesome) { showGenerate = true }
            }
            GhostButton("استيراد CSV", icon = Icons.Filled.FileOpen) {
                csvPicker.launch(arrayOf("text/*", "text/csv", "text/comma-separated-values", "application/*"))
            }
        }

        Spacer(Modifier.height(9.dp))
        Text("جلب من الراوتر", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            GhostButton("كل الكروت", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                run("جاري جلب كل الكروت من الراوتر…") {
                    MikrotikClient.fetchAllCards(Store.activeRouter()).map { list ->
                        Store.setUsers(list)
                        val unused = list.count { it.status == CardStatus.UNUSED }
                        val expired = list.count { it.status == CardStatus.EXPIRED }
                        "تم جلب ${list.size} كرت — $unused غير مستهلك، $expired منتهي"
                    }
                }
            }
            GhostButton("الهوتسبوت", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                run("جاري الجلب من الهوتسبوت…") {
                    MikrotikClient.fetchHotspotUsers(Store.activeRouter()).map { list ->
                        Store.setUsers(list); "تم جلب ${list.size} كرت من الهوتسبوت"
                    }
                }
            }
            GhostButton("اليوزر منجر", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                run("جاري الجلب من اليوزر منجر…") {
                    MikrotikClient.fetchUserManagerUsers(Store.activeRouter()).map { list ->
                        Store.setUsers(list); "تم جلب ${list.size} مستخدم من اليوزر منجر"
                    }
                }
            }
            GhostButton(
                "رفع إلى ${settings.uploadTarget.labelAr}",
                icon = Icons.Filled.CloudUpload, color = Violet,
                enabled = !busy && users.isNotEmpty(),
            ) {
                progress = 0 to users.size
                val target = settings.uploadTarget
                run("جاري الرفع إلى ${target.labelAr}…") {
                    if (target == UploadTarget.USER_MANAGER) {
                        MikrotikClient.createUserManagerUsers(Store.activeRouter(), users) { d, t -> progress = d to t }
                            .map { "تم رفع $it مستخدم إلى اليوزر منجر" }
                    } else {
                        MikrotikClient.createHotspotUsers(Store.activeRouter(), users) { d, t -> progress = d to t }
                            .map { "تم رفع $it كرت إلى الهوتسبوت" }
                    }
                }
            }
            GhostButton("حذف المنتهية", icon = Icons.Filled.Delete, color = Warn, enabled = !busy) {
                run("جاري حذف الكروت المنتهية…") {
                    MikrotikClient.removeExpiredUsers(Store.activeRouter()).map { "تم حذف $it كرت منتهي من الراوتر" }
                }
            }
        }

        if (busy) {
            Spacer(Modifier.height(10.dp))
            Text(busyLabel, fontSize = 12.sp, color = Neon)
            Spacer(Modifier.height(5.dp))
            progress?.let { (d, t) -> NeonProgress(d.toFloat() / t.coerceAtLeast(1)) } ?: NeonProgress(0.4f)
        }

        message?.let { (text, isError) ->
            Spacer(Modifier.height(10.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .background((if (isError) Danger else Lime).copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                    .border(1.dp, (if (isError) Danger else Lime).copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                    .clickable { message = null }
                    .padding(11.dp)
            ) { Text(text, fontSize = 12.sp, color = if (isError) Danger else Lime) }
        }

        Spacer(Modifier.height(12.dp))

        if (users.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                CardFilter.entries.forEach { f ->
                    val count = when (f) {
                        CardFilter.ALL -> users.size
                        CardFilter.UNUSED -> users.count { it.status == CardStatus.UNUSED }
                        CardFilter.IN_USE -> users.count { it.status == CardStatus.IN_USE }
                        CardFilter.EXPIRED -> users.count { it.status == CardStatus.EXPIRED || it.status == CardStatus.DISABLED }
                        CardFilter.HOTSPOT -> users.count { it.source == CardSource.HOTSPOT }
                        CardFilter.USER_MANAGER -> users.count { it.source == CardSource.USER_MANAGER }
                        CardFilter.LOCAL -> users.count { it.source == CardSource.LOCAL }
                    }
                    if (count > 0 || f == CardFilter.ALL) {
                        Chip("${f.labelAr} ($count)", filter == f) { filter = f }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { Store.clearUsers(); message = null }) {
                    Icon(Icons.Filled.Delete, null, tint = Danger, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("إفراغ القائمة", color = Danger, fontSize = 12.sp)
                }
            }
        }

        if (shown.isEmpty()) {
            EmptyState(
                Icons.Filled.CreditCard,
                if (users.isEmpty()) "لا توجد كروت بعد" else "لا كروت بهذا التصنيف",
                if (users.isEmpty()) "ولّد دفعة، أو استورد CSV، أو اجلب الكروت الموجودة من الراوتر" else "جرّب تصنيفاً آخر",
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                items(shown.size) { i ->
                    val u = shown[i]
                    GlassCard(Modifier.fillMaxWidth(), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier
                                    .size(34.dp)
                                    .background(statusColor(u.status).copy(alpha = 0.12f), RoundedCornerShape(9.dp))
                                    .border(1.dp, Stroke, RoundedCornerShape(9.dp)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    u.serial.ifBlank { (i + 1).toString() },
                                    fontSize = 10.5.sp, color = statusColor(u.status), fontWeight = FontWeight.Bold,
                                )
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(u.username, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(
                                    buildList {
                                        if (settings.cardMode == CardMode.USER_PASS && u.password.isNotBlank())
                                            add("الرمز: ${u.password}")
                                        if (u.profile.isNotBlank()) add(u.profile)
                                        if (u.price.isNotBlank()) add("${u.price} ${settings.currency}")
                                        if (u.validity.isNotBlank()) add(u.validity)
                                    }.joinToString("  •  "),
                                    fontSize = 11.sp, color = TextMid,
                                )
                                if (u.uptime.isNotBlank() || u.bytesUsed > 0) {
                                    Text(
                                        buildList {
                                            if (u.uptime.isNotBlank()) add("استُخدم ${u.uptime}")
                                            if (u.bytesUsed > 0) add(formatBytes(u.bytesUsed))
                                        }.joinToString("  •  "),
                                        fontSize = 10.sp, color = TextLow,
                                    )
                                }
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                if (u.status != CardStatus.UNKNOWN) {
                                    Text(
                                        u.status.labelAr, fontSize = 10.sp, color = statusColor(u.status),
                                        modifier = Modifier
                                            .background(statusColor(u.status).copy(alpha = 0.12f), RoundedCornerShape(999.dp))
                                            .padding(horizontal = 8.dp, vertical = 2.dp),
                                    )
                                }
                                Text(u.source.labelAr, fontSize = 9.sp, color = TextLow, modifier = Modifier.padding(top = 3.dp))
                            }
                            IconButton(onClick = { Store.setUsers(users - u) }) {
                                Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(17.dp))
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
            message = "تم توليد ${generated.size} كرت" to false
        }
    }
}

private fun statusColor(s: CardStatus): Color = when (s) {
    CardStatus.UNUSED -> Lime
    CardStatus.IN_USE -> Neon
    CardStatus.EXPIRED -> Danger
    CardStatus.DISABLED -> Warn
    CardStatus.UNKNOWN -> TextMid
}

@Composable
private fun Chip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        label,
        fontSize = 11.5.sp,
        color = if (selected) Neon else TextMid,
        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
        modifier = Modifier
            .background(if (selected) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
            .border(1.dp, if (selected) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun GenerateDialog(onDismiss: () -> Unit, onGenerate: (List<UserEntry>) -> Unit) {
    val profiles by Store.profiles.collectAsState()
    val settings by Store.settings.collectAsState()
    var count by remember { mutableStateOf("50") }
    var prefix by remember { mutableStateOf("") }
    var length by remember { mutableStateOf("6") }
    var charset by remember { mutableStateOf(Charset.DIGITS) }
    var mode by remember { mutableStateOf(settings.cardMode) }
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
                Text("نوع الكرت", fontSize = 12.sp, color = TextLow)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CardMode.entries.forEach { m -> Chip(m.labelAr, mode == m) { mode = m } }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppField(count, { count = it.filter { c -> c.isDigit() } }, "عدد الكروت", Modifier.weight(1f), numeric = true)
                    AppField(length, { length = it.filter { c -> c.isDigit() } }, "عدد الأرقام", Modifier.weight(1f), numeric = true)
                }
                if (mode == CardMode.USER_PASS) {
                    AppField(
                        passwordLength, { passwordLength = it.filter { c -> c.isDigit() } },
                        "عدد أرقام كلمة المرور", Modifier.fillMaxWidth(), numeric = true,
                    )
                }
                AppField(prefix, { prefix = it }, "بادئة الاسم (اختياري)", Modifier.fillMaxWidth())

                Text("نوع الرموز", fontSize = 12.sp, color = TextLow)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Charset.entries.forEach { c -> Chip(c.labelAr, charset == c) { charset = c } }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppField(price, { price = it }, "السعر", Modifier.weight(1f))
                    AppField(validity, { validity = it }, "الصلاحية (30d)", Modifier.weight(1f))
                }
                AppField(profile, { profile = it }, "الباقة / البروفايل", Modifier.fillMaxWidth())
                if (profiles.isNotEmpty()) {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        profiles.forEach { p ->
                            Chip(p.name, profile == p.name) {
                                profile = p.name
                                if (p.price.isNotBlank()) price = p.price
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                Store.updateSettings(Store.settings.value.copy(cardMode = mode))
                onGenerate(
                    UserGenerator.generate(
                        count = count.toIntOrNull()?.coerceIn(1, 5000) ?: 50,
                        prefix = prefix,
                        length = length.toIntOrNull()?.coerceIn(3, 20) ?: 6,
                        charset = charset,
                        mode = mode,
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
