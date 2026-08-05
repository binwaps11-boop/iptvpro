package com.binwaps.cardmanager

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Router
import androidx.compose.runtime.Composable
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
import androidx.compose.material3.Text
import com.binwaps.cardmanager.ui.components.AppChip
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.BannerKind
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.MessageBanner
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Warn
import kotlinx.coroutines.launch

/**
 * لوحة الأدمن الموصولة بخادم التراخيص — المصدر المركزي الواحد. تعرض الطلبات
 * والمشتركين (بالأرقام والأجهزة والراوترات) من قاعدة البيانات نفسها التي
 * يسجّل فيها المشتركون، وتوافق/توقف/تنقل الجهاز عبرها مباشرة.
 */
@Composable
fun ServerAdminScreen() {
    val scope = rememberCoroutineScope()
    var signedIn by remember { mutableStateOf(AdminApi.hasToken()) }
    var tokenField by remember { mutableStateOf(AdminApi.token()) }
    var accounts by remember { mutableStateOf<List<AdminApi.ServerAccount>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<Pair<String, BannerKind>?>(null) }

    fun load() {
        busy = true; message = null
        scope.launch {
            AdminApi.accounts().fold(
                onSuccess = { accounts = it; busy = false },
                onFailure = {
                    busy = false
                    message = (it.message ?: "تعذّر الجلب") to BannerKind.ERROR
                    if ((it.message ?: "").contains("رمز الأدمن")) signedIn = false
                },
            )
        }
    }

    fun act(label: String, block: suspend () -> Result<Unit>) {
        busy = true; message = null
        scope.launch {
            block().fold(
                onSuccess = { message = "$label ✓" to BannerKind.SUCCESS; load() },
                onFailure = { busy = false; message = (it.message ?: "فشل") to BannerKind.ERROR },
            )
        }
    }

    Column(
        Modifier.fillMaxSize().background(ScreenGradient).verticalScroll(rememberScrollState()).padding(16.dp),
    ) {
        SectionHeader("لوحة التراخيص", "متصلة بخادمك — كل المشتركين والطلبات", Icons.Filled.Group)
        Spacer(Modifier.height(12.dp))

        if (!AdminApi.configured) {
            MessageBanner("خادم التراخيص غير مُهيَّأ في الإعدادات (LICENSE_SERVER)", BannerKind.ERROR)
            return@Column
        }

        if (!signedIn) {
            GlassCard(Modifier.fillMaxWidth(), padding = 16) {
                Text("رمز الأدمن", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "أدخل الرمز الذي طبعه الخادم عند التثبيت. يُحفظ على جهازك فقط.",
                    fontSize = 12.sp, color = TextMid,
                )
                Spacer(Modifier.height(10.dp))
                AppField(tokenField, { tokenField = it }, "رمز الأدمن", Modifier.fillMaxWidth(), ltr = true, password = true)
                Spacer(Modifier.height(12.dp))
                NeonButton("دخول", Modifier.fillMaxWidth(), enabled = tokenField.isNotBlank()) {
                    AdminApi.setToken(tokenField)
                    signedIn = true
                    load()
                }
                message?.let { Spacer(Modifier.height(10.dp)); MessageBanner(it.first, it.second) }
            }
            return@Column
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GhostButton("تحديث", Modifier, Icons.Filled.Refresh, enabled = !busy) { load() }
            GhostButton("تسجيل خروج", Modifier) { AdminApi.setToken(""); signedIn = false; accounts = emptyList() }
        }
        message?.let { Spacer(Modifier.height(10.dp)); MessageBanner(it.first, it.second) }
        Spacer(Modifier.height(12.dp))

        // أول تحميل
        if (accounts.isEmpty() && !busy && message == null) {
            LaunchedLoad { load() }
        }

        val pending = accounts.filter { it.pending }
        val rest = accounts.filterNot { it.pending }

        if (pending.isNotEmpty()) {
            Text("طلبات جديدة (${pending.size})", fontSize = 13.sp, color = Warn, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            pending.forEach { AccountCard(it, highlight = true, onAct = ::act) }
            Spacer(Modifier.height(10.dp))
        }

        Text("كل المشتركين (${accounts.size})", fontSize = 13.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        if (accounts.isEmpty() && !busy) {
            Text("لا مشتركين بعد", fontSize = 13.sp, color = TextMid, modifier = Modifier.padding(vertical = 20.dp))
        }
        rest.forEach { AccountCard(it, highlight = false, onAct = ::act) }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun LaunchedLoad(block: () -> Unit) {
    androidx.compose.runtime.LaunchedEffect(Unit) { block() }
}

@Composable
private fun AccountCard(
    acc: AdminApi.ServerAccount,
    highlight: Boolean,
    onAct: (String, suspend () -> Result<Unit>) -> Unit,
) {
    val glow = if (highlight) Warn else if (acc.valid) Lime else Danger
    GlassCard(Modifier.fillMaxWidth().padding(bottom = 8.dp), glow = glow.copy(alpha = 0.4f), padding = 12) {
        Text(acc.name.ifBlank { acc.email }, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextHi)
        Text("${acc.email}  •  ${acc.phone}", fontSize = 12.sp, color = TextMid)
        Text("الجهاز: ${acc.device}", fontSize = 11.5.sp, color = TextLow)
        val statusAr = when (acc.status) {
            "active" -> "مشترك (${acc.daysLeft} يوم)"
            "trial" -> "تجربة (${acc.daysLeft} يوم)"
            "trial_ended" -> "انتهت التجربة"
            "expired" -> "انتهى الاشتراك"
            "blocked" -> "موقوف"
            else -> acc.status
        }
        Text(
            statusAr + if (acc.pending) "  •  طلب ${if (acc.pendingRenewal) "تجديد" else "جديد"}" else "",
            fontSize = 12.sp, color = if (acc.valid) Lime else Warn, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 3.dp),
        )
        if (acc.routers.isNotEmpty()) {
            Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.material3.Icon(Icons.Filled.Router, null, tint = TextLow, modifier = Modifier.height(14.dp))
                Text(
                    "  " + acc.routers.joinToString("، ") { it.first.ifBlank { it.second } }.take(80),
                    fontSize = 11.sp, color = TextLow,
                )
            }
        }

        Spacer(Modifier.height(8.dp))
        var plan by remember(acc.id) { mutableStateOf("month") }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("month" to "شهر", "quarter" to "٣ أشهر", "year" to "سنة", "lifetime" to "دائم").forEach { (v, l) ->
                AppChip(l, plan == v) { plan = v }
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NeonButton("اعتماد", Modifier.weight(1f)) { onAct("اعتُمد") { AdminApi.approve(acc.id, plan) } }
            if (acc.blocked) {
                GhostButton("استئناف", Modifier.weight(1f)) { onAct("استُؤنف") { AdminApi.block(acc.id, false) } }
            } else {
                GhostButton("إيقاف", Modifier.weight(1f), color = Danger) { onAct("أُوقف") { AdminApi.block(acc.id, true) } }
            }
        }
    }
}
