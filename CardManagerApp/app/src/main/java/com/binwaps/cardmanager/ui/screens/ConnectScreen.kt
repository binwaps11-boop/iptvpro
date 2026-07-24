package com.binwaps.cardmanager.ui.screens

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Wifi
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.model.RouterProfile
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.NeonGradient
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import kotlinx.coroutines.launch

/**
 * أول شاشة في التطبيق: الاتصال بالراوتر.
 * يمكن حفظ عدة راوترات والتبديل بينها، أو الدخول بدون اتصال للعمل محلياً.
 */
@Composable
fun ConnectScreen(onConnected: () -> Unit, onSkip: () -> Unit) {
    val scope = rememberCoroutineScope()
    val routers by Store.routers.collectAsState()
    val settings by Store.settings.collectAsState()

    var editingId by remember { mutableStateOf(Store.activeRouter()?.id ?: 0L) }
    val current = routers.firstOrNull { it.id == editingId }

    var name by remember { mutableStateOf(current?.name ?: "راوتري") }
    var host by remember { mutableStateOf(current?.host ?: "192.168.88.1") }
    var port by remember { mutableStateOf((current?.port ?: 8728).toString()) }
    var user by remember { mutableStateOf(current?.username ?: "admin") }
    var pass by remember { mutableStateOf(current?.password ?: "") }

    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // ملء الحقول عند اختيار راوتر محفوظ
    LaunchedEffect(editingId) {
        routers.firstOrNull { it.id == editingId }?.let { r ->
            name = r.name; host = r.host; port = r.port.toString(); user = r.username; pass = r.password
        }
    }

    fun doConnect() {
        error = null
        busy = true
        val profile = RouterProfile(
            id = if (editingId != 0L) editingId else Store.newId(),
            name = name.ifBlank { "راوتر" },
            host = host.trim(),
            port = port.toIntOrNull() ?: 8728,
            username = user.trim(),
            password = pass,
        )
        scope.launch {
            val result = MikrotikClient.connect(profile)
            busy = false
            result.onSuccess { status ->
                Store.upsertRouter(profile)
                Store.setActiveRouter(profile.id)
                Store.setStatus(status)
                Store.setConnected(true)
                // تحديث رابط الهوتسبوت تلقائياً حسب عنوان الراوتر
                if (Store.settings.value.hotspotLoginUrl.contains("192.168.88.1")) {
                    Store.updateSettings(Store.settings.value.copy(hotspotLoginUrl = "http://${profile.host}/login"))
                }
                onConnected()
            }.onFailure {
                error = it.message ?: "تعذّر الاتصال بالراوتر"
            }
        }
    }

    val transition = rememberInfiniteTransition(label = "glow")
    val pulse by transition.animateFloat(
        initialValue = 0.94f, targetValue = 1.06f,
        animationSpec = infiniteRepeatable(tween(2200), RepeatMode.Reverse), label = "pulse",
    )

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(26.dp))

        // الشعار
        Box(contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size(96.dp)
                    .scale(pulse)
                    .background(
                        Brush.radialGradient(listOf(Neon.copy(alpha = 0.25f), Violet.copy(alpha = 0.02f))),
                        CircleShape,
                    )
            )
            Box(
                Modifier
                    .size(66.dp)
                    .background(NeonGradient, RoundedCornerShape(20.dp)),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Router, null, tint = com.binwaps.cardmanager.ui.theme.Ink, modifier = Modifier.size(34.dp)) }
        }

        Spacer(Modifier.height(14.dp))
        Text("مدير الكروت", fontSize = 27.sp, fontWeight = FontWeight.Bold, color = TextHi)
        Text(
            "اتصل بالراوتر للبدء — إنشاء وطباعة كروت اليوزر منجر والهوتسبوت",
            fontSize = 12.5.sp, color = TextLow, textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 4.dp, start = 12.dp, end = 12.dp),
        )
        Spacer(Modifier.height(22.dp))

        // الراوترات المحفوظة
        if (routers.isNotEmpty()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("راوتراتي", fontSize = 12.sp, color = TextLow, modifier = Modifier.weight(1f))
            }
            Spacer(Modifier.height(6.dp))
            routers.forEach { r ->
                val selected = r.id == editingId
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(bottom = 6.dp)
                        .background(
                            if (selected) Neon.copy(alpha = 0.10f) else com.binwaps.cardmanager.ui.theme.Panel,
                            RoundedCornerShape(13.dp),
                        )
                        .border(1.dp, if (selected) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(13.dp))
                        .clickable { editingId = r.id }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Wifi, null, tint = if (selected) Neon else TextLow, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(r.name, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextHi)
                        Text("${r.host}:${r.port} — ${r.username}", fontSize = 11.sp, color = TextLow)
                    }
                    IconButton(onClick = { Store.deleteRouter(r.id); if (editingId == r.id) editingId = 0L }) {
                        Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(18.dp))
                    }
                }
            }
            GhostButton("+ راوتر جديد", Modifier.fillMaxWidth()) {
                editingId = 0L; name = "راوتر جديد"; host = "192.168.88.1"; port = "8728"; user = "admin"; pass = ""
            }
            Spacer(Modifier.height(14.dp))
        }

        // نموذج بيانات الاتصال
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 16) {
            Text("بيانات الاتصال", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(12.dp))
            AppField(name, { name = it }, "اسم الراوتر", Modifier.fillMaxWidth(), leading = Icons.Filled.Router)
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppField(host, { host = it }, "عنوان IP", Modifier.weight(2f), leading = Icons.Filled.Dns)
                AppField(port, { port = it.filter { c -> c.isDigit() } }, "المنفذ", Modifier.weight(1f), numeric = true)
            }
            Spacer(Modifier.height(9.dp))
            AppField(user, { user = it }, "اسم المستخدم", Modifier.fillMaxWidth(), leading = Icons.Filled.Person)
            Spacer(Modifier.height(9.dp))
            AppField(pass, { pass = it }, "كلمة المرور", Modifier.fillMaxWidth(), password = true, leading = Icons.Filled.Lock)

            if (error != null) {
                Spacer(Modifier.height(10.dp))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(Danger.copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                        .border(1.dp, Danger.copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                        .padding(11.dp)
                ) {
                    Column {
                        Text("فشل الاتصال", fontSize = 12.5.sp, color = Danger, fontWeight = FontWeight.Bold)
                        Text(error!!, fontSize = 11.sp, color = TextMid)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "تأكد أن خدمة API مفعّلة على الراوتر: IP → Services → api (منفذ 8728)، وأن جوالك على نفس الشبكة.",
                            fontSize = 10.5.sp, color = TextLow,
                        )
                    }
                }
            }

            Spacer(Modifier.height(14.dp))
            NeonButton(
                text = if (busy) "جاري الاتصال…" else "اتصال",
                icon = Icons.Filled.Wifi,
                enabled = !busy && host.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) { doConnect() }
        }

        Spacer(Modifier.height(12.dp))
        Text(
            "الدخول بدون اتصال — للتصميم والطباعة محلياً",
            fontSize = 12.sp, color = TextMid,
            modifier = Modifier
                .clickable { Store.setConnected(false); onSkip() }
                .padding(8.dp),
        )
        Spacer(Modifier.height(30.dp))
    }
}
