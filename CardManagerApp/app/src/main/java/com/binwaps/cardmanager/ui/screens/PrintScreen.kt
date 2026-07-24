package com.binwaps.cardmanager.ui.screens

import android.Manifest
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.PaperType
import com.binwaps.cardmanager.print.PdfExporter
import com.binwaps.cardmanager.print.ThermalPrinter
import com.binwaps.cardmanager.ui.components.CardPreview
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
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("الطباعة والتصدير", fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text("عدد الكروت الجاهزة: ${users.size}", color = Color.Gray, fontSize = 13.sp)

        Text("اختر القالب", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            templates.forEach { t ->
                FilterChip(
                    selected = t.id == template?.id,
                    onClick = { selectedTemplateId = t.id },
                    label = { Text(t.name, fontSize = 12.sp) },
                )
            }
        }

        template?.let { t ->
            Card { CardPreview(template = t, modifier = Modifier.fillMaxWidth().padding(8.dp)) }
        }

        Text("نوع الطباعة", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            PaperType.entries.forEach { p ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = settings.paperType == p,
                        onCheckedChange = { Store.updateSettings(settings.copy(paperType = p)) },
                    )
                    Text(p.labelAr, fontSize = 14.sp)
                }
            }
        }

        if (settings.paperType != PaperType.A4) {
            Text("ارتفاع الكرت على الطابعة الحرارية: ${heightMm.toInt()} مم", fontSize = 13.sp)
            Slider(
                value = heightMm,
                onValueChange = { heightMm = it },
                onValueChangeFinished = { Store.updateSettings(settings.copy(thermalCardHeightMm = heightMm)) },
                valueRange = 20f..120f,
            )
        }

        progress?.let { (done, total) ->
            LinearProgressIndicator(progress = { done.toFloat() / total }, modifier = Modifier.fillMaxWidth())
            Text("طباعة $done من $total", fontSize = 12.sp, color = Color.Gray)
        }

        if (settings.paperType == PaperType.A4) {
            Button(
                enabled = !busy && users.isNotEmpty() && template != null,
                onClick = {
                    busy = true
                    scope.launch {
                        val file = withContext(Dispatchers.IO) { PdfExporter.export(context, template!!, users, settings) }
                        busy = false
                        PdfExporter.share(context, file)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Share, null); Spacer(Modifier.width(6.dp)); Text("تصدير PDF ومشاركته")
            }
            OutlinedButton(
                enabled = !busy && users.isNotEmpty() && template != null,
                onClick = {
                    busy = true
                    scope.launch {
                        val file = withContext(Dispatchers.IO) { PdfExporter.export(context, template!!, users, settings) }
                        busy = false
                        PdfExporter.printViaSystem(context, file)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Print, null); Spacer(Modifier.width(6.dp)); Text("طباعة عبر النظام (WiFi/USB)")
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(settings.cutMarks, { Store.updateSettings(settings.copy(cutMarks = it)) })
                Text("علامات قص حول الكروت", fontSize = 13.sp)
            }
        } else {
            Button(
                enabled = !busy && users.isNotEmpty() && template != null,
                onClick = { openPrinterPicker() },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Bluetooth, null); Spacer(Modifier.width(6.dp)); Text("طباعة عبر البلوتوث")
            }
            if (settings.tcpPrinterIp.isNotBlank()) {
                OutlinedButton(
                    enabled = !busy && users.isNotEmpty() && template != null,
                    onClick = {
                        busy = true
                        progress = 0 to users.size
                        scope.launch {
                            val conn = ThermalPrinter.tcpPrinter(settings.tcpPrinterIp, settings.tcpPrinterPort)
                            val r = ThermalPrinter.printCards(conn, template!!, users, Store.settings.value) { done, total ->
                                progress = done to total
                            }
                            busy = false
                            progress = null
                            r.onSuccess {
                                Toast.makeText(context, "تمت طباعة $it كرت", Toast.LENGTH_LONG).show()
                            }.onFailure {
                                Toast.makeText(context, "فشل الطباعة: ${it.message}", Toast.LENGTH_LONG).show()
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.Print, null); Spacer(Modifier.width(6.dp))
                    Text("طباعة عبر الشبكة (${settings.tcpPrinterIp})")
                }
            }
        }

        if (users.isEmpty()) {
            Text("لا يوجد مستخدمون بعد — أضفهم من تبويب المستخدمين", color = Color(0xFFB71C1C), fontSize = 13.sp)
        }
        Spacer(Modifier.height(30.dp))
    }

    if (showPrinterPicker) {
        AlertDialog(
            onDismissRequest = { showPrinterPicker = false },
            title = { Text("اختر الطابعة") },
            text = {
                Column {
                    if (printers.isEmpty()) {
                        Text("لا توجد طابعات مقترنة. اقرن الطابعة من إعدادات البلوتوث أولاً.")
                    }
                    printers.forEach { p ->
                        TextButton(onClick = {
                            showPrinterPicker = false
                            busy = true
                            progress = 0 to users.size
                            scope.launch {
                                val r = ThermalPrinter.printCards(p, template!!, users, Store.settings.value) { done, total ->
                                    progress = done to total
                                }
                                busy = false
                                progress = null
                                r.onSuccess {
                                    Toast.makeText(context, "تمت طباعة $it كرت", Toast.LENGTH_LONG).show()
                                }.onFailure {
                                    Toast.makeText(context, "فشل الطباعة: ${it.message}", Toast.LENGTH_LONG).show()
                                }
                            }
                        }, modifier = Modifier.fillMaxWidth()) {
                            Text(runCatching { p.device.name ?: "طابعة" }.getOrDefault("طابعة"))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { showPrinterPicker = false }) { Text("إلغاء") } },
        )
    }
}
