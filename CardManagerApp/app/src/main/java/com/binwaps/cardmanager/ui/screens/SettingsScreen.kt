package com.binwaps.cardmanager.ui.screens

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
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
import com.binwaps.cardmanager.license.LicenseManager
import com.binwaps.cardmanager.license.LicenseState
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.components.StatusPill
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Warn
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(onDisconnect: () -> Unit, onLicense: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings by Store.settings.collectAsState()
    val connected by Store.connected.collectAsState()
    val status by Store.status.collectAsState()
    var testing by remember { mutableStateOf(false) }
    // نص نسخة احتياطية بانتظار تأكيد الاستعادة (عملية تستبدل كل البيانات)
    var pendingRestore by remember { mutableStateOf<String?>(null) }
    val restoreLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri != null) {
            // قراءة ملف قد يحوي صوراً Base64 بميغابايتات — على خيط خلفي لا الرئيسي
            scope.launch {
                val text = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    runCatching {
                        context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                    }.getOrNull()
                }
                if (text.isNullOrBlank()) {
                    Toast.makeText(context, "تعذّر قراءة الملف", Toast.LENGTH_LONG).show()
                } else pendingRestore = text
            }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SectionHeader("الإعدادات", null, Icons.Filled.Settings)

        // الراوتر
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("الراوتر", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi, modifier = Modifier.weight(1f))
                StatusPill(connected, if (connected) "متصل" else "غير متصل")
            }
            Spacer(Modifier.height(9.dp))
            val r = Store.activeRouter()
            Text(
                if (r == null) "لا يوجد راوتر محفوظ" else "${r.name} — ${r.host}:${r.port} (${r.username})",
                fontSize = 12.5.sp, color = TextMid,
            )
            if (status.identity.isNotBlank()) {
                Text("${status.identity} • ${status.board} • ${status.version}", fontSize = 11.sp, color = TextLow)
            }
            Spacer(Modifier.height(11.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GhostButton(if (testing) "جاري الفحص…" else "اختبار الاتصال", icon = Icons.Filled.Router, enabled = !testing && r != null) {
                    testing = true
                    scope.launch {
                        MikrotikClient.connect(r!!)
                            .onSuccess {
                                Store.setStatus(it); Store.setConnected(true)
                                Toast.makeText(context, "نجح الاتصال ✓", Toast.LENGTH_LONG).show()
                            }
                            .onFailure {
                                Store.setConnected(false)
                                Toast.makeText(context, "فشل: ${it.message}", Toast.LENGTH_LONG).show()
                            }
                        testing = false
                    }
                }
                GhostButton("تغيير الراوتر", icon = Icons.Filled.Logout, color = Danger) {
                    Store.setConnected(false)
                    onDisconnect()
                }
            }
        }

        // QR والدخول التلقائي
        GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.3f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("رمز QR والدخول التلقائي", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            }
            Spacer(Modifier.height(10.dp))
            AppField(
                settings.hotspotLoginUrl,
                { Store.updateSettings(settings.copy(hotspotLoginUrl = it)) },
                "رابط صفحة دخول الهوتسبوت", Modifier.fillMaxWidth(), leading = Icons.Filled.QrCode2, code = true,
            )
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppField(settings.wifiSsid, { Store.updateSettings(settings.copy(wifiSsid = it)) }, "اسم الشبكة SSID", Modifier.weight(1f), code = true)
                AppField(settings.wifiPassword, { Store.updateSettings(settings.copy(wifiPassword = it)) }, "كلمة مرور الواي فاي", Modifier.weight(1f), code = true)
            }
        }

        // الطباعة
        GlassCard(Modifier.fillMaxWidth()) {
            Text("الطباعة", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(10.dp))
            AppField(settings.currency, { Store.updateSettings(settings.copy(currency = it)) }, "العملة", Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            AppField(
                settings.lowStockThreshold.toString(),
                { v -> v.filter { it.isDigit() }.toIntOrNull()?.let { Store.updateSettings(settings.copy(lowStockThreshold = it.coerceIn(0, 100000))) } },
                "تنبيه نفاد الكروت عند بقاء (عدد)", Modifier.fillMaxWidth(), numeric = true,
            )
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppField(
                    settings.thermalFeedMm.toString(),
                    { it.toFloatOrNull()?.let { v -> Store.updateSettings(settings.copy(thermalFeedMm = v)) } },
                    "تغذية الورق (مم)", Modifier.weight(1f), numeric = true,
                )
                AppField(
                    settings.thermalDpi.toString(),
                    { it.toIntOrNull()?.let { v -> Store.updateSettings(settings.copy(thermalDpi = v)) } },
                    "دقة الطابعة DPI", Modifier.weight(1f), numeric = true,
                )
            }
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppField(
                    settings.tcpPrinterIp,
                    { Store.updateSettings(settings.copy(tcpPrinterIp = it.trim())) },
                    "طابعة شبكة IP (اختياري)", Modifier.weight(2f), leading = Icons.Filled.Print, code = true,
                )
                AppField(
                    settings.tcpPrinterPort.toString(),
                    { it.toIntOrNull()?.let { v -> Store.updateSettings(settings.copy(tcpPrinterPort = v)) } },
                    "المنفذ", Modifier.weight(1f), numeric = true,
                )
            }
            Spacer(Modifier.height(4.dp))
            CheckRow("وضع توافق الطابعات المقلدة (ESC *)", settings.escAsteriskMode) {
                Store.updateSettings(settings.copy(escAsteriskMode = it))
            }
            CheckRow("قص الورق تلقائياً بعد الطباعة", settings.autoCut) {
                Store.updateSettings(settings.copy(autoCut = it))
            }
        }

        // النسخ الاحتياطي والاستعادة — يحمي من فقدان كل شيء عند تغيير الجوال
        GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.32f)) {
            Text("النسخ الاحتياطي والاستعادة", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(6.dp))
            Text(
                "احفظ كل بياناتك في ملف واحد (القوالب، الكروت المحلية، المبيعات، " +
                    "الباقات، الراوترات، الإعدادات، وصور الخلفيات) واستعدها على أي جهاز.",
                fontSize = 11.sp, color = TextMid,
            )
            Spacer(Modifier.height(11.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GhostButton("حفظ نسخة احتياطية", Modifier.weight(1f), Icons.Filled.Send, color = Lime) {
                    // بناء النسخة (تشفير صور الخلفيات Base64 وكتابة الملف) على خيط خلفي
                    scope.launch {
                        val built = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                            runCatching { Store.writeBackupFile() }
                        }
                        built.onSuccess { f ->
                            runCatching {
                                val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", f)
                                context.startActivity(
                                    android.content.Intent.createChooser(
                                        android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                            type = "application/json"
                                            putExtra(android.content.Intent.EXTRA_STREAM, uri)
                                            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        },
                                        "حفظ / مشاركة النسخة الاحتياطية",
                                    ),
                                )
                            }.onFailure { Toast.makeText(context, "تعذّرت المشاركة: ${it.message}", Toast.LENGTH_LONG).show() }
                        }.onFailure {
                            Toast.makeText(context, "تعذّر إنشاء النسخة: ${it.message}", Toast.LENGTH_LONG).show()
                        }
                    }
                }
                GhostButton("استعادة من ملف", Modifier.weight(1f), Icons.Filled.Router) {
                    runCatching { restoreLauncher.launch("*/*") }
                        .onFailure { Toast.makeText(context, "تعذّر فتح منتقي الملفات", Toast.LENGTH_LONG).show() }
                }
            }
        }

        // الترخيص
        GlassCard(Modifier.fillMaxWidth(), glow = Lime.copy(alpha = 0.3f)) {
            Text("الترخيص", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(8.dp))
            val ls by LicenseManager.state.collectAsState()
            Text(
                when (val s = ls) {
                    is LicenseState.Trial -> "نسخة تجريبية — متبقٍ ${s.daysLeft} يوم"
                    is LicenseState.Licensed ->
                        if (s.lifetime) "مفعّل — ترخيص دائم" else "مفعّل — ${s.plan.labelAr}، متبقٍ ${s.daysLeft} يوم"
                    LicenseState.TrialEnded -> "انتهت التجربة — اطلب ترخيصاً"
                    LicenseState.Expired -> "انتهى الاشتراك"
                    LicenseState.NeedsRegister -> "غير مسجّل — سجّل بريدك لبدء التجربة"
                    LicenseState.Suspended -> "موقوف من مزوّد الخدمة"
                    LicenseState.ClockInvalid -> "ساعة الجهاز غير صحيحة — صحّح التاريخ أو اتصل بالإنترنت"
                },
                fontSize = 12.5.sp,
                color = if (ls is LicenseState.Licensed) Lime else Warn,
            )
            Text("رمز الجهاز: ${LicenseManager.deviceCode()}", fontSize = 11.sp, color = TextLow)
            Spacer(Modifier.height(10.dp))
            GhostButton("إدارة الترخيص", icon = Icons.Filled.VerifiedUser, color = Lime) { onLicense() }
        }

        // تقرير آخر انهيار — لإرساله للمطوّر
        val crash = remember { com.binwaps.cardmanager.data.CrashLogger.lastCrash() }
        if (crash != null) {
            GlassCard(Modifier.fillMaxWidth(), glow = Danger.copy(alpha = 0.4f)) {
                Text("تقرير آخر خروج للتطبيق", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Danger)
                // لا نعرض Stack trace بلغة Java للمستخدم — سطر عربي، والنص الكامل يذهب في «إرسال التقرير»
                val stamp = crash.lineSequence().firstOrNull().orEmpty().take(40)
                Text(
                    "أُغلق التطبيق بشكل غير متوقع" + (if (stamp.isNotBlank()) " ($stamp)" else "") +
                        " — أرسل التقرير للمطوّر ليُعالج السبب.",
                    fontSize = 12.sp, color = TextMid, lineHeight = 18.sp,
                    modifier = Modifier.padding(top = 6.dp),
                )
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    GhostButton("إرسال التقرير", icon = Icons.Filled.Send, color = Danger) {
                        context.startActivity(
                            android.content.Intent.createChooser(
                                android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(android.content.Intent.EXTRA_TEXT, crash)
                                },
                                "إرسال تقرير الخطأ",
                            )
                        )
                    }
                    GhostButton("مسح") { com.binwaps.cardmanager.data.CrashLogger.clear() }
                }
            }
        }

        // سجل العمليات — يوضح أين توقف الاتصال أو الرفع أو الطباعة فعلاً
        val events by com.binwaps.cardmanager.data.EventLog.events.collectAsState()
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.3f)) {
            Text("سجل العمليات", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Text(
                "آخر ما جرى فعلاً: الاتصال، التوليد، الرفع، الطباعة — أرسله عند أي مشكلة",
                fontSize = 11.5.sp, color = TextLow,
            )
            Spacer(Modifier.height(9.dp))
            if (events.isEmpty()) {
                Text("لا عمليات بعد", fontSize = 11.5.sp, color = TextLow)
            } else {
                val fmt = remember { java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US) }
                events.asReversed().take(12).forEach { e ->
                    Row(Modifier.padding(bottom = 4.dp)) {
                        Text(
                            if (e.ok) "✓" else "✗",
                            fontSize = 11.sp,
                            color = if (e.ok) Lime else Danger,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "${fmt.format(java.util.Date(e.at))} [${e.tag}] ${e.text}",
                            fontSize = 11.5.sp,
                            color = if (e.ok) TextMid else Danger,
                        )
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GhostButton("إرسال السجل", icon = Icons.Filled.Send) {
                    context.startActivity(
                        android.content.Intent.createChooser(
                            android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(
                                    android.content.Intent.EXTRA_TEXT,
                                    com.binwaps.cardmanager.data.EventLog.asText(),
                                )
                            },
                            "إرسال سجل العمليات",
                        )
                    )
                }
                GhostButton("مسح") { com.binwaps.cardmanager.data.EventLog.clear() }
            }
        }

        // عن التطبيق — المهندس والمصمم ورقم التواصل
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.28f)) {
            Text("عن التطبيق", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(9.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("تطوير وتصميم", fontSize = 12.5.sp, color = TextMid, modifier = Modifier.weight(1f))
                Text("المهندس علي واقص", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Neon)
            }
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("للتواصل والدعم", fontSize = 12.5.sp, color = TextMid, modifier = Modifier.weight(1f))
                Text("776831921", fontSize = 13.sp, color = TextHi)
            }
            Spacer(Modifier.height(11.dp))
            GhostButton("تواصل عبر واتساب", Modifier.fillMaxWidth(), Icons.Filled.Chat, color = Lime) {
                val msg = "السلام عليكم، بخصوص تطبيق مدير الكروت"
                val wa = android.content.Intent(
                    android.content.Intent.ACTION_VIEW,
                    android.net.Uri.parse("https://wa.me/967776831921?text=" + android.net.Uri.encode(msg)),
                )
                runCatching { context.startActivity(wa) }
            }
        }
        Spacer(Modifier.height(14.dp))

        Text(
            "مدير الكروت — الإصدار ${com.binwaps.cardmanager.BuildConfig.VERSION_NAME}  •  المهندس علي واقص",
            fontSize = 11.sp, color = TextLow,
        )
        Spacer(Modifier.height(24.dp))
    }

    // تأكيد الاستعادة — عملية تستبدل كل البيانات الحالية، فلا بد من تأكيد صريح
    pendingRestore?.let { text ->
        AlertDialog(
            onDismissRequest = { pendingRestore = null },
            containerColor = com.binwaps.cardmanager.ui.theme.Panel,
            titleContentColor = TextHi,
            title = { Text("استعادة نسخة احتياطية", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Text(
                    "سيُستبدل كل ما في التطبيق الآن (القوالب، الكروت المحلية، المبيعات، " +
                        "الباقات، الراوترات، والإعدادات) ببيانات هذا الملف. لا يمكن التراجع. هل تتابع؟",
                    fontSize = 12.5.sp, color = TextMid,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val ok = Store.restoreBackupJson(text)
                    Toast.makeText(
                        context,
                        if (ok) "تمت الاستعادة ✓ — أغلق التطبيق وافتحه من جديد" else "الملف غير صالح",
                        Toast.LENGTH_LONG,
                    ).show()
                    pendingRestore = null
                }) { Text("استعادة", color = Danger, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { pendingRestore = null }) { Text("إلغاء", color = TextLow) }
            },
        )
    }
}

@Composable
private fun CheckRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(
            checked, onChange,
            colors = CheckboxDefaults.colors(
                checkedColor = Neon,
                checkmarkColor = com.binwaps.cardmanager.ui.theme.Ink,
                uncheckedColor = TextLow,
            ),
        )
        Text(label, fontSize = 12.5.sp, color = TextMid)
    }
}
