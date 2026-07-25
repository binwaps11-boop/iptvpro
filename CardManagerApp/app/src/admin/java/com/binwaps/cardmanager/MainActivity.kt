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
import androidx.compose.runtime.collectAsState
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

/**
 * حساب مشترك — الوحدة الأساسية في لوحة الأدمن.
 * الحساب = بريد جيميل، مربوط بجهاز واحد فقط. الطلب الوارد يصبح حساباً
 * «قيد الانتظار» حتى توافق عليه، فتُصدر مفتاحه المقفول على جهازه.
 */
@Serializable
data class Account(
    val email: String,
    val customer: String = "",
    val phone: String = "",
    /** جهاز الطلب الحالي (قد يتغير إن طلب من جوال آخر) */
    val deviceCode: String = "",
    /** الجهاز الذي صدر له المفتاح الفعّال — أساس قاعدة «جوال واحد» */
    val boundDevice: String = "",
    val key: String = "",
    val planCode: Int = 1,
    val issuedAt: Long = 0,
    val expiresAt: Long = 0,
    /** true = طلب جديد لم تُصدر مفتاحه بعد */
    val pending: Boolean = true,
    val requestedAt: Long = 0,
    val renewal: Boolean = false,
) {
    val activated: Boolean get() = key.isNotBlank()
}

/** حفظ حسابات المشتركين والطلبات */
object AdminStore {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }
    private lateinit var ctx: Context
    private var cache: List<Account> = emptyList()

    fun init(context: Context) {
        ctx = context.applicationContext
        cache = runCatching {
            val f = File(ctx.filesDir, "accounts.json")
            if (f.exists()) json.decodeFromString<List<Account>>(f.readText())
            else migrateOldIssued()
        }.getOrDefault(emptyList())
    }

    /** ترحيل السجل القديم (تراخيص بلا بريد) إلى حسابات */
    private fun migrateOldIssued(): List<Account> {
        val old = runCatching {
            val f = File(ctx.filesDir, "issued.json")
            if (!f.exists()) return emptyList()
            json.decodeFromString<List<OldIssued>>(f.readText())
        }.getOrDefault(emptyList())
        val migrated = old.map {
            Account(
                email = "device:${it.deviceCode}", customer = it.customer, phone = it.phone,
                deviceCode = it.deviceCode, boundDevice = it.deviceCode, key = it.key, planCode = it.planCode,
                issuedAt = it.issuedAt, expiresAt = it.expiresAt, pending = false,
            )
        }
        if (migrated.isNotEmpty()) persistList(migrated)
        return migrated
    }

    @Serializable
    private data class OldIssued(
        val customer: String = "", val deviceCode: String = "", val key: String = "",
        val planCode: Int = 1, val issuedAt: Long = 0, val expiresAt: Long = 0, val phone: String = "",
    )

    fun all(): List<Account> = cache
    fun pending(): List<Account> = cache.filter { it.pending }.sortedByDescending { it.requestedAt }
    fun subscribers(): List<Account> = cache.filter { it.activated }.sortedByDescending { it.issuedAt }

    private fun keyOf(a: Account) = a.email.trim().lowercase().ifBlank { "device:${a.deviceCode.trim().uppercase()}" }

    /** يضيف/يحدّث حساباً حسب بريده */
    fun upsert(a: Account) {
        val k = keyOf(a)
        cache = listOf(a) + cache.filterNot { keyOf(it) == k }
        persistList(cache)
    }

    fun removeByEmail(email: String) {
        cache = cache.filterNot { it.email.equals(email, true) }
        persistList(cache)
    }

    fun byEmail(email: String): Account? =
        cache.firstOrNull { it.email.equals(email.trim(), true) }

    /**
     * هل هذا البريد مربوط بجهاز آخر مفعّل؟ — أساس قاعدة «حساب واحد لجوال واحد».
     * يعيد رمز الجهاز المربوط، أو null إن كان حراً أو لنفس الجهاز.
     */
    fun boundToOtherDevice(email: String, deviceCode: String): String? {
        val a = byEmail(email) ?: return null
        if (!a.activated || a.boundDevice.isBlank()) return null
        return if (a.boundDevice.trim().uppercase() != deviceCode.trim().uppercase()) a.boundDevice else null
    }

    /** سجل الطلب الوارد كحساب قيد الانتظار (يُدمج مع موجود بنفس البريد) */
    fun recordRequest(req: LicenseLink.Request) {
        val existing = byEmail(req.email)
        val email = req.email.ifBlank { existing?.email ?: "device:${req.deviceCode}" }
        upsert(
            (existing ?: Account(email = email)).copy(
                email = email,
                customer = req.name.ifBlank { existing?.customer.orEmpty() },
                phone = req.phone.ifBlank { existing?.phone.orEmpty() },
                deviceCode = req.deviceCode,
                pending = true,
                requestedAt = System.currentTimeMillis(),
                renewal = req.renewal,
            )
        )
    }

    private fun persistList(list: List<Account>) = runCatching {
        File(ctx.filesDir, "accounts.json").writeText(json.encodeToString(list))
    }
}

