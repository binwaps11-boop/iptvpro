package com.binwaps.cardmanager.ui.screens

import android.Manifest
import android.os.Build
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
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
import com.binwaps.cardmanager.model.PaperType
import com.binwaps.cardmanager.model.PrintBatch
import com.binwaps.cardmanager.print.PdfExporter
import com.binwaps.cardmanager.print.PrintEngine
import com.binwaps.cardmanager.print.ThermalPrinter
import com.binwaps.cardmanager.ui.components.CardPreview
import com.binwaps.cardmanager.ui.components.sampleUser
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.NeonProgress
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.dantsu.escposprinter.connection.bluetooth.BluetoothConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun PrintScreen(navController: androidx.navigation.NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val users by Store.users.collectAsState()
    val templates by Store.templates.collectAsState()
    val settings by Store.settings.collectAsState()

    var selectedTemplateId by remember { mutableStateOf(templates.firstOrNull()?.id) }
    val template = templates.firstOrNull { it.id == selectedTemplateId } ?: templates.firstOrNull()

    // محرك الطباعة الصامد — يعمل في الخلفية ويستأنف من نقطة التوقف عند أي فشل
    val engineState by PrintEngine.state.collectAsState()
    androidx.compose.runtime.LaunchedEffect(Unit) { PrintEngine.restoreIfAny() }
    val busy = engineState is PrintEngine.State.Running
    val canStart = engineState is PrintEngine.State.Idle || engineState is PrintEngine.State.Done
    var showPrinterPicker by remember { mutableStateOf(false) }
    var printers by remember { mutableStateOf<List<BluetoothConnection>>(emptyList()) }
    var heightMm by remember { mutableFloatStateOf(settings.thermalCardHeightMm) }
    /** الاختيار القادم للطابعة هو استئناف لمهمة محفوظة، لا بداية جديدة */
    var thermalResumeMode by remember { mutableStateOf(false) }
    var htmlBusy by remember { mutableStateOf(false) }

    fun saveBatch() {
        val t = template ?: return
        // نسجّل ما طُبع فعلاً — بعد تطبيق نطاق "من كرت … إلى كرت …"
        val printed = PdfExporter.selectRange(users, Store.settings.value)
        Store.addBatch(
            PrintBatch(
                id = Store.newId(),
                createdAt = System.currentTimeMillis(),
                templateId = t.id,
                templateName = t.name,
                profile = printed.firstOrNull()?.profile ?: "",
                unitPrice = printed.firstOrNull()?.price ?: "",
                paper = Store.settings.value.paperType,
                users = printed,
            )
        )
    }

    val btPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        if (granted.values.all { it }) {
            printers = ThermalPrinter.pairedPrinters()
            showPrinterPicker = true
        } else {
            Toast.makeText(context, "يجب السماح بصلاحية البلوتوث", Toast.LENGTH_LONG).show()
        }
    }

    fun openPrinterPicker() {
        if (Build.VERSION.SDK_INT >= 31) {
            btPermission.launch(arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN))
        } else {
            printers = ThermalPrinter.pairedPrinters()
            showPrinterPicker = true
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        SectionHeader("الطباعة والتصدير", "${users.size} كرت جاهز للطباعة", Icons.Filled.Print)
        Spacer(Modifier.height(14.dp))

        if (users.isEmpty()) {
            EmptyState(Icons.Filled.Print, "لا توجد كروت للطباعة", "ولّد أو استورد كروتاً من قسم الكروت أولاً")
        }


        // اختيار القالب
        Text("القالب", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(7.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            templates.forEach { t ->
                val on = t.id == template?.id
                Text(
                    t.name, fontSize = 12.sp,
                    color = if (on) Neon else TextMid,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier
                        .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                        .clickable { selectedTemplateId = t.id }
                        .padding(horizontal = 13.dp, vertical = 7.dp),
                )
            }
        }

        Spacer(Modifier.height(12.dp))
        template?.let { t ->
            GlassCard(Modifier.fillMaxWidth(), padding = 10) {
                CardPreview(template = t, user = users.firstOrNull() ?: sampleUser, modifier = Modifier.fillMaxWidth())
            }
        }

        Spacer(Modifier.height(16.dp))
        Text("نوع الطباعة", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(7.dp))
        PaperType.entries.forEach { p ->
            val on = settings.paperType == p
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 6.dp)
                    .background(if (on) Neon.copy(alpha = 0.08f) else Panel, RoundedCornerShape(13.dp))
                    .border(1.dp, if (on) Neon.copy(alpha = 0.45f) else Stroke, RoundedCornerShape(13.dp))
                    .clickable { Store.updateSettings(settings.copy(paperType = p)) }
                    .padding(horizontal = 13.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(16.dp)
                        .background(if (on) Neon else Panel, CircleShape)
                        .border(1.dp, if (on) Neon else Stroke, CircleShape)
                )
                Spacer(Modifier.width(10.dp))
                Text(p.labelAr, fontSize = 13.5.sp, color = if (on) TextHi else TextMid)
            }
        }

        if (settings.paperType != PaperType.A4) {
            Spacer(Modifier.height(6.dp))
            Text("ارتفاع الكرت: ${heightMm.toInt()} مم", fontSize = 12.5.sp, color = TextHi)
            Slider(
                value = heightMm,
                onValueChange = { heightMm = it },
                onValueChangeFinished = { Store.updateSettings(settings.copy(thermalCardHeightMm = heightMm)) },
                valueRange = 20f..120f,
                colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
            )
        }

        // تخطيط الصفحة — متاح دائماً للطباعة الورقية
        if (settings.paperType == PaperType.A4 && template != null) {
            val info = remember(template, settings.layout, users.size) {
                PdfExporter.computeLayout(template, settings, users.size)
            }
            Spacer(Modifier.height(12.dp))
            GlassCard(
                Modifier.fillMaxWidth().clickable { navController.navigate("layout/${template.id}") },
                glow = Violet.copy(alpha = 0.45f), padding = 14,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.GridView, null, tint = Violet, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(11.dp))
                    Column(Modifier.weight(1f)) {
                        Text("تخطيط الصفحة", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                        Text(
                            "${info.columns} بالعرض × ${info.rows} بالطول = ${info.perPage} كرت في الصفحة",
                            fontSize = 12.sp, color = Neon,
                        )
                        Text(
                            "${settings.layout.paper.labelAr} ${settings.layout.orientation.labelAr} • " +
                                "${info.pages} صفحة • الكرت ${info.cardWidthMm.toInt()}×${info.cardHeightMm.toInt()} مم",
                            fontSize = 10.5.sp, color = TextLow,
                        )
                    }
                    Text("تعديل ‹", fontSize = 13.sp, color = Violet, fontWeight = FontWeight.Bold)
                }
            }
        }

        // بطاقة حالة المحرك — التقدم، الفشل القابل للاستئناف، الاكتمال
        when (val es = engineState) {
            is PrintEngine.State.Running -> {
                Spacer(Modifier.height(10.dp))
                GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.4f), padding = 12) {
                    Text(es.label, fontSize = 12.5.sp, color = TextHi, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(7.dp))
                    NeonProgress(es.done.toFloat() / es.total.coerceAtLeast(1))
                    Spacer(Modifier.height(6.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "يمكنك مغادرة الشاشة — الطباعة تستمر في الخلفية",
                            fontSize = 10.5.sp, color = TextLow, modifier = Modifier.weight(1f),
                        )
                        Text(
                            "إيقاف",
                            fontSize = 12.sp, color = com.binwaps.cardmanager.ui.theme.Danger,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.clickable { PrintEngine.cancel() }.padding(6.dp),
                        )
                    }
                }
            }
            is PrintEngine.State.Failed -> {
                Spacer(Modifier.height(10.dp))
                GlassCard(Modifier.fillMaxWidth(), glow = com.binwaps.cardmanager.ui.theme.Danger.copy(alpha = 0.5f), padding = 12) {
                    Text("توقفت الطباعة — ولم يضِع شيء", fontSize = 13.sp, color = TextHi, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(5.dp))
                    Text(es.error, fontSize = 11.5.sp, color = TextMid)
                    Spacer(Modifier.height(9.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NeonButton("استئناف من نقطة التوقف") {
                            if (es.kind == PrintEngine.Kind.THERMAL) {
                                // الاتصال القديم قد يكون مقطوعاً — نعيد اختيار الطابعة
                                thermalResumeMode = true
                                openPrinterPicker()
                            } else {
                                PrintEngine.resume(context)
                            }
                        }
                        GhostButton("إلغاء المهمة", color = com.binwaps.cardmanager.ui.theme.Danger) {
                            PrintEngine.cancel()
                        }
                    }
                }
            }
            is PrintEngine.State.Restorable -> {
                Spacer(Modifier.height(10.dp))
                GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.5f), padding = 12) {
                    Text("لديك طباعة غير مكتملة من جلسة سابقة", fontSize = 13.sp, color = TextHi, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(5.dp))
                    Text("اكتمل ${es.done} من ${es.total} — يمكن المتابعة من مكان التوقف", fontSize = 11.5.sp, color = TextMid)
                    Spacer(Modifier.height(9.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NeonButton("استئناف") {
                            if (es.kind == PrintEngine.Kind.THERMAL) {
                                thermalResumeMode = true
                                openPrinterPicker()
                            } else {
                                PrintEngine.resumeRestored(context)
                            }
                        }
                        GhostButton("تجاهل") { PrintEngine.dismissRestored() }
                    }
                }
            }
            is PrintEngine.State.Done -> {
                Spacer(Modifier.height(10.dp))
                GlassCard(Modifier.fillMaxWidth(), glow = com.binwaps.cardmanager.ui.theme.Lime.copy(alpha = 0.5f), padding = 12) {
                    Text("✓ اكتملت الطباعة — ${es.total} كرت", fontSize = 13.sp, color = com.binwaps.cardmanager.ui.theme.Lime, fontWeight = FontWeight.Bold)
                    if (es.files.isNotEmpty()) {
                        Spacer(Modifier.height(9.dp))
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NeonButton("مشاركة الملف") { PdfExporter.shareAll(context, es.files) }
                            GhostButton("طباعة عبر النظام") {
                                es.files.forEach { PdfExporter.printViaSystem(context, it) }
                            }
                            GhostButton("تم") { PrintEngine.acknowledge() }
                        }
                    } else {
                        Spacer(Modifier.height(7.dp))
                        GhostButton("تم") { PrintEngine.acknowledge() }
                    }
                }
            }
            else -> {}
        }

        Spacer(Modifier.height(16.dp))

        if (settings.paperType == PaperType.A4) {
            NeonButton("إنشاء PDF — ملف واحد لكل الكروت", Modifier.fillMaxWidth(), Icons.Filled.Share, enabled = canStart && template != null) {
                val t0 = template ?: return@NeonButton
                val issues = PrintEngine.preflight(t0, users, settings, thermal = false)
                if (issues.isNotEmpty()) {
                    Toast.makeText(context, issues.first(), Toast.LENGTH_LONG).show()
                    return@NeonButton
                }
                PrintEngine.startPdf(context, t0, users, settings)
            }
            Spacer(Modifier.height(5.dp))
            Text(
                "ملف PDF واحد يضم كل الكروت مهما كان عددها — يكتمل في ثوانٍ، " +
                    "وأي خطأ يُعالج بضغطة استئناف بلا إعادة من البداية.",
                fontSize = 10.sp, color = TextLow,
            )
            Spacer(Modifier.height(9.dp))
            GhostButton("صفحة HTML للطباعة من المتصفح", Modifier.fillMaxWidth(), enabled = !busy && !htmlBusy && template != null) {
                val t0 = template ?: return@GhostButton
                htmlBusy = true
                scope.launch {
                    try {
                        val file = withContext(Dispatchers.IO) {
                            com.binwaps.cardmanager.print.HtmlExporter.export(context, t0, users, settings)
                        }
                        saveBatch()
                        com.binwaps.cardmanager.print.HtmlExporter.open(context, file)
                    } catch (e: Exception) {
                        Toast.makeText(context, "فشل التصدير: ${e.message}", Toast.LENGTH_LONG).show()
                    } finally {
                        htmlBusy = false
                    }
                }
            }
            Spacer(Modifier.height(5.dp))
            Text(
                "صفحة HTML تُفتح في أي متصفح على الجوال أو الكمبيوتر وتُطبع منه بنفس المقاسات — " +
                    "مفيدة لإرسال الكروت لشخص آخر ليطبعها. رمز QR يظهر في PDF فقط.",
                fontSize = 10.sp, color = TextLow,
            )
        } else {
            NeonButton("طباعة عبر البلوتوث", Modifier.fillMaxWidth(), Icons.Filled.Bluetooth, enabled = canStart) {
                val issues = PrintEngine.preflight(template, users, settings, thermal = true)
                if (issues.isNotEmpty()) {
                    Toast.makeText(context, issues.first(), Toast.LENGTH_LONG).show()
                    return@NeonButton
                }
                thermalResumeMode = false
                openPrinterPicker()
            }
            Spacer(Modifier.height(5.dp))
            Text(
                "كل كرت له ثلاث محاولات بإعادة اتصال تلقائية — انقطاع البلوتوث لا يفشل الدفعة، " +
                    "وعند التوقف تستأنف من الكرت نفسه.",
                fontSize = 10.sp, color = TextLow,
            )
            if (settings.tcpPrinterIp.isNotBlank()) {
                Spacer(Modifier.height(9.dp))
                GhostButton(
                    "طباعة عبر الشبكة (${settings.tcpPrinterIp})",
                    Modifier.fillMaxWidth(), Icons.Filled.Lan, color = Violet, enabled = !busy,
                ) {
                    val t0 = template ?: return@GhostButton
                    val issues = PrintEngine.preflight(t0, users, settings, thermal = true)
                    if (issues.isNotEmpty()) {
                        Toast.makeText(context, issues.first(), Toast.LENGTH_LONG).show()
                        return@GhostButton
                    }
                    val ip = settings.tcpPrinterIp
                    val port = settings.tcpPrinterPort
                    PrintEngine.startThermal(context, t0, users, settings) {
                        ThermalPrinter.tcpPrinter(ip, port)
                    }
                }
            }
        }

        Spacer(Modifier.height(30.dp))
    }

    if (showPrinterPicker) {
        AlertDialog(
            onDismissRequest = { showPrinterPicker = false },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("اختر الطابعة", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (printers.isEmpty()) {
                        Text(
                            "لا توجد طابعات مقترنة.\nاقرن الطابعة من إعدادات البلوتوث في جوالك ثم أعد المحاولة.",
                            fontSize = 12.5.sp, color = TextMid,
                        )
                    }
                    printers.forEach { p ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .background(Neon.copy(alpha = 0.07f), RoundedCornerShape(11.dp))
                                .clickable {
                                    if (busy) return@clickable   // منع طباعة مزدوجة بلمستين سريعتين
                                    val t0 = template ?: return@clickable
                                    showPrinterPicker = false
                                    if (thermalResumeMode) {
                                        thermalResumeMode = false
                                        PrintEngine.resumeThermalWith(context) { p }
                                    } else {
                                        PrintEngine.startThermal(context, t0, users, Store.settings.value) { p }
                                    }
                                }
                                .padding(13.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.Bluetooth, null, tint = Neon, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(9.dp))
                            Text(
                                runCatching { p.device.name ?: "طابعة" }.getOrDefault("طابعة"),
                                fontSize = 13.5.sp, color = TextHi,
                            )
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { showPrinterPicker = false }) { Text("إغلاق", color = TextLow) } },
        )
    }
}
