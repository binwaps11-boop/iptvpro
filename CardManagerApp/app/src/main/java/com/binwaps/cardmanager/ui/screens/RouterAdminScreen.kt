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
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.binwaps.cardmanager.mikrotik.DhcpLease
import com.binwaps.cardmanager.mikrotik.InterfaceStat
import com.binwaps.cardmanager.mikrotik.IpBinding
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.ui.components.AppField
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
import java.util.Locale

private enum class AdminTab(val labelAr: String) {
    DIAG("فحص شامل"),
    PPP("PPPoE"),
    DEVICES("أجهزة الشبكة"),
    INTERFACES("المنافذ والحركة"),
    BLOCKED("الحجب والسماح"),
    SYSTEM("النظام"),
}

/**
 * إدارة الراوتر — أجهزة الشبكة (DHCP)، حركة المنافذ، حجب الأجهزة بعنوانها الفيزيائي،
 * والخدمات والنسخ الاحتياطي وإعادة التشغيل.
 */
@Composable
fun RouterAdminScreen() {
    val routers by Store.routers.collectAsState()
    val settings by Store.settings.collectAsState()
    val router = routers.firstOrNull { it.id == settings.activeRouterId } ?: routers.firstOrNull()
    val scope = rememberCoroutineScope()

    var tab by remember { mutableStateOf(AdminTab.DEVICES) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }

    var leases by remember { mutableStateOf<List<DhcpLease>>(emptyList()) }
    var interfaces by remember { mutableStateOf<List<InterfaceStat>>(emptyList()) }
    var bindings by remember { mutableStateOf<List<IpBinding>>(emptyList()) }
    var services by remember { mutableStateOf<List<Triple<String, String, Boolean>>>(emptyList()) }
    var confirmReboot by remember { mutableStateOf(false) }
    var diag by remember { mutableStateOf<List<MikrotikClient.DiagLine>>(emptyList()) }
    var ppp by remember { mutableStateOf<List<MikrotikClient.PppSecret>>(emptyList()) }
    var pppProfiles by remember { mutableStateOf<List<String>>(emptyList()) }
    var pppUploadProfile by remember { mutableStateOf("") }
    var bindOn by remember { mutableStateOf<Boolean?>(null) }
    var macToAdd by remember { mutableStateOf("") }
    var macNote by remember { mutableStateOf("") }

    // رقم جيل لكل تحديث — استجابة قديمة بطيئة لا تكتب فوق بيانات أحدث
    var refreshGen by remember { mutableStateOf(0) }

    fun refresh() {
        if (router == null) {
            message = "لا يوجد راوتر — اتصل أولاً من شاشة الاتصال"
            return
        }
        val gen = ++refreshGen
        busy = true
        message = ""
        scope.launch {
            fun fresh() = gen == refreshGen
            when (tab) {
                AdminTab.DEVICES -> MikrotikClient.fetchDhcpLeases(router)
                    .onSuccess { if (fresh()) leases = it }
                    .onFailure { if (fresh()) message = it.message.orEmpty() }
                AdminTab.INTERFACES -> MikrotikClient.fetchInterfaces(router)
                    .onSuccess { if (fresh()) interfaces = it.sortedByDescending { s -> s.rxBytes + s.txBytes } }
                    .onFailure { if (fresh()) message = it.message.orEmpty() }
                AdminTab.BLOCKED -> MikrotikClient.fetchIpBindings(router)
                    .onSuccess { if (fresh()) bindings = it }
                    .onFailure { if (fresh()) message = it.message.orEmpty() }
                AdminTab.SYSTEM -> {
                    MikrotikClient.fetchServices(router)
                        .onSuccess { if (fresh()) services = it }
                        .onFailure { if (fresh()) message = it.message.orEmpty() }
                    MikrotikClient.isBindFirstDeviceOn(router).onSuccess { if (fresh()) bindOn = it }
                }
                AdminTab.DIAG -> MikrotikClient.diagnose(router)
                    .onSuccess { if (fresh()) diag = it }
                    .onFailure { if (fresh()) message = it.message.orEmpty() }
                AdminTab.PPP -> {
                    MikrotikClient.fetchPppSecrets(router)
                        .onSuccess { if (fresh()) ppp = it }
                        .onFailure { if (fresh()) message = it.message.orEmpty() }
                    MikrotikClient.fetchPppProfiles(router).onSuccess {
                        if (fresh()) {
                            pppProfiles = it
                            if (pppUploadProfile.isBlank()) pppUploadProfile = it.firstOrNull().orEmpty()
                        }
                    }
                }
            }
            if (fresh()) busy = false
        }
    }

    LaunchedEffect(tab, router?.id) { refresh() }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                SectionHeader("إدارة الراوتر", router?.name ?: "غير متصل", Icons.Filled.Settings)
            }
            IconButton(onClick = { refresh() }) {
                Icon(Icons.Filled.Refresh, "تحديث", tint = if (busy) TextLow else Neon)
            }
        }
        Spacer(Modifier.height(12.dp))

        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            AdminTab.entries.forEach { t ->
                val on = tab == t
                Text(
                    t.labelAr,
                    fontSize = 11.5.sp,
                    color = if (on) Neon else TextMid,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier
                        .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                        .clickable { tab = t }
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                )
            }
        }

        if (message.isNotBlank()) {
            Spacer(Modifier.height(10.dp))
            Text(message, fontSize = 11.5.sp, color = Danger)
        }
        if (busy) {
            Spacer(Modifier.height(10.dp))
            Text("جاري القراءة من الراوتر…", fontSize = 11.5.sp, color = TextLow)
        }
        Spacer(Modifier.height(12.dp))

        when (tab) {
            AdminTab.DIAG -> {
                Text(
                    "يجري أوامر خام على الراوتر ويعرض ردّه الحقيقي على كلٍّ منها — " +
                        "أرسل لقطة من هذه الشاشة عند أي مشكلة في العدادات أو الجلب",
                    fontSize = 11.sp, color = TextLow,
                )
                Spacer(Modifier.height(9.dp))
                diag.forEach { d ->
                    GlassCard(Modifier.fillMaxWidth().padding(bottom = 7.dp), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                if (d.ok) "✓" else "✗",
                                fontSize = 14.sp, fontWeight = FontWeight.Bold,
                                color = if (d.ok) Lime else Danger,
                            )
                            Spacer(Modifier.width(9.dp))
                            Column(Modifier.weight(1f)) {
                                Text(d.label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(d.value, fontSize = 11.sp, color = if (d.ok) TextMid else Danger)
                            }
                        }
                    }
                }
                if (diag.isEmpty() && !busy) {
                    Text("اضغط زر التحديث أعلاه لبدء الفحص", fontSize = 11.5.sp, color = TextLow)
                }
            }

            AdminTab.PPP -> {
                val pending = Store.users.collectAsState().value
                    .filter { it.routerId.isBlank() && !it.uploaded }
                Text(
                    "${ppp.size} حساب PPPoE — ${ppp.count { it.active }} متصل الآن",
                    fontSize = 11.5.sp, color = TextLow,
                )
                Spacer(Modifier.height(9.dp))
                if (pending.isNotEmpty()) {
                    if (pppProfiles.isNotEmpty()) {
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            pppProfiles.forEach { p ->
                                Text(
                                    p, fontSize = 11.sp,
                                    color = if (pppUploadProfile == p) Neon else TextMid,
                                    modifier = Modifier
                                        .background(if (pppUploadProfile == p) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                                        .border(1.dp, if (pppUploadProfile == p) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                                        .clickable { pppUploadProfile = p }
                                        .padding(horizontal = 11.dp, vertical = 6.dp),
                                )
                            }
                        }
                        Spacer(Modifier.height(7.dp))
                    }
                    GhostButton("رفع ${pending.size} كرت كحسابات PPPoE", Modifier.fillMaxWidth(), enabled = !busy) {
                        val r0 = router ?: return@GhostButton
                        busy = true; message = ""
                        scope.launch {
                            val created = java.util.Collections.synchronizedList(mutableListOf<String>())
                            MikrotikClient.createPppSecrets(
                                r0, pending, pppUploadProfile,
                                onCreated = { created.add(it.username) },
                            ).onSuccess {
                                Store.markUploaded(created)
                                message = "تم رفع $it حساب PPPoE"
                            }.onFailure { message = it.message.orEmpty() }
                            busy = false
                            refresh()
                        }
                    }
                    Spacer(Modifier.height(9.dp))
                }
                ppp.forEach { s ->
                    GlassCard(Modifier.fillMaxWidth().padding(bottom = 7.dp), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(s.name, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(
                                    buildList {
                                        if (s.profile.isNotBlank()) add(s.profile)
                                        if (s.active) add("متصل ${s.activeUptime} — ${s.activeAddress}")
                                        else if (s.disabled) add("معطّل")
                                        else add("غير متصل")
                                    }.joinToString("  •  "),
                                    fontSize = 10.5.sp,
                                    color = if (s.active) Lime else if (s.disabled) Danger else TextLow,
                                )
                            }
                            if (s.active) {
                                Text(
                                    "فصل", fontSize = 11.sp, color = Warn, fontWeight = FontWeight.Bold,
                                    modifier = Modifier
                                        .background(Warn.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
                                        .clickable {
                                            val r0 = router ?: return@clickable
                                            scope.launch {
                                                MikrotikClient.disconnectPppActive(r0, s.name)
                                                    .onFailure { message = it.message.orEmpty() }
                                                refresh()
                                            }
                                        }
                                        .padding(horizontal = 11.dp, vertical = 5.dp),
                                )
                                Spacer(Modifier.width(6.dp))
                            }
                            Text(
                                if (s.disabled) "تفعيل" else "تعطيل",
                                fontSize = 11.sp,
                                color = if (s.disabled) Lime else TextMid,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .background(Panel, RoundedCornerShape(999.dp))
                                    .border(1.dp, Stroke, RoundedCornerShape(999.dp))
                                    .clickable {
                                        val r0 = router ?: return@clickable
                                        scope.launch {
                                            MikrotikClient.setPppSecretDisabled(r0, s.id, !s.disabled)
                                                .onFailure { message = it.message.orEmpty() }
                                            refresh()
                                        }
                                    }
                                    .padding(horizontal = 11.dp, vertical = 5.dp),
                            )
                        }
                    }
                }
                if (ppp.isEmpty() && !busy) {
                    Text("لا توجد حسابات PPPoE على هذا الراوتر", fontSize = 11.5.sp, color = TextLow)
                }
            }

            AdminTab.DEVICES -> {
                Text("${leases.size} جهاز حصل على عنوان من الراوتر", fontSize = 11.5.sp, color = TextLow)
                Spacer(Modifier.height(8.dp))
                leases.forEach { l ->
                    GlassCard(Modifier.fillMaxWidth().padding(bottom = 8.dp), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Filled.Devices, null,
                                tint = if (l.status == "bound") Lime else TextLow,
                                modifier = Modifier.size(20.dp),
                            )
                            Spacer(Modifier.width(9.dp))
                            Column(Modifier.weight(1f)) {
                                Text(
                                    l.hostName.ifBlank { l.macAddress.ifBlank { "جهاز" } },
                                    fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi,
                                )
                                Text(
                                    "${l.address}  •  ${l.macAddress}" +
                                        (if (l.expiresAfter.isNotBlank()) "  •  ينتهي بعد ${l.expiresAfter}" else ""),
                                    fontSize = 10.sp, color = TextLow,
                                )
                            }
                            IconButton(onClick = {
                                if (router != null && l.macAddress.isNotBlank()) {
                                    busy = true
                                    scope.launch {
                                        MikrotikClient.blockMac(router, l.macAddress, l.hostName)
                                            .onSuccess { message = "تم حجب ${l.macAddress}" }
                                            .onFailure { message = it.message.orEmpty() }
                                        busy = false
                                    }
                                }
                            }) {
                                Icon(Icons.Filled.Block, "حجب", tint = Danger, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }

            AdminTab.INTERFACES -> {
                interfaces.forEach { s ->
                    GlassCard(Modifier.fillMaxWidth().padding(bottom = 8.dp), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier
                                    .size(9.dp)
                                    .background(
                                        if (s.disabled) TextLow else if (s.running) Lime else Warn,
                                        RoundedCornerShape(999.dp),
                                    )
                            )
                            Spacer(Modifier.width(9.dp))
                            Column(Modifier.weight(1f)) {
                                Text(s.name, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(s.type, fontSize = 10.sp, color = TextLow)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text("نزول ${bytes(s.rxBytes)}", fontSize = 10.5.sp, color = Neon)
                                Text("صعود ${bytes(s.txBytes)}", fontSize = 10.5.sp, color = Violet)
                            }
                        }
                    }
                }
            }

            AdminTab.BLOCKED -> {
                GlassCard(Modifier.fillMaxWidth(), padding = 12) {
                    Text("إضافة عنوان فيزيائي", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                    Spacer(Modifier.height(8.dp))
                    AppField(macToAdd, { macToAdd = it }, "MAC مثل AA:BB:CC:DD:EE:FF", Modifier.fillMaxWidth())
                    Spacer(Modifier.height(7.dp))
                    AppField(macNote, { macNote = it }, "ملاحظة (اختياري)", Modifier.fillMaxWidth())
                    Spacer(Modifier.height(9.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GhostButton("حجب", icon = Icons.Filled.Block, color = Danger, enabled = !busy && macToAdd.isNotBlank()) {
                            val r = router ?: return@GhostButton
                            busy = true
                            scope.launch {
                                MikrotikClient.blockMac(r, macToAdd.trim(), macNote)
                                    .onSuccess { macToAdd = ""; macNote = ""; message = "تم الحجب" }
                                    .onFailure { message = it.message.orEmpty() }
                                busy = false
                                refresh()
                            }
                        }
                        GhostButton("سماح بدون كرت", color = Lime, enabled = !busy && macToAdd.isNotBlank()) {
                            val r = router ?: return@GhostButton
                            busy = true
                            scope.launch {
                                MikrotikClient.bypassMac(r, macToAdd.trim(), macNote)
                                    .onSuccess { macToAdd = ""; macNote = ""; message = "تم السماح" }
                                    .onFailure { message = it.message.orEmpty() }
                                busy = false
                                refresh()
                            }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                bindings.forEach { b ->
                    GlassCard(Modifier.fillMaxWidth().padding(bottom = 8.dp), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    b.macAddress.ifBlank { b.address.ifBlank { "—" } },
                                    fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi,
                                )
                                Text(
                                    bindingLabel(b.type) + (if (b.comment.isNotBlank()) "  •  ${b.comment}" else ""),
                                    fontSize = 10.sp,
                                    color = if (b.type == "blocked") Danger else Lime,
                                )
                            }
                            IconButton(onClick = {
                                val r = router ?: return@IconButton
                                busy = true
                                scope.launch {
                                    MikrotikClient.removeIpBinding(r, b.id)
                                        .onFailure { message = it.message.orEmpty() }
                                    busy = false
                                    refresh()
                                }
                            }) {
                                Icon(Icons.Filled.Delete, "حذف", tint = Danger, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }

            AdminTab.SYSTEM -> {
                GlassCard(Modifier.fillMaxWidth(), padding = 12) {
                    Text("الخدمات على الراوتر", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                    Spacer(Modifier.height(8.dp))
                    services.forEach { (name, port, enabled) ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(name, fontSize = 12.sp, color = TextHi, modifier = Modifier.weight(1f))
                            Text(if (port.isBlank()) "—" else port, fontSize = 11.sp, color = TextMid)
                            Spacer(Modifier.width(10.dp))
                            Text(
                                if (enabled) "مفعّلة" else "معطّلة",
                                fontSize = 10.5.sp,
                                color = if (enabled) Lime else TextLow,
                            )
                        }
                    }
                    if (services.isEmpty()) {
                        Text("اضغط تحديث لقراءة الخدمات", fontSize = 11.sp, color = TextLow)
                    }
                }
                Spacer(Modifier.height(12.dp))
                GlassCard(Modifier.fillMaxWidth(), padding = 12) {
                    Text("ربط الكرت بأول جهاز", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                    Spacer(Modifier.height(5.dp))
                    Text(
                        "عند تشغيله يُثبَّت الكرت على أول جهاز يدخل به، فلا يعمل على جهاز آخر. " +
                            "يُنفَّذ بسكربت دخول على بروفايل سيرفر الهوتسبوت.",
                        fontSize = 10.5.sp, color = TextLow,
                    )
                    Spacer(Modifier.height(9.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            when (bindOn) {
                                true -> "الحالة: مفعّل"
                                false -> "الحالة: معطّل"
                                null -> "الحالة: غير معروفة"
                            },
                            fontSize = 12.sp,
                            color = if (bindOn == true) Lime else TextMid,
                            modifier = Modifier.weight(1f),
                        )
                        GhostButton(
                            if (bindOn == true) "إيقاف" else "تشغيل",
                            color = if (bindOn == true) Danger else Lime,
                            enabled = !busy,
                        ) {
                            val r = router ?: return@GhostButton
                            val turnOn = bindOn != true
                            busy = true
                            scope.launch {
                                MikrotikClient.setBindFirstDevice(r, turnOn)
                                    .onSuccess { res ->
                                        bindOn = turnOn
                                        message = if (res.skipped > 0)
                                            "تم على ${res.changed} بروفايل — تُرك ${res.skipped} لأن عليه سكربت دخول خاص بك"
                                        else "تم على ${res.changed} من ${res.total} بروفايل"
                                    }
                                    .onFailure { message = it.message.orEmpty() }
                                busy = false
                            }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                GlassCard(Modifier.fillMaxWidth(), padding = 12) {
                    Text("صيانة", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
                    Spacer(Modifier.height(9.dp))
                    GhostButton("حفظ نسخة احتياطية على الراوتر", icon = Icons.Filled.Save, enabled = !busy) {
                        val r = router ?: return@GhostButton
                        busy = true
                        scope.launch {
                            val name = "cardmanager-" + System.currentTimeMillis()
                            MikrotikClient.backupRouter(r, name)
                                .onSuccess { message = "تم حفظ النسخة: $it — نزّلها من Files على الراوتر" }
                                .onFailure { message = it.message.orEmpty() }
                            busy = false
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    GhostButton("تشغيل تسجيل دخول الهوتسبوت", enabled = !busy) {
                        val r = router ?: return@GhostButton
                        busy = true
                        scope.launch {
                            MikrotikClient.enableHotspotLogging(r)
                                .onSuccess { message = "تم — سيبدأ الراوتر بتسجيل الجلسات في السجل" }
                                .onFailure { message = it.message.orEmpty() }
                            busy = false
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    GhostButton("إعادة تشغيل الراوتر", icon = Icons.Filled.PowerSettingsNew, color = Danger, enabled = !busy) {
                        confirmReboot = true
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "إعادة التشغيل تقطع الإنترنت عن كل المتصلين لدقيقة أو أكثر",
                        fontSize = 10.sp, color = TextLow,
                    )
                }
            }
        }

        Spacer(Modifier.height(30.dp))
    }

    if (confirmReboot) {
        AlertDialog(
            onDismissRequest = { confirmReboot = false },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("إعادة تشغيل الراوتر؟", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Text(
                    "سيُقطع الاتصال عن جميع المستخدمين حتى يعود الراوتر. هل تريد المتابعة؟",
                    fontSize = 13.sp, color = TextMid,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmReboot = false
                    val r = router ?: return@TextButton
                    scope.launch {
                        MikrotikClient.rebootRouter(r)
                        message = "أُرسل أمر إعادة التشغيل"
                    }
                }) { Text("إعادة التشغيل", color = Danger, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { confirmReboot = false }) { Text("إلغاء", color = TextLow) }
            },
        )
    }
}

private fun bindingLabel(type: String): String = when (type) {
    "blocked" -> "محجوب"
    "bypassed" -> "مسموح بدون كرت"
    "regular" -> "عادي"
    else -> type
}

private fun bytes(v: Long): String = when {
    v >= 1_073_741_824 -> String.format(Locale.US, "%.2f GB", v / 1_073_741_824.0)
    v >= 1_048_576 -> String.format(Locale.US, "%.1f MB", v / 1_048_576.0)
    v >= 1024 -> String.format(Locale.US, "%.0f KB", v / 1024.0)
    else -> "$v B"
}