class MainActivity : ComponentActivity() {

    private val incoming = androidx.compose.runtime.mutableStateOf<LicenseLink.Request?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        com.binwaps.cardmanager.data.CrashLogger.install(this)
        com.binwaps.cardmanager.render.CardRenderer.init(this)
        com.binwaps.cardmanager.data.Backend.init(this)
        AdminStore.init(this)
        handleLink(intent)
        setContent {
            CardManagerTheme {
                AdminScreen(incoming = incoming.value, onConsumed = { incoming.value = null })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLink(intent)
    }

    private fun handleLink(intent: Intent?) {
        LicenseLink.parseRequest(intent?.data)?.let {
            AdminStore.recordRequest(it)   // كل طلب يصل يُسجَّل حساباً قيد الانتظار
            incoming.value = it
        }
    }
}

private fun expiryFor(p: LicenseCore.Plan): Long {
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

@Composable
private fun AdminScreen(
    incoming: LicenseLink.Request? = null,
    onConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    val fmt = remember { SimpleDateFormat("yyyy/MM/dd", Locale.US) }

    var localAccounts by remember { mutableStateOf(AdminStore.all()) }
    var editing by remember { mutableStateOf<Account?>(null) }   // الحساب المفتوح للإصدار
    var plan by remember { mutableStateOf(LicenseCore.Plan.MONTH) }
    var override by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var generated by remember { mutableStateOf<Account?>(null) }
    var manualDevice by remember { mutableStateOf("") }
    var manualEmail by remember { mutableStateOf("") }

    // الربط السحابي الحي — الطلبات تصل لحظياً دون رابط
    val cloudReady by com.binwaps.cardmanager.data.Backend.ready.collectAsState()
    var cloudAccounts by remember { mutableStateOf<List<com.binwaps.cardmanager.data.CloudAccount>>(emptyList()) }
    androidx.compose.runtime.DisposableEffect(cloudReady) {
        val reg = if (cloudReady)
            com.binwaps.cardmanager.data.Backend.listenAccounts { cloudAccounts = it } else null
        onDispose { reg?.remove() }
    }

    fun cloudToAccount(c: com.binwaps.cardmanager.data.CloudAccount) = Account(
        email = c.email.ifBlank { "device:${c.deviceCode}" },
        customer = c.name, phone = c.phone, deviceCode = c.deviceCode,
        boundDevice = c.boundDevice, key = c.key, planCode = c.planCode,
        issuedAt = c.issuedAt, expiresAt = c.expiresAt,
        pending = c.status == "pending", requestedAt = c.requestedAt, renewal = c.renewal,
    )

    // المصدر الحي إن توفر السحاب، وإلا المحلي
    val accounts = if (cloudReady) cloudAccounts.map { cloudToAccount(it) } else localAccounts

    fun reload() { localAccounts = AdminStore.all() }

    fun accIdOf(acc: Account) =
        com.binwaps.cardmanager.data.Backend.accountId(
            acc.email.removePrefix("device:").let { if (it == acc.deviceCode) "" else acc.email }, acc.deviceCode,
        )

    // طلب وصل عبر رابط ← افتحه للإصدار
    androidx.compose.runtime.LaunchedEffect(incoming) {
        val req = incoming ?: return@LaunchedEffect
        reload()
        editing = AdminStore.byEmail(req.email.ifBlank { "device:${req.deviceCode}" })
        editing?.let { plan = LicenseCore.Plan.of(it.planCode) }
        generated = null; error = null; override = false
        onConsumed()
    }

    fun clipboard() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun issue(acc: Account) {
        // قاعدة «حساب واحد لجوال واحد» — نفحص في السحاب إن توفّر، وإلا محلياً
        val bound = if (cloudReady)
            cloudAccounts.firstOrNull { it.email.equals(acc.email, true) && it.approved && it.boundDevice.isNotBlank() }
                ?.boundDevice?.takeIf { it.trim().uppercase() != acc.deviceCode.trim().uppercase() }
        else AdminStore.boundToOtherDevice(acc.email, acc.deviceCode)
        if (bound != null && !override) {
            error = "⚠ هذا الحساب (${acc.email}) مربوط بجهاز آخر: $bound — " +
                "لن يعمل على جوالين. اضغط مرة أخرى للنقل إلى الجهاز الجديد رغم ذلك."
            override = true
            return
        }
        override = false
        val expiry = expiryFor(plan)
        val key = LicenseCore.generate(AdminKeys.PRIVATE_KEY_B64, acc.deviceCode, expiry, plan)
        if (key == null) {
            error = "رمز الجهاز غير صحيح — تأكد من نسخه كاملاً"
            return
        }
        val updated = acc.copy(
            key = key, planCode = plan.code, issuedAt = System.currentTimeMillis(),
            expiresAt = expiry, pending = false, boundDevice = acc.deviceCode.trim(),
        )
        AdminStore.upsert(updated)
        reload()
        // يصل المشترك لحظياً فيُفعَّل تطبيقه تلقائياً
        if (cloudReady) com.binwaps.cardmanager.data.Backend.issue(
            accIdOf(acc), key, plan.code, expiry, acc.deviceCode.trim(),
        )
        generated = updated
        editing = updated
        error = null
    }

    Column(
        Modifier.fillMaxSize().background(ScreenGradient).verticalScroll(rememberScrollState()).padding(16.dp),
    ) {
        Spacer(Modifier.height(10.dp))
        SectionHeader(
            "لوحة التراخيص",
            if (cloudReady) "متصل بالسحابة — الطلبات تصل لحظياً" else "الموافقة على الحسابات وإصدار المفاتيح",
            Icons.Filled.VpnKey,
        )
        Spacer(Modifier.height(14.dp))

        val pending = accounts.filter { it.pending }.sortedByDescending { it.requestedAt }
        val subs = accounts.filter { it.activated }.sortedByDescending { it.issuedAt }
        val now = System.currentTimeMillis()

        // ===== الطلبات الجديدة =====
        Text("طلبات جديدة (${pending.size})", fontSize = 13.sp, color = TextLow)
        Spacer(Modifier.height(8.dp))
        if (pending.isEmpty()) {
            Text(
                if (cloudReady) "لا توجد طلبات — ستصل هنا لحظياً فور إرسال المشترك"
                else "لا توجد طلبات — فعّل الربط السحابي أو استقبلها عبر الرابط",
                fontSize = 11.5.sp, color = TextLow,
            )
        }
        pending.forEach { acc ->
            GlassCard(Modifier.fillMaxWidth().padding(bottom = 8.dp), glow = Warn.copy(alpha = 0.35f), padding = 12) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(acc.customer.ifBlank { "بدون اسم" }, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                        if (!acc.email.startsWith("device:")) Text(acc.email, fontSize = 11.5.sp, color = Neon)
                        Text(
                            "الجهاز: ${acc.deviceCode}" + if (acc.phone.isNotBlank()) "  •  ${acc.phone}" else "",
                            fontSize = 11.sp, color = TextMid,
                        )
                        if (acc.renewal) Text("طلب تجديد", fontSize = 10.5.sp, color = Warn)
                    }
                    Text(
                        "موافقة",
                        fontSize = 12.sp, color = Lime, fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .background(Lime.copy(alpha = 0.14f), RoundedCornerShape(999.dp))
                            .clickable { editing = acc; plan = LicenseCore.Plan.of(acc.planCode); generated = null; error = null; override = false }
                            .padding(horizontal = 13.dp, vertical = 7.dp),
                    )
                    IconButton(onClick = { AdminStore.removeByEmail(acc.email); if (cloudReady) com.binwaps.cardmanager.data.Backend.deleteAccount(accIdOf(acc)); reload() }) {
                        Icon(Icons.Filled.Delete, "حذف الطلب", tint = TextLow, modifier = Modifier.size(17.dp))
                    }
                }
            }
        }

        // ===== إصدار / موافقة على حساب =====
        editing?.let { acc ->
            Spacer(Modifier.height(14.dp))
            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.4f), padding = 16) {
                Text("الموافقة وإصدار المفتاح", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Spacer(Modifier.height(9.dp))
                if (!acc.email.startsWith("device:")) {
                    Text("الحساب: ${acc.email}", fontSize = 12.5.sp, color = Neon)
                    Spacer(Modifier.height(4.dp))
                }
                Text("المشترك: ${acc.customer.ifBlank { "—" }}", fontSize = 12.sp, color = TextMid)
                Text("الجهاز: ${acc.deviceCode}", fontSize = 12.sp, color = TextMid)
                if (acc.phone.isNotBlank()) Text("الجوال: ${acc.phone}", fontSize = 12.sp, color = TextMid)

                Spacer(Modifier.height(12.dp))
                Text("مدة الاشتراك", fontSize = 12.sp, color = TextLow)
                Spacer(Modifier.height(7.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    LicenseCore.Plan.entries.forEach { p ->
                        val on = plan == p
                        Text(
                            p.labelAr, fontSize = 11.5.sp,
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
                error?.let {
                    Spacer(Modifier.height(10.dp))
                    Text(it, fontSize = 12.sp, color = Danger)
                }
                Spacer(Modifier.height(13.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f)) {
                        NeonButton("إصدار المفتاح", Modifier.fillMaxWidth(), Icons.Filled.VpnKey, enabled = acc.deviceCode.isNotBlank()) { issue(acc) }
                    }
                    GhostButton("إلغاء") { editing = null; error = null; generated = null }
                }
            }
            // دردشة حية مع المشترك عن هذا الحساب
            if (cloudReady) {
                Spacer(Modifier.height(12.dp))
                com.binwaps.cardmanager.ui.screens.ChatPanel(accountId = accIdOf(acc), asAdmin = true)
            }
        }

        // ===== المفتاح الناتج =====
        generated?.let { acc ->
            Spacer(Modifier.height(12.dp))
            GlassCard(Modifier.fillMaxWidth(), glow = Lime.copy(alpha = 0.45f), padding = 16) {
                Text("المفتاح جاهز — أرسله للمشترك", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = Lime)
                Spacer(Modifier.height(9.dp))
                Text(
                    acc.key, fontSize = 12.sp, color = TextHi, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                        .background(Ink.copy(alpha = 0.6f), RoundedCornerShape(11.dp))
                        .border(1.dp, Stroke, RoundedCornerShape(11.dp)).padding(11.dp),
                )
                Spacer(Modifier.height(11.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    GhostButton("نسخ", Modifier.weight(1f), Icons.Filled.ContentCopy) {
                        clipboard().setPrimaryClip(ClipData.newPlainText("license", acc.key))
                        Toast.makeText(context, "تم نسخ المفتاح", Toast.LENGTH_SHORT).show()
                    }
                    GhostButton("إرسال للمشترك", Modifier.weight(1f), Icons.Filled.Share, color = Violet) {
                        context.startActivity(
                            Intent.createChooser(
                                Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(
                                        Intent.EXTRA_TEXT,
                                        LicenseLink.activationMessage(
                                            key = acc.key,
                                            planLabel = LicenseCore.Plan.of(acc.planCode).labelAr,
                                            expiryLabel = fmt.format(Date(acc.expiresAt)),
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

        // ===== إدخال يدوي (احتياطي) =====
        Spacer(Modifier.height(16.dp))
        GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.3f), padding = 14) {
            Text("إضافة يدوية", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Text("للحالات الاستثنائية — الصق رمز الجهاز والبريد", fontSize = 10.5.sp, color = TextLow)
            Spacer(Modifier.height(9.dp))
            AppField(manualEmail, { manualEmail = it }, "بريد المشترك (اختياري)", Modifier.fillMaxWidth())
            Spacer(Modifier.height(7.dp))
            AppField(manualDevice, { manualDevice = it }, "رمز جهاز المشترك", Modifier.fillMaxWidth())
            Spacer(Modifier.height(7.dp))
            GhostButton("لصق رمز الجهاز", Modifier.fillMaxWidth(), Icons.Filled.ContentPaste) {
                val text = clipboard().primaryClip?.getItemAt(0)?.text?.toString().orEmpty()
                if (text.isNotBlank()) manualDevice = text.trim().lines().last { it.isNotBlank() }.trim()
            }
            Spacer(Modifier.height(10.dp))
            Box {
                NeonButton("تجهيز الحساب للإصدار", Modifier.fillMaxWidth(), Icons.Filled.VpnKey, enabled = manualDevice.isNotBlank()) {
                    val email = manualEmail.trim().ifBlank { "device:${manualDevice.trim()}" }
                    val acc = AdminStore.byEmail(email) ?: Account(email = email)
                    editing = acc.copy(email = email, deviceCode = manualDevice.trim())
                    generated = null; error = null; override = false
                    manualDevice = ""; manualEmail = ""
                }
            }
        }

        // ===== المشتركون =====
        Spacer(Modifier.height(20.dp))
        Text("المشتركون (${subs.size})", fontSize = 13.sp, color = TextLow)
        Spacer(Modifier.height(9.dp))
        if (subs.isEmpty()) Text("لم تصدر أي ترخيص بعد", fontSize = 12.sp, color = TextLow)
        subs.forEach { acc ->
            val daysLeft = ((acc.expiresAt - now) / 86_400_000L).toInt()
            val expired = daysLeft < 0
            val soon = !expired && daysLeft <= 7
            GlassCard(
                Modifier.fillMaxWidth().padding(bottom = 8.dp),
                glow = (if (expired) Danger else if (soon) Warn else Lime).copy(alpha = 0.3f),
                padding = 12,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(acc.customer.ifBlank { "بدون اسم" }, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                        if (!acc.email.startsWith("device:")) Text(acc.email, fontSize = 11.sp, color = Neon)
                        Text(
                            "الجهاز: ${acc.deviceCode}" + if (acc.phone.isNotBlank()) "  •  ${acc.phone}" else "",
                            fontSize = 11.sp, color = TextMid,
                        )
                        Text(
                            "${LicenseCore.Plan.of(acc.planCode).labelAr} — " +
                                if (expired) "انتهى في ${fmt.format(Date(acc.expiresAt))}"
                                else "ينتهي ${fmt.format(Date(acc.expiresAt))} (متبقٍ $daysLeft يوم)",
                            fontSize = 11.sp,
                            color = if (expired) Danger else if (soon) Warn else TextLow,
                        )
                    }
                    Column {
                        Text(
                            "تجديد", fontSize = 11.sp, color = Neon, fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .background(Neon.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
                                .clickable { editing = acc; plan = LicenseCore.Plan.of(acc.planCode); generated = null; error = null; override = false }
                                .padding(horizontal = 11.dp, vertical = 5.dp),
                        )
                        Row {
                            IconButton(onClick = {
                                clipboard().setPrimaryClip(ClipData.newPlainText("license", acc.key))
                                Toast.makeText(context, "تم نسخ المفتاح", Toast.LENGTH_SHORT).show()
                            }) { Icon(Icons.Filled.ContentCopy, "نسخ", tint = Neon, modifier = Modifier.size(17.dp)) }
                            IconButton(onClick = { AdminStore.removeByEmail(acc.email); if (cloudReady) com.binwaps.cardmanager.data.Backend.deleteAccount(accIdOf(acc)); reload() }) {
                                Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(17.dp))
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        Box(
            Modifier.fillMaxWidth()
                .background(Danger.copy(alpha = 0.08f), RoundedCornerShape(13.dp))
                .border(1.dp, Danger.copy(alpha = 0.3f), RoundedCornerShape(13.dp)).padding(13.dp),
        ) {
            Text(
                "لا تشارك تطبيق لوحة التراخيص مع أحد — من يملكه يستطيع إصدار مفاتيح لأي جهاز.",
                fontSize = 11.5.sp, color = Danger,
            )
        }
        Spacer(Modifier.height(30.dp))
    }
}
