package com.binwaps.cardmanager

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.license.LicenseCore
import com.binwaps.cardmanager.license.LicenseLink
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.theme.CardManagerTheme
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Ink
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
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** ترخيص صادر — يُحفظ في سجل الأدمن */
@Serializable
data class IssuedLicense(
    val customer: String,
    val deviceCode: String,
    val key: String,
    val planCode: Int,
    val issuedAt: Long,
    val expiresAt: Long,
    val phone: String = "",
)

/** سجل التراخيص الصادرة */
object AdminStore {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }
    private lateinit var ctx: Context
    private var cache: List<IssuedLicense> = emptyList()

    fun init(context: Context) {
        ctx = context.applicationContext
        cache = runCatching {
            val f = File(ctx.filesDir, "issued.json")
            if (f.exists()) json.decodeFromString<List<IssuedLicense>>(f.readText()) else emptyList()
        }.getOrDefault(emptyList())
    }

    fun all(): List<IssuedLicense> = cache

    /** ترخيص واحد لكل جهاز — التجديد يستبدل السابق */
    fun add(l: IssuedLicense) {
        cache = listOf(l) + cache.filterNot { it.deviceCode.equals(l.deviceCode, true) }
        persist()
    }

    fun remove(key: String) {
        cache = cache.filterNot { it.key == key }
        persist()
    }

    // سجل دائم للأجهزة التي أخذت تجربة — لا يُحذف أبداً حتى لو حُذف ترخيصها،
    // هذا ما يمنع «حذف التطبيق وإعادة التثبيت» من تجديد التجربة
    private var trialDevices: Map<String, Long> = emptyMap()

    fun initTrials() {
        trialDevices = runCatching {
            val f = File(ctx.filesDir, "trial_devices.json")
            if (f.exists()) json.decodeFromString<Map<String, Long>>(f.readText()) else emptyMap()
        }.getOrDefault(emptyMap())
    }

    /** متى أخذ هذا الجهاز تجربة؟ null = لم يأخذ */
    fun trialIssuedAt(deviceCode: String): Long? = trialDevices[deviceCode.trim().uppercase()]

    fun recordTrial(deviceCode: String) {
        trialDevices = trialDevices + (deviceCode.trim().uppercase() to System.currentTimeMillis())
        runCatching {
            File(ctx.filesDir, "trial_devices.json").writeText(json.encodeToString(trialDevices))
        }
    }

    private fun persist() = runCatching {
        File(ctx.filesDir, "issued.json").writeText(json.encodeToString(cache))
    }
}

class MainActivity : ComponentActivity() {

