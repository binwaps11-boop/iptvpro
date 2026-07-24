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
import com.binwaps.cardmanager.print.ThermalPrinter
import com.binwaps.cardmanager.ui.components.CardPreview
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
fun PrintScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val users by Store.users.collectAsState()
    val templates by Store.templates.collectAsState()
    val settings by Store.settings.collectAsState()

    var selectedTemplateId by remember { mutableStateOf(templates.firstOrNull()?.id) }
    val template = templates.firstOrNull { it.id == selectedTemplateId } ?: templates.firstOrNull()

    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var showPrinterPicker by remember { mutableStateOf(false) }
    var printers by remember { mutableStateOf<List<BluetoothConnection>>(emptyList()) }
    var heightMm by remember { mutableFloatStateOf(settings.thermalCardHeightMm) }

    fun saveBatch() {
        val t = template ?: return
        Store.addBatch(
            PrintBatch(
                id = Store.newId(),
                createdAt = System.currentTimeMillis(),
                templateId = t.id,
                templateName = t.name,
                profile = users.firstOrNull()?.profile ?: "",
                unitPrice = users.firstOrNull()?.price ?: "",
                paper = Store.settings.value.paperType,
                users = users,
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
            EmptyState(Icons.Filled.Print, "لا توجد كروت للطباعة", "ولّد أو استورد كروتاً من تبويب الكروت أولاً")
            return@Column
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
                CardPreview(template = t, user = users.first(), modifier = Modifier.fillMaxWidth())
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
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(
                    settings.cutMarks, { Store.updateSettings(settings.copy(cutMarks = it)) },
                    colors = CheckboxDefaults.colors(checkedColor = Neon, checkmarkColor = com.binwaps.cardmanager.ui.theme.Ink),
                )
                Text("علامات قص حول الكروت", fontSize = 12.5.sp, color = TextMid)
            }
        }

        progress?.let { (done, total) ->
            Spacer(Modifier.height(10.dp))
            NeonProgress(done.toFloat() / total.coerceAtLeast(1))
            Spacer(Modifier.height(4.dp))
            Text("جاري الطباعة: $done من $total", fontSize = 12.sp, color = Neon)
        }

        Spacer(Modifier.height(16.dp))

        if (settings.paperType == PaperType.A4) {
            NeonButton("تصدير PDF ومشاركته", Modifier.fillMaxWidth(), Icons.Filled.Share, enabled = !busy) {
                busy = true
                scope.launch {
                    val file = withContext(Dispatchers.IO) { PdfExporter.export(context, template!!, users, settings) }
                    busy = false
                    saveBatch()
                    PdfExporter.share(context, file)
                }
            }
            Spacer(Modifier.height(9.dp))
            GhostButton("طباعة عبر النظام (WiFi/USB)", Modifier.fillMaxWidth(), Icons.Filled.Print, enabled = !busy) {
                busy = true
                scope.launch {
                    val file = withContext(Dispatchers.IO) { PdfExporter.export(context, template!!, users, settings) }
                    busy = false
                    saveBatch()
                    PdfExporter.printViaSystem(context, file)
                }
            }
        } else {
            NeonButton("طباعة عبر البلوتوث", Modifier.fillMaxWidth(), Icons.Filled.Bluetooth, enabled = !busy) {
                openPrinterPicker()
            }
            if (settings.tcpPrinterIp.isNotBlank()) {
                Spacer(Modifier.height(9.dp))
                GhostButton(
                    "طباعة عبر الشبكة (${settings.tcpPrinterIp})",
                    Modifier.fillMaxWidth(), Icons.Filled.Lan, color = Violet, enabled = !busy,
                ) {
                    busy = true; progress = 0 to users.size
                    scope.launch {
                        val conn = ThermalPrinter.tcpPrinter(settings.tcpPrinterIp, settings.tcpPrinterPort)
                        ThermalPrinter.printCards(conn, template!!, users, Store.settings.value) { d, t -> progress = d to t }
                            .onSuccess { saveBatch(); Toast.makeText(context, "تمت طباعة $it كرت", Toast.LENGTH_LONG).show() }
                            .onFailure { Toast.makeText(context, "فشل الطباعة: ${it.message}", Toast.LENGTH_LONG).show() }
                        busy = false; progress = null
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
                                    showPrinterPicker = false
                                    busy = true; progress = 0 to users.size
                                    scope.launch {
                                        ThermalPrinter.printCards(p, template!!, users, Store.settings.value) { d, t -> progress = d to t }
                                            .onSuccess { saveBatch(); Toast.makeText(context, "تمت طباعة $it كرت", Toast.LENGTH_LONG).show() }
                                            .onFailure { Toast.makeText(context, "فشل الطباعة: ${it.message}", Toast.LENGTH_LONG).show() }
                                        busy = false; progress = null
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
