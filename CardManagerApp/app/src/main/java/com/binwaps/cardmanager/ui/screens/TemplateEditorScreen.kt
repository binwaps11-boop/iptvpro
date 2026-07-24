package com.binwaps.cardmanager.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.QrContent
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.CardPreview
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import kotlin.math.abs

private val textColors = listOf(
    0xFF000000, 0xFFFFFFFF, 0xFF0B5E4F, 0xFFB71C1C, 0xFF1565C0,
    0xFFF57F17, 0xFF4A148C, 0xFF33691E, 0xFF37474F, 0xFF00838F,
)

private val cardColors = listOf(
    0xFFFFFFFF, 0xFFFFF8E1, 0xFFE8F5E9, 0xFFE3F2FD, 0xFFFCE4EC,
    0xFFF3E5F5, 0xFF212121, 0xFF0B5E4F, 0xFF1A237E,
)

@Composable
fun TemplateEditorScreen(templateId: Long, onDone: () -> Unit) {
    var template by remember { mutableStateOf(Store.template(templateId) ?: Store.defaultTemplate()) }
    var selectedFieldId by remember { mutableStateOf<Long?>(null) }
    var previewSize by remember { mutableStateOf(IntSize.Zero) }
    var showAddField by remember { mutableStateOf(false) }

    val selected = template.fields.firstOrNull { it.id == selectedFieldId }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            Store.importBackground(uri)?.let { path -> template = template.copy(backgroundPath = path) }
        }
    }

    fun updateField(f: CardField) {
        template = template.copy(fields = template.fields.map { if (it.id == f.id) f else it })
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDone) { Icon(Icons.Filled.ArrowForward, "رجوع", tint = TextMid) }
            Text("محرر القالب", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextHi, modifier = Modifier.weight(1f))
            Box(Modifier.width(110.dp)) {
                NeonButton("حفظ", icon = Icons.Filled.Save) {
                    Store.upsertTemplate(template)
                    onDone()
                }
            }
        }

        AppField(template.name, { template = template.copy(name = it) }, "اسم القالب", Modifier.fillMaxWidth())

        // المعاينة الحية مع السحب
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 10) {
            Box(
                Modifier
                    .fillMaxWidth()
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
                                    if (dist < w * 0.3f) selectedFieldId = nearest.id
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
        Text("اضغط على الحقل ثم اسحبه لتحريكه على الكرت", fontSize = 11.5.sp, color = TextLow)

        // شريط الحقول
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            template.fields.forEach { f ->
                val on = f.id == selectedFieldId
                Text(
                    if (f.type == FieldType.CUSTOM_TEXT && f.customText.isNotBlank()) f.customText.take(12) else f.type.labelAr,
                    fontSize = 11.sp,
                    color = if (on) Neon else TextMid,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier
                        .background(if (on) Neon.copy(alpha = 0.13f) else Panel, RoundedCornerShape(999.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                        .clickable { selectedFieldId = if (on) null else f.id }
                        .padding(horizontal = 11.dp, vertical = 6.dp),
                )
            }
            Row(
                Modifier
                    .background(Neon.copy(alpha = 0.10f), RoundedCornerShape(999.dp))
                    .clickable { showAddField = true }
                    .padding(horizontal = 11.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Add, null, tint = Neon, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(3.dp))
                Text("إضافة حقل", fontSize = 11.sp, color = Neon)
            }
        }

        // خصائص الحقل المحدد
        if (selected != null) {
            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.3f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("حقل: ${selected.type.labelAr}", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi, modifier = Modifier.weight(1f))
                    IconButton(onClick = {
                        template = template.copy(fields = template.fields.filterNot { it.id == selected.id })
                        selectedFieldId = null
                    }) { Icon(Icons.Filled.Delete, "حذف", tint = Danger, modifier = Modifier.size(19.dp)) }
                }
                Spacer(Modifier.height(6.dp))
                if (selected.type == FieldType.CUSTOM_TEXT) {
                    AppField(selected.customText, { updateField(selected.copy(customText = it)) }, "النص", Modifier.fillMaxWidth())
                } else if (selected.type != FieldType.QR_CODE) {
                    AppField(selected.prefix, { updateField(selected.copy(prefix = it)) }, "نص قبل القيمة (مثل: المستخدم:)", Modifier.fillMaxWidth())
                }
                Spacer(Modifier.height(6.dp))
                Text("الحجم", fontSize = 12.sp, color = TextLow)
                Slider(
                    value = selected.sizeFrac,
                    onValueChange = { updateField(selected.copy(sizeFrac = it)) },
                    valueRange = 0.03f..if (selected.type == FieldType.QR_CODE) 0.95f else 0.32f,
                    colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
                )
                if (selected.type != FieldType.QR_CODE) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("خط عريض", fontSize = 12.sp, color = TextMid, modifier = Modifier.weight(1f))
                        Text(
                            if (selected.bold) "مفعّل" else "معطّل",
                            fontSize = 11.5.sp,
                            color = if (selected.bold) Neon else TextLow,
                            modifier = Modifier
                                .background(
                                    if (selected.bold) Neon.copy(alpha = 0.12f) else Panel,
                                    RoundedCornerShape(999.dp),
                                )
                                .clickable { updateField(selected.copy(bold = !selected.bold)) }
                                .padding(horizontal = 12.dp, vertical = 5.dp),
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text("لون النص", fontSize = 12.sp, color = TextLow)
                    Spacer(Modifier.height(6.dp))
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        textColors.forEach { c ->
                            ColorDot(c, selected.color == c) { updateField(selected.copy(color = c)) }
                        }
                    }
                }
            }
        }

        // إعدادات الكرت
        GlassCard(Modifier.fillMaxWidth()) {
            Text("إعدادات الكرت", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AppField(
                    template.widthMm.toString(),
                    { it.toFloatOrNull()?.let { v -> template = template.copy(widthMm = v.coerceIn(20f, 210f)) } },
                    "العرض (مم)", Modifier.weight(1f), numeric = true,
                )
                AppField(
                    template.heightMm.toString(),
                    { it.toFloatOrNull()?.let { v -> template = template.copy(heightMm = v.coerceIn(20f, 297f)) } },
                    "الارتفاع (مم)", Modifier.weight(1f), numeric = true,
                )
            }
            Spacer(Modifier.height(6.dp))
            Text("مقاسات جاهزة", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(
                    "كرت بنكي 85×54" to (85.6f to 54f),
                    "تذكرة 63×33" to (63f to 33f),
                    "صغير 63×27" to (63f to 27f),
                    "قسيمة 48×27" to (48f to 27f),
                ).forEach { (label, dims) ->
                    val on = template.widthMm == dims.first && template.heightMm == dims.second
                    Text(
                        label, fontSize = 11.sp, color = if (on) Neon else TextMid,
                        modifier = Modifier
                            .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                            .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                            .clickable { template = template.copy(widthMm = dims.first, heightMm = dims.second) }
                            .padding(horizontal = 11.dp, vertical = 6.dp),
                    )
                }
            }

            Spacer(Modifier.height(11.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GhostButton("رفع خلفية من الجوال", icon = Icons.Filled.Image) { imagePicker.launch("image/*") }
                if (template.backgroundPath.isNotBlank()) {
                    GhostButton("إزالة", color = Danger) { template = template.copy(backgroundPath = "") }
                }
            }

            Spacer(Modifier.height(11.dp))
            Text("لون خلفية الكرت", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                cardColors.forEach { c ->
                    ColorDot(c, template.backgroundColor == c) { template = template.copy(backgroundColor = c) }
                }
            }

            Spacer(Modifier.height(11.dp))
            Text("لون الإطار", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                textColors.forEach { c ->
                    ColorDot(c, template.borderColor == c) { template = template.copy(borderColor = c) }
                }
            }

            Spacer(Modifier.height(11.dp))
            Text("سُمك الإطار: ${"%.1f".format(template.borderWidthMm)} مم", fontSize = 12.sp, color = TextMid)
            Slider(
                value = template.borderWidthMm,
                onValueChange = { template = template.copy(borderWidthMm = it) },
                valueRange = 0f..3f,
                colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
            )
            Text("استدارة الزوايا: ${"%.1f".format(template.cornerRadiusMm)} مم", fontSize = 12.sp, color = TextMid)
            Slider(
                value = template.cornerRadiusMm,
                onValueChange = { template = template.copy(cornerRadiusMm = it) },
                valueRange = 0f..8f,
                colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
            )

            Spacer(Modifier.height(6.dp))
            Text("محتوى رمز QR", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                QrContent.entries.forEach { q ->
                    val on = template.qrContent == q
                    Text(
                        q.labelAr, fontSize = 11.sp, color = if (on) Neon else TextMid,
                        modifier = Modifier
                            .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                            .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                            .clickable { template = template.copy(qrContent = q) }
                            .padding(horizontal = 11.dp, vertical = 6.dp),
                    )
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }

    if (showAddField) {
        AlertDialog(
            onDismissRequest = { showAddField = false },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("إضافة حقل", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    FieldType.entries.forEach { type ->
                        Text(
                            type.labelAr,
                            fontSize = 14.sp, color = TextHi,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    val f = CardField(
                                        id = Store.newId(),
                                        type = type,
                                        sizeFrac = if (type == FieldType.QR_CODE) 0.45f else 0.10f,
                                        customText = if (type == FieldType.CUSTOM_TEXT) "نص جديد" else "",
                                    )
                                    template = template.copy(fields = template.fields + f)
                                    selectedFieldId = f.id
                                    showAddField = false
                                }
                                .padding(vertical = 11.dp),
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { showAddField = false }) { Text("إلغاء", color = TextLow) } },
        )
    }
}

@Composable
private fun ColorDot(color: Long, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(30.dp)
            .background(Color(color), CircleShape)
            .border(
                if (selected) 3.dp else 1.dp,
                if (selected) Neon else Stroke,
                CircleShape,
            )
            .clickable(onClick = onClick)
    )
}