    /** طلب وصل عبر رابط من تطبيق مشترك */
    private val incoming = androidx.compose.runtime.mutableStateOf<LicenseLink.Request?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        com.binwaps.cardmanager.data.CrashLogger.install(this)
        com.binwaps.cardmanager.render.CardRenderer.init(this)
        AdminStore.init(this)
        AdminStore.initTrials()
        handleLink(intent)
        setContent {
            CardManagerTheme {
                AdminScreen(
                    incoming = incoming.value,
                    onIncomingConsumed = { incoming.value = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLink(intent)
    }

    private fun handleLink(intent: Intent?) {
        LicenseLink.parseRequest(intent?.data)?.let { incoming.value = it }
    }
}

@Composable
private fun AdminScreen(
    incoming: LicenseLink.Request? = null,
    onIncomingConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    var customer by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var deviceCode by remember { mutableStateOf("") }
    /** الضغطة الأولى على إصدار تجربة مكررة تُحذّر — والثانية تُصدر */
    var trialOverride by remember { mutableStateOf(false) }
    var plan by remember { mutableStateOf(LicenseCore.Plan.MONTH) }
    var generated by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var history by remember { mutableStateOf(AdminStore.all()) }
    var banner by remember { mutableStateOf<String?>(null) }

    val fmt = remember { SimpleDateFormat("yyyy/MM/dd", Locale.US) }

    // طلب وصل عبر رابط ← املأ الحقول تلقائياً
    androidx.compose.runtime.LaunchedEffect(incoming) {
        val req = incoming ?: return@LaunchedEffect
        deviceCode = req.deviceCode
        // إن كان مشتركاً سابقاً نستعيد اسمه من السجل
        val known = AdminStore.all().firstOrNull { it.deviceCode.equals(req.deviceCode, true) }
        customer = req.name.ifBlank { known?.customer.orEmpty() }
        phone = known?.phone.orEmpty()
        known?.let { plan = LicenseCore.Plan.of(it.planCode) }
        banner = if (req.renewal) {
            "طلب تجديد من ${customer.ifBlank { "مشترك" }}"
        } else {
            "طلب تفعيل جديد من ${customer.ifBlank { "مشترك" }}"
        }
        generated = null
        error = null
        onIncomingConsumed()
    }

    fun clipboard() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun expiryFor(p: LicenseCore.Plan): Long {
        val cal = Calendar.getInstance()
        when (p) {
            LicenseCore.Plan.TRIAL -> cal.add(Calendar.DAY_OF_YEAR, 7)
            LicenseCore.Plan.MONTH -> cal.add(Calendar.MONTH, 1)
            LicenseCore.Plan.QUARTER -> cal.add(Calendar.MONTH, 3)
            LicenseCore.Plan.YEAR -> cal.add(Calendar.YEAR, 1)
            LicenseCore.Plan.LIFETIME -> cal.add(Calendar.YEAR, 50)
        }
        return cal.timeInMillis
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Spacer(Modifier.height(10.dp))
        SectionHeader("لوحة التراخيص", "إصدار مفاتيح تفعيل للمشتركين", Icons.Filled.VpnKey)
        Spacer(Modifier.height(16.dp))

        // إشعار وصول طلب عبر رابط
        banner?.let { text ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .background(Lime.copy(alpha = 0.10f), RoundedCornerShape(13.dp))
                    .border(1.dp, Lime.copy(alpha = 0.4f), RoundedCornerShape(13.dp))
                    .clickable { banner = null }
                    .padding(13.dp)
            ) {
                Column {
                    Text(text, fontSize = 13.sp, color = Lime, fontWeight = FontWeight.Bold)
                    Text("البيانات مملوءة بالأسفل — اختر المدة واضغط إصدار المفتاح", fontSize = 11.sp, color = TextMid)
                }
            }
            Spacer(Modifier.height(14.dp))
        }

        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 16) {
            Text("ترخيص جديد", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(11.dp))
            AppField(customer, { customer = it }, "اسم المشترك", Modifier.fillMaxWidth())
            Spacer(Modifier.height(7.dp))
            AppField(phone, { phone = it }, "رقم جوال المشترك", Modifier.fillMaxWidth(), numeric = true)
            Spacer(Modifier.height(9.dp))
            AppField(deviceCode, { deviceCode = it; error = null }, "رمز جهاز المشترك", Modifier.fillMaxWidth())
            Spacer(Modifier.height(7.dp))
            GhostButton("لصق رمز الجهاز", Modifier.fillMaxWidth(), Icons.Filled.ContentPaste) {
                val text = clipboard().primaryClip?.getItemAt(0)?.text?.toString().orEmpty()
                if (text.isBlank()) {
                    Toast.makeText(context, "الحافظة فارغة", Toast.LENGTH_SHORT).show()
                } else {
                    // نأخذ آخر سطر يحتوي على رمز
                    deviceCode = text.trim().lines().last { it.isNotBlank() }.trim()
                    error = null
                }
            }

            Spacer(Modifier.height(12.dp))
            Text("مدة الاشتراك", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(7.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                LicenseCore.Plan.entries.forEach { p ->
                    val on = plan == p
                    Text(
                        p.labelAr,
                        fontSize = 11.5.sp,
                        color = if (on) Neon else TextMid,
                        fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                        modifier = Modifier
                            .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                            .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                            .clickable { plan = p }
                            .padding(horizontal = 13.dp, vertical = 7.dp),
                    )
                }
            }

            if (error != null) {
                Spacer(Modifier.height(10.dp))
                Text(error!!, fontSize = 12.sp, color = Danger)
            }

            Spacer(Modifier.height(14.dp))
            NeonButton("إصدار المفتاح", Modifier.fillMaxWidth(), Icons.Filled.VpnKey, enabled = deviceCode.isNotBlank()) {
                // التجربة مرة واحدة لكل جهاز: البصمة لا تتغير بإعادة تثبيت التطبيق،
                // فالجهاز الذي أخذ تجربة يظهر هنا مهما حذف التطبيق وأعاده
                val priorTrial = if (plan == LicenseCore.Plan.TRIAL) AdminStore.trialIssuedAt(deviceCode) else null
                if (priorTrial != null && !trialOverride) {
                    error = "⚠ هذا الجهاز أخذ تجربة من قبل بتاريخ ${fmt.format(Date(priorTrial))} — " +
                        "اضغط الزر مرة أخرى إن أردت الإصدار رغم ذلك"
                    trialOverride = true
                    return@NeonButton
                }
                trialOverride = false
                val expiry = expiryFor(plan)
                val key = LicenseCore.generate(AdminKeys.PRIVATE_KEY_B64, deviceCode, expiry, plan)
                if (key == null) {
                    error = "رمز الجهاز غير صحيح — تأكد من نسخه كاملاً"
                } else {
                    generated = key
                    error = null
                    if (plan == LicenseCore.Plan.TRIAL) AdminStore.recordTrial(deviceCode)
                    AdminStore.add(
                        IssuedLicense(
                            customer = customer.ifBlank { "بدون اسم" },
                            deviceCode = deviceCode.trim(),
                            key = key,
                            planCode = plan.code,
                            issuedAt = System.currentTimeMillis(),
                            expiresAt = expiry,
                            phone = phone.trim(),
                        )
                    )
                    history = AdminStore.all()
                }
            }
        }

        // المفتاح الناتج
        generated?.let { key ->
            Spacer(Modifier.height(14.dp))
            GlassCard(Modifier.fillMaxWidth(), glow = Lime.copy(alpha = 0.45f), padding = 16) {
                Text("المفتاح جاهز", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = Lime)
                Spacer(Modifier.height(9.dp))
                Text(
                    key,
                    fontSize = 12.5.sp, color = TextHi, textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Ink.copy(alpha = 0.6f), RoundedCornerShape(11.dp))
                        .border(1.dp, Stroke, RoundedCornerShape(11.dp))
                        .padding(11.dp),
                )
                Spacer(Modifier.height(11.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    GhostButton("نسخ", Modifier.weight(1f), Icons.Filled.ContentCopy) {
                        clipboard().setPrimaryClip(ClipData.newPlainText("license", key))
                        Toast.makeText(context, "تم نسخ المفتاح", Toast.LENGTH_SHORT).show()
                    }
                    GhostButton("إرسال للمشترك", Modifier.weight(1f), Icons.Filled.Share, color = Violet) {
                        val expiry = history.firstOrNull { it.key == key }?.expiresAt
                        context.startActivity(
                            Intent.createChooser(
                                Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(
                                        Intent.EXTRA_TEXT,
                                        LicenseLink.activationMessage(
                                            key = key,
                                            planLabel = plan.labelAr,
                                            expiryLabel = expiry?.let { fmt.format(Date(it)) }.orEmpty(),
                                        ),
                                    )
                                },
                                "إرسال المفتاح للمشترك",
                            )
                        )
                    }
                }
            }
        }

        // المشتركون
        Spacer(Modifier.height(20.dp))
        Text("المشتركون (${history.size})", fontSize = 13.sp, color = TextLow)
        Spacer(Modifier.height(9.dp))
        if (history.isEmpty()) {
            Text("لم تصدر أي ترخيص بعد", fontSize = 12.sp, color = TextLow)
        }
        val now = System.currentTimeMillis()
        history.forEach { l ->
            val daysLeft = ((l.expiresAt - now) / 86_400_000L).toInt()
            val expired = daysLeft < 0
            val soon = !expired && daysLeft <= 7
            GlassCard(
                Modifier.fillMaxWidth().padding(bottom = 8.dp),
                glow = (if (expired) Danger else if (soon) Warn else Lime).copy(alpha = 0.3f),
                padding = 12,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(l.customer, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                        Text(
                            "الجهاز: ${l.deviceCode}" + if (l.phone.isNotBlank()) "  •  ${l.phone}" else "",
                            fontSize = 11.sp, color = TextMid,
                        )
                        Text(
                            "${LicenseCore.Plan.of(l.planCode).labelAr} — " +
                                if (expired) "انتهى في ${fmt.format(Date(l.expiresAt))}"
                                else "ينتهي ${fmt.format(Date(l.expiresAt))} (متبقٍ $daysLeft يوم)",
                            fontSize = 11.sp,
                            color = if (expired) Danger else if (soon) Warn else TextLow,
                        )
                    }
                    Column {
                        Text(
                            "تجديد",
                            fontSize = 11.sp, color = Neon, fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .background(Neon.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
                                .clickable {
                                    customer = l.customer
                                    phone = l.phone
                                    deviceCode = l.deviceCode
                                    plan = LicenseCore.Plan.of(l.planCode)
                                    generated = null
                                    banner = "تجديد اشتراك ${l.customer}"
                                }
                                .padding(horizontal = 11.dp, vertical = 5.dp),
                        )
                        Row {
                            IconButton(onClick = {
                                clipboard().setPrimaryClip(ClipData.newPlainText("license", l.key))
                                Toast.makeText(context, "تم نسخ المفتاح", Toast.LENGTH_SHORT).show()
                            }) { Icon(Icons.Filled.ContentCopy, "نسخ", tint = Neon, modifier = Modifier.size(17.dp)) }
                            IconButton(onClick = {
                                AdminStore.remove(l.key); history = AdminStore.all()
                            }) { Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(17.dp)) }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .background(Danger.copy(alpha = 0.08f), RoundedCornerShape(13.dp))
                .border(1.dp, Danger.copy(alpha = 0.3f), RoundedCornerShape(13.dp))
                .padding(13.dp)
        ) {
            Text(
                "لا تشارك تطبيق لوحة التراخيص مع أحد — من يملكه يستطيع إصدار مفاتيح لأي جهاز.",
                fontSize = 11.5.sp, color = Danger,
            )
        }
        Spacer(Modifier.height(30.dp))
    }
}
