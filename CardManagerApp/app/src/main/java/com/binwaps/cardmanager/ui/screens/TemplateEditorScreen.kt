package com.binwaps.cardmanager.ui.screens

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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.gestures.detectDragGestures
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.QrContent
import com.binwaps.cardmanager.ui.components.CardPreview
import kotlin.math.abs

private val presetColors = listOf(
    0xFF000000, 0xFFFFFFFF, 0xFF0B5E4F, 0xFFB71C1C, 0xFF1565C0,
    0xFFF57F17, 0xFF4A148C, 0xFF33691E, 0xFF37474F,
)

@Composable
fun TemplateEditorScreen(templateId: Long, onDone: () -> Unit) {
    val context = LocalContext.current
    var template by remember { mutableStateOf(Store.template(templateId) ?: Store.defaultTemplate()) }
    var selectedFieldId by remember { mutableStateOf<Long?>(null) }
    var previewSize by remember { mutableStateOf(IntSize.Zero) }
    var showAddField by remember { mutableStateOf(false) }

    val selected = template.fields.firstOrNull { it.id == selectedFieldId }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            Store.importBackground(uri)?.let { path ->
                template = template.copy(backgroundPath = path)
            }
        }
    }

    fun updateField(f: CardField) {
        template = template.copy(fields = template.fields.map { if (it.id == f.id) f else it })
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("محرر القالب", fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Button(onClick = {
                Store.upsertTemplate(template)
                onDone()
            }) {
                Icon(Icons.Filled.Save, null); Spacer(Modifier.width(4.dp)); Text("حفظ")
            }
        }

        OutlinedTextField(
            value = template.name,
            onValueChange = { template = template.copy(name = it) },
            label = { Text("اسم القالب") },
            modifier = Modifier.fillMaxWidth(),
        )

        // المعاينة مع السحب لتحريك الحقول
        Card {
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
                    .onSizeChanged { previewSize = it }
                    .pointerInput(template.id, previewSize) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                if (previewSize.width == 0) return@detectDragGestures
                                val w = previewSize.width.toFloat()
                                val h = w * template.heightMm / template.widthMm
                                val nearest = template.fields.minByOrNull { f ->
                                    abs(f.xFrac * w - offset.x) + abs(f.yFrac * h - offset.y)
                                }
                                if (nearest != null) {
                                    val dist = abs(nearest.xFrac * w - offset.x) + abs(nearest.yFrac * h - offset.y)
                                    if (dist < w * 0.25f) selectedFieldId = nearest.id
                                }
                            },
                            onDrag = { change, drag ->
                                change.consume()
                                val f = template.fields.firstOrNull { it.id == selectedFieldId } ?: return@detectDragGestures
                                if (previewSize.width == 0) return@detectDragGestures
                                val w = previewSize.width.toFloat()
                                val h = w * template.heightMm / template.widthMm
                                updateField(
                                    f.copy(
                                        xFrac = (f.xFrac + drag.x / w).coerceIn(0f, 1f),
                                        yFrac = (f.yFrac + drag.y / h).coerceIn(0f, 1f),
                                    )
                                )
                            },
                        )
                    }
            ) {
                CardPreview(template = template, modifier = Modifier.fillMaxWidth())
            }
        }
        Text("اسحب أي حقل على الكرت لتحريكه", fontSize = 12.sp, color = Color.Gray)

        // شريط الحقول
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            template.fields.forEach { f ->
                FilterChip(
                    selected = f.id == selectedFieldId,
                    onClick = { selectedFieldId = if (selectedFieldId == f.id) null else f.id },
                    label = { Text(if (f.type == FieldType.CUSTOM_TEXT && f.customText.isNotBlank()) f.customText.take(10) else f.type.labelAr, fontSize = 11.sp) },
                )
            }
            FilterChip(selected = false, onClick = { showAddField = true }, label = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Add, null, Modifier.size(14.dp)); Text("إضافة حقل", fontSize = 11.sp)
                }
            })
        }

        // خصائص الحقل المحدد
        if (selected != null) {
            Card {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("حقل: ${selected.type.labelAr}", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        IconButton(onClick = {
                            template = template.copy(fields = template.fields.filterNot { it.id == selected.id })
                            selectedFieldId = null
                        }) { Icon(Icons.Filled.Delete, "حذف", tint = Color.Red) }
                    }
                    if (selected.type == FieldType.CUSTOM_TEXT) {
                        OutlinedTextField(
                            value = selected.customText,
                            onValueChange = { updateField(selected.copy(customText = it)) },
                            label = { Text("النص") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    } else if (selected.type != FieldType.QR_CODE) {
                        OutlinedTextField(
                            value = selected.prefix,
                            onValueChange = { updateField(selected.copy(prefix = it)) },
                            label = { Text("نص قبل القيمة (مثل: المستخدم:)") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    Text("الحجم", fontSize = 13.sp)
                    Slider(
                        value = selected.sizeFrac,
                        onValueChange = { updateField(selected.copy(sizeFrac = it)) },
                        valueRange = 0.03f..if (selected.type == FieldType.QR_CODE) 0.95f else 0.30f,
                    )
                    if (selected.type != FieldType.QR_CODE) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(selected.bold, { updateField(selected.copy(bold = it)) })
                            Text("خط عريض")
                        }
                        Text("اللون", fontSize = 13.sp)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            presetColors.forEach { c ->
                                Box(
                                    Modifier
                                        .size(28.dp)
                                        .background(Color(c), CircleShape)
                                        .border(
                                            if (selected.color == c) 3.dp else 1.dp,
                                            if (selected.color == c) Color(0xFF0B5E4F) else Color.LightGray,
                                            CircleShape,
                                        )
                                        .clickable { updateField(selected.copy(color = c)) }
                                )
                            }
                        }
                    }
                }
            }
        }

        // خصائص القالب
        Card {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("إعدادات الكرت", fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = template.widthMm.toString(),
                        onValueChange = { it.toFloatOrNull()?.let { v -> template = template.copy(widthMm = v.coerceIn(20f, 210f)) } },
                        label = { Text("العرض مم") }, modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = template.heightMm.toString(),
                        onValueChange = { it.toFloatOrNull()?.let { v -> template = template.copy(heightMm = v.coerceIn(20f, 297f)) } },
                        label = { Text("الارتفاع مم") }, modifier = Modifier.weight(1f),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { imagePicker.launch("image/*") }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.Image, null); Spacer(Modifier.width(4.dp)); Text("رفع خلفية من الجوال", fontSize = 12.sp)
                    }
                    if (template.backgroundPath.isNotBlank()) {
                        OutlinedButton(onClick = { template = template.copy(backgroundPath = "") }) {
                            Text("إزالة الخلفية", fontSize = 12.sp)
                        }
                    }
                }
                Text("لون الخلفية", fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(0xFFFFFFFF, 0xFFFFF8E1, 0xFFE8F5E9, 0xFFE3F2FD, 0xFFFCE4EC, 0xFFF3E5F5).forEach { c ->
                        Box(
                            Modifier
                                .size(28.dp)
                                .background(Color(c), CircleShape)
                                .border(
                                    if (template.backgroundColor == c) 3.dp else 1.dp,
                                    if (template.backgroundColor == c) Color(0xFF0B5E4F) else Color.LightGray,
                                    CircleShape,
                                )
                                .clickable { template = template.copy(backgroundColor = c) }
                        )
                    }
                }
                Text("محتوى رمز QR", fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    QrContent.entries.forEach { q ->
                        FilterChip(
                            selected = template.qrContent == q,
                            onClick = { template = template.copy(qrContent = q) },
                            label = { Text(q.labelAr, fontSize = 11.sp) },
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }

    if (showAddField) {
        AlertDialog(
            onDismissRequest = { showAddField = false },
            title = { Text("إضافة حقل") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    FieldType.entries.forEach { type ->
                        TextButton(onClick = {
                            val f = CardField(
                                id = Store.newId(),
                                type = type,
                                sizeFrac = if (type == FieldType.QR_CODE) 0.45f else 0.10f,
                                customText = if (type == FieldType.CUSTOM_TEXT) "نص جديد" else "",
                            )
                            template = template.copy(fields = template.fields + f)
                            selectedFieldId = f.id
                            showAddField = false
                        }, modifier = Modifier.fillMaxWidth()) {
                            Text(type.labelAr)
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { showAddField = false }) { Text("إلغاء") } },
        )
    }
}
