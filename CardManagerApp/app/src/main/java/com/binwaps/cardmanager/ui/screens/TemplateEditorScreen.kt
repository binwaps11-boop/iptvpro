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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
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
import com.binwaps.cardmanager.model.CardCell
import com.binwaps.cardmanager.model.CardField
import com.binwaps.cardmanager.model.CardLayoutMode
import com.binwaps.cardmanager.model.CardRow
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.CellAlign
import com.binwaps.cardmanager.model.FieldType
import com.binwaps.cardmanager.model.QrContent
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.util.toMoneyOrNull
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
import com.binwaps.cardmanager.ui.theme.Violet
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
            Store.importBackground(uri)?.let { path ->
                com.binwaps.cardmanager.render.CardRenderer.clearCache()
                template = template.copy(backgroundPath = path)
            }
        }
    }

    // منتقي صورة حقل الشعار — يضبط صورة الحقل المحدّد وقت الاختيار
    val fieldImagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val fid = selectedFieldId
        if (uri != null && fid != null) {
            Store.importBackground(uri)?.let { path ->
                com.binwaps.cardmanager.render.CardRenderer.clearCache()
                template = template.copy(
                    fields = template.fields.map { if (it.id == fid) it.copy(imagePath = path) else it },
                )
            }
        }
    }

    // منتقي اللون الحرّ: يحمل اللون الابتدائي ودالة التطبيق على الهدف المختار
    var pickerInit by remember { mutableStateOf(0xFF000000L) }
    var pickerCb by remember { mutableStateOf<((Long) -> Unit)?>(null) }

    fun updateField(f: CardField) {
        template = template.copy(fields = template.fields.map { if (it.id == f.id) f else it })
    }

    // الرجوع (السهم أو زر النظام) كان يرمي كل التعديلات بصمت — الآن تأكيد: حفظ/تجاهل/بقاء
    val dirty = template != (Store.template(templateId) ?: template)
    var confirmLeave by remember { mutableStateOf(false) }
    fun leave() { if (dirty) confirmLeave = true else onDone() }
    androidx.activity.compose.BackHandler(enabled = dirty) { confirmLeave = true }
    if (confirmLeave) {
        com.binwaps.cardmanager.ui.components.ConfirmDialog(
            title = "تغييرات غير محفوظة",
            body = "عدّلت القالب ولم تحفظ. احفظ قبل الخروج، أو تجاهل التغييرات، أو ابقَ في المحرر.",
            confirmLabel = "حفظ والخروج",
            danger = false,
            neutralLabel = "تجاهل التغييرات",
            onNeutral = { onDone() },
            onConfirm = { Store.upsertTemplate(template); onDone() },
            onDismiss = { confirmLeave = false },
        )
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
            IconButton(onClick = { leave() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "رجوع", tint = TextMid) }
            Text("محرر القالب", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextHi, modifier = Modifier.weight(1f))
            Box(Modifier.width(110.dp)) {
                NeonButton("حفظ", icon = Icons.Filled.Save) {
                    Store.upsertTemplate(template)
                    onDone()
                }
            }
        }

        AppField(template.name, { template = template.copy(name = it) }, "اسم القالب", Modifier.fillMaxWidth())

        // طريقة بناء الكرت
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CardLayoutMode.entries.forEach { m ->
                val on = template.layoutMode == m
                Column(
                    Modifier
                        .weight(1f)
                        .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(14.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.55f) else Stroke, RoundedCornerShape(14.dp))
                        .clickable {
                            template = if (m == CardLayoutMode.TABLE && template.rows.isEmpty()) {
                                // أول مرة: ابدأ بجدول جاهز حتى لا تكون الشاشة فارغة
                                val seed = Store.smartTableTemplate(Store.newId())
                                template.copy(layoutMode = m, rows = seed.rows, tablePaddingMm = seed.tablePaddingMm)
                            } else {
                                template.copy(layoutMode = m)
                            }
                        }
                        .padding(horizontal = 11.dp, vertical = 9.dp),
                ) {
                    Text(m.labelAr, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (on) Neon else TextMid)
                    Text(m.hintAr, fontSize = 11.sp, color = TextLow)
                }
            }
        }

        // المعاينة الحية مع السحب
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 10) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .onSizeChanged { previewSize = it }
                    .pointerInput(template.id, previewSize, template.layoutMode) {
                        if (template.layoutMode == CardLayoutMode.TABLE) return@pointerInput
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
        if (template.layoutMode == CardLayoutMode.TABLE) {
            TableBuilder(template) { template = it }
        }

        if (template.layoutMode == CardLayoutMode.FREE) {
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
                // الرمز والباركود والصورة عناصر رسومية — لا نص بادئة ولا تنسيق خط لها
                val graphic = selected.type == FieldType.QR_CODE || selected.type == FieldType.BARCODE ||
                    selected.type == FieldType.IMAGE
                if (selected.type == FieldType.CUSTOM_TEXT) {
                    AppField(selected.customText, { updateField(selected.copy(customText = it)) }, "النص", Modifier.fillMaxWidth())
                } else if (selected.type == FieldType.IMAGE) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GhostButton(
                            if (selected.imagePath.isBlank()) "اختر صورة الشعار" else "تغيير الصورة",
                            icon = Icons.Filled.Image,
                        ) { fieldImagePicker.launch("image/*") }
                        if (selected.imagePath.isNotBlank()) {
                            GhostButton("إزالة الصورة", color = Danger) {
                                com.binwaps.cardmanager.render.CardRenderer.clearCache()
                                updateField(selected.copy(imagePath = ""))
                            }
                        }
                    }
                    if (selected.imagePath.isBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text("لم تُختر صورة بعد — لن يظهر الحقل حتى تختار صورة", fontSize = 11.5.sp, color = TextLow)
                    }
                } else if (!graphic) {
                    AppField(selected.prefix, { updateField(selected.copy(prefix = it)) }, "نص قبل القيمة (مثل: المستخدم:)", Modifier.fillMaxWidth())
                }
                Spacer(Modifier.height(8.dp))
                // مكان العنصر في الكرت — إدخال رقمي دقيق بجانب السحب
                Text("مكان العنصر في الكرت (%)", fontSize = 12.sp, color = TextLow)
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // نسب مئوية صحيحة بنص مستقل — مسح الرقم كان مرفوضاً فيلتصق القديم
                    com.binwaps.cardmanager.ui.components.NumberField(
                        (selected.xFrac * 100).toInt().toFloat(),
                        { updateField(selected.copy(xFrac = (it / 100f).coerceIn(0f, 1f))) },
                        "أفقي X", Modifier.weight(1f), min = 0f, max = 100f, integer = true, key = selected.id,
                    )
                    com.binwaps.cardmanager.ui.components.NumberField(
                        (selected.yFrac * 100).toInt().toFloat(),
                        { updateField(selected.copy(yFrac = (it / 100f).coerceIn(0f, 1f))) },
                        "رأسي Y", Modifier.weight(1f), min = 0f, max = 100f, integer = true, key = selected.id,
                    )
                    com.binwaps.cardmanager.ui.components.NumberField(
                        (selected.sizeFrac * 100).toInt().toFloat(),
                        { updateField(selected.copy(sizeFrac = (it / 100f).coerceIn(0.02f, 0.95f))) },
                        "الحجم", Modifier.weight(1f), min = 2f, max = 95f, integer = true, key = selected.id,
                    )
                }
                Spacer(Modifier.height(7.dp))
                // محاذاة سريعة
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(
                        "يمين" to 0.85f, "وسط أفقي" to 0.5f, "يسار" to 0.15f,
                    ).forEach { (label, x) ->
                        Text(
                            label, fontSize = 11.sp, color = Neon,
                            modifier = Modifier
                                .background(Neon.copy(alpha = 0.10f), RoundedCornerShape(999.dp))
                                .clickable { updateField(selected.copy(xFrac = x)) }
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        )
                    }
                    listOf("أعلى" to 0.15f, "وسط رأسي" to 0.5f, "أسفل" to 0.85f).forEach { (label, y) ->
                        Text(
                            label, fontSize = 11.sp, color = Violet,
                            modifier = Modifier
                                .background(Violet.copy(alpha = 0.10f), RoundedCornerShape(999.dp))
                                .clickable { updateField(selected.copy(yFrac = y)) }
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        )
                    }
                }

                Spacer(Modifier.height(6.dp))
                Text("الحجم", fontSize = 12.sp, color = TextLow)
                Slider(
                    value = selected.sizeFrac,
                    onValueChange = { updateField(selected.copy(sizeFrac = it)) },
                    valueRange = 0.03f..if (graphic) 0.95f else 0.32f,
                    colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
                )
                if (!graphic) {
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
                        com.binwaps.cardmanager.ui.components.CustomColorDot {
                            pickerInit = selected.color; pickerCb = { updateField(selected.copy(color = it)) }
                        }
                    }
                }
            }
        }
        } // نهاية النمط الحر

        // إعدادات الكرت
        GlassCard(Modifier.fillMaxWidth()) {
            Text("إعدادات الكرت", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // NumberField: كتابة «63» كانت تُنتج 20.03 لأن coerceIn تعيد كتابة النص مع كل ضغطة
                com.binwaps.cardmanager.ui.components.NumberField(
                    template.widthMm, { template = template.copy(widthMm = it) },
                    "العرض (مم)", Modifier.weight(1f), min = 20f, max = 210f, key = template.id,
                )
                com.binwaps.cardmanager.ui.components.NumberField(
                    template.heightMm, { template = template.copy(heightMm = it) },
                    "الارتفاع (مم)", Modifier.weight(1f), min = 20f, max = 297f, key = template.id,
                )
            }
            Spacer(Modifier.height(6.dp))
            Text("مقاسات جاهزة", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(
                    "3 في الصف ${com.binwaps.cardmanager.ui.components.ltr("69×18")}" to (69.38f to 17.64f),
                    "كرت بنكي ${com.binwaps.cardmanager.ui.components.ltr("85×54")}" to (85.6f to 54f),
                    "تذكرة ${com.binwaps.cardmanager.ui.components.ltr("63×33")}" to (63f to 33f),
                    "صغير ${com.binwaps.cardmanager.ui.components.ltr("63×27")}" to (63f to 27f),
                    "قسيمة ${com.binwaps.cardmanager.ui.components.ltr("48×27")}" to (48f to 27f),
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
                    GhostButton("إزالة", color = Danger) {
                        com.binwaps.cardmanager.render.CardRenderer.clearCache()
                        template = template.copy(backgroundPath = "")
                    }
                }
            }

            Spacer(Modifier.height(11.dp))
            Text("لون خلفية الكرت", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                cardColors.forEach { c ->
                    ColorDot(c, template.backgroundColor == c) { template = template.copy(backgroundColor = c) }
                }
                com.binwaps.cardmanager.ui.components.CustomColorDot {
                    pickerInit = template.backgroundColor; pickerCb = { template = template.copy(backgroundColor = it) }
                }
            }

            Spacer(Modifier.height(11.dp))
            Text("لون الإطار", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                textColors.forEach { c ->
                    ColorDot(c, template.borderColor == c) { template = template.copy(borderColor = c) }
                }
                com.binwaps.cardmanager.ui.components.CustomColorDot {
                    pickerInit = template.borderColor; pickerCb = { template = template.copy(borderColor = it) }
                }
            }

            if (template.layoutMode == CardLayoutMode.TABLE) {
                Spacer(Modifier.height(11.dp))
                Text("سُمك خطوط الجدول: ${"%.2f".format(java.util.Locale.US, template.gridWidthMm)} مم", fontSize = 12.sp, color = TextMid)
                Slider(
                    value = template.gridWidthMm,
                    onValueChange = { template = template.copy(gridWidthMm = it) },
                    valueRange = 0.05f..1f,
                    colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
                )
                Text("الهامش الداخلي: ${"%.1f".format(java.util.Locale.US, template.tablePaddingMm)} مم", fontSize = 12.sp, color = TextMid)
                Slider(
                    value = template.tablePaddingMm,
                    onValueChange = { template = template.copy(tablePaddingMm = it) },
                    valueRange = 0f..5f,
                    colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
                )
                Text("لون خطوط الجدول", fontSize = 12.sp, color = TextLow)
                Spacer(Modifier.height(6.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    textColors.forEach { c ->
                        ColorDot(c, template.gridColor == c) { template = template.copy(gridColor = c) }
                    }
                    com.binwaps.cardmanager.ui.components.CustomColorDot {
                        pickerInit = template.gridColor; pickerCb = { template = template.copy(gridColor = it) }
                    }
                }
            }

            Spacer(Modifier.height(11.dp))
            Text("سُمك الإطار: ${"%.1f".format(java.util.Locale.US, template.borderWidthMm)} مم", fontSize = 12.sp, color = TextMid)
            Slider(
                value = template.borderWidthMm,
                onValueChange = { template = template.copy(borderWidthMm = it) },
                valueRange = 0f..3f,
                colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
            )
            Text("استدارة الزوايا: ${"%.1f".format(java.util.Locale.US, template.cornerRadiusMm)} مم", fontSize = 12.sp, color = TextMid)
            Slider(
                value = template.cornerRadiusMm,
                onValueChange = { template = template.copy(cornerRadiusMm = it) },
                valueRange = 0f..8f,
                colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
            )

            Spacer(Modifier.height(11.dp))
            Text("خط الكرت", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(6.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                com.binwaps.cardmanager.model.CardFont.entries.forEach { f ->
                    val on = template.font == f
                    Text(
                        f.labelAr, fontSize = 11.sp, color = if (on) Neon else TextMid,
                        modifier = Modifier
                            .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                            .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                            .clickable { template = template.copy(font = f) }
                            .padding(horizontal = 11.dp, vertical = 6.dp),
                    )
                }
            }
            Text(
                "الخطوط مضمّنة في التطبيق فتُطبع العربية بنفس الشكل على أي جهاز أو طابعة",
                fontSize = 11.sp, color = TextLow, modifier = Modifier.padding(top = 4.dp),
            )

            Spacer(Modifier.height(11.dp))
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

    pickerCb?.let { cb ->
        com.binwaps.cardmanager.ui.components.ColorPickerDialog(
            pickerInit, onPick = cb, onDismiss = { pickerCb = null },
        )
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
                                        sizeFrac = when (type) {
                                            FieldType.QR_CODE -> 0.45f
                                            FieldType.BARCODE -> 0.6f // الباركود عريض
                                            FieldType.IMAGE -> 0.3f // شعار متوسط
                                            else -> 0.10f
                                        },
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

/**
 * بانِي الجدول — يبني الكرت صفوفاً وخلايا مثل طباعة سمارت كريتور،
 * لكن هنا كل شيء قابل للتعديل: ارتفاع الصف، عدد الخلايا، عرض كل خلية، محتواها، خطها وإطارها.
 */
@Composable
private fun TableBuilder(template: CardTemplate, onChange: (CardTemplate) -> Unit) {
    var selectedCellId by remember { mutableStateOf<Long?>(null) }
    var addCellToRow by remember { mutableStateOf<Long?>(null) }

    fun setRows(rows: List<CardRow>) = onChange(template.copy(rows = rows))

    fun updateCell(rowId: Long, cell: CardCell) = setRows(
        template.rows.map { r ->
            if (r.id != rowId) r else r.copy(cells = r.cells.map { if (it.id == cell.id) cell else it })
        }
    )

    // منتقي صورة خلية — يحفظ الهدف (صف، خلية) ثم يضبط الصورة عند العودة
    var cellImageTarget by remember { mutableStateOf<Pair<Long, Long>?>(null) }
    val cellImagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val target = cellImageTarget
        if (uri != null && target != null) {
            Store.importBackground(uri)?.let { path ->
                com.binwaps.cardmanager.render.CardRenderer.clearCache()
                setRows(
                    template.rows.map { r ->
                        if (r.id != target.first) r
                        else r.copy(cells = r.cells.map { if (it.id == target.second) it.copy(imagePath = path) else it })
                    },
                )
            }
        }
    }

    // منتقي اللون الحرّ لخلية الجدول
    var cellPickerInit by remember { mutableStateOf(0xFF000000L) }
    var cellPickerCb by remember { mutableStateOf<((Long) -> Unit)?>(null) }
    cellPickerCb?.let { cb ->
        com.binwaps.cardmanager.ui.components.ColorPickerDialog(
            cellPickerInit, onPick = cb, onDismiss = { cellPickerCb = null },
        )
    }

    GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.3f)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("صفوف الكرت", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi, modifier = Modifier.weight(1f))
            Text(
                "مجموع الارتفاع ${"%.1f".format(java.util.Locale.US, template.rowsHeightMm)} من ${"%.1f".format(java.util.Locale.US, template.heightMm)} مم",
                fontSize = 11.5.sp,
                color = if (template.rowsHeightMm > template.heightMm) Danger else TextLow,
            )
        }
        Spacer(Modifier.height(9.dp))

        template.rows.forEachIndexed { index, row ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(Panel, RoundedCornerShape(14.dp))
                    .border(1.dp, Stroke, RoundedCornerShape(14.dp))
                    .padding(9.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("صف ${index + 1}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Neon)
                    Spacer(Modifier.width(9.dp))
                    Box(Modifier.width(96.dp)) {
                        com.binwaps.cardmanager.ui.components.NumberField(
                            row.heightMm,
                            { h -> setRows(template.rows.map { r -> if (r.id == row.id) r.copy(heightMm = h) else r }) },
                            "ارتفاع مم", min = 1f, max = 100f, key = row.id,
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    if (index > 0) IconButton(onClick = {
                        val l = template.rows.toMutableList(); l.add(index - 1, l.removeAt(index)); setRows(l)
                    }, modifier = Modifier.size(30.dp)) {
                        Icon(Icons.Filled.KeyboardArrowUp, "أعلى", tint = TextMid, modifier = Modifier.size(19.dp))
                    }
                    if (index < template.rows.lastIndex) IconButton(onClick = {
                        val l = template.rows.toMutableList(); l.add(index + 1, l.removeAt(index)); setRows(l)
                    }, modifier = Modifier.size(30.dp)) {
                        Icon(Icons.Filled.KeyboardArrowDown, "أسفل", tint = TextMid, modifier = Modifier.size(19.dp))
                    }
                    IconButton(onClick = { setRows(template.rows.filterNot { it.id == row.id }) }, modifier = Modifier.size(30.dp)) {
                        Icon(Icons.Filled.Delete, "حذف الصف", tint = Danger, modifier = Modifier.size(18.dp))
                    }
                }

                Spacer(Modifier.height(7.dp))
                // خلايا الصف — من اليمين لليسار كما تُطبع
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.cells.forEach { c ->
                        val on = c.id == selectedCellId
                        Text(
                            cellChipLabel(c),
                            fontSize = 11.sp,
                            color = if (on) Neon else TextMid,
                            fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                            modifier = Modifier
                                .background(if (on) Neon.copy(alpha = 0.13f) else ScreenPanelChip, RoundedCornerShape(999.dp))
                                .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                                .clickable { selectedCellId = if (on) null else c.id }
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        )
                    }
                    Row(
                        Modifier
                            .background(Neon.copy(alpha = 0.10f), RoundedCornerShape(999.dp))
                            .clickable { addCellToRow = row.id }
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Add, null, tint = Neon, modifier = Modifier.size(13.dp))
                        Spacer(Modifier.width(3.dp))
                        Text("خلية", fontSize = 11.sp, color = Neon)
                    }
                }

                // خصائص الخلية المحددة داخل هذا الصف
                val cell = row.cells.firstOrNull { it.id == selectedCellId }
                if (cell != null) {
                    Spacer(Modifier.height(9.dp))
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .background(Neon.copy(alpha = 0.05f), RoundedCornerShape(12.dp))
                            .padding(9.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("الخلية: ${cell.type.labelAr}", fontSize = 12.5.sp, fontWeight = FontWeight.Bold, color = TextHi, modifier = Modifier.weight(1f))
                            IconButton(onClick = {
                                setRows(template.rows.map { r -> if (r.id == row.id) r.copy(cells = r.cells.filterNot { it.id == cell.id }) else r })
                                selectedCellId = null
                            }, modifier = Modifier.size(30.dp)) {
                                Icon(Icons.Filled.Delete, "حذف الخلية", tint = Danger, modifier = Modifier.size(18.dp))
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        if (cell.type == FieldType.CUSTOM_TEXT) {
                            AppField(cell.customText, { updateCell(row.id, cell.copy(customText = it)) }, "النص", Modifier.fillMaxWidth())
                        } else if (cell.type == FieldType.IMAGE) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                GhostButton(
                                    if (cell.imagePath.isBlank()) "اختر صورة" else "تغيير الصورة",
                                    icon = Icons.Filled.Image,
                                ) { cellImageTarget = row.id to cell.id; cellImagePicker.launch("image/*") }
                                if (cell.imagePath.isNotBlank()) {
                                    GhostButton("إزالة", color = Danger) {
                                        com.binwaps.cardmanager.render.CardRenderer.clearCache()
                                        updateCell(row.id, cell.copy(imagePath = ""))
                                    }
                                }
                            }
                        } else if (cell.type != FieldType.QR_CODE) {
                            AppField(cell.prefix, { updateCell(row.id, cell.copy(prefix = it)) }, "نص قبل القيمة", Modifier.fillMaxWidth())
                        }
                        Spacer(Modifier.height(7.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            com.binwaps.cardmanager.ui.components.NumberField(
                                cell.weight, { w -> updateCell(row.id, cell.copy(weight = w)) },
                                "عرض نسبي", Modifier.weight(1f), min = 0.05f, max = 20f, key = cell.id,
                            )
                            com.binwaps.cardmanager.ui.components.NumberField(
                                cell.fontSizePt, { s -> updateCell(row.id, cell.copy(fontSizePt = s)) },
                                "حجم الخط pt", Modifier.weight(1f), min = 3f, max = 72f, key = cell.id,
                            )
                        }
                        Spacer(Modifier.height(7.dp))
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            CellAlign.entries.forEach { a ->
                                Chip(a.labelAr, cell.align == a) { updateCell(row.id, cell.copy(align = a)) }
                            }
                            Chip(if (cell.bold) "عريض ✓" else "عريض", cell.bold) { updateCell(row.id, cell.copy(bold = !cell.bold)) }
                            Chip(if (cell.border) "إطار ✓" else "إطار", cell.border) { updateCell(row.id, cell.copy(border = !cell.border)) }
                        }
                        Spacer(Modifier.height(7.dp))
                        Text("نوع المحتوى", fontSize = 11.5.sp, color = TextLow)
                        Spacer(Modifier.height(5.dp))
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            FieldType.entries.forEach { t ->
                                Chip(t.labelAr, cell.type == t) { updateCell(row.id, cell.copy(type = t)) }
                            }
                        }
                        Spacer(Modifier.height(7.dp))
                        Text("لون النص", fontSize = 11.5.sp, color = TextLow)
                        Spacer(Modifier.height(5.dp))
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            textColors.forEach { c ->
                                ColorDot(c, cell.color == c) { updateCell(row.id, cell.copy(color = c)) }
                            }
                            com.binwaps.cardmanager.ui.components.CustomColorDot {
                                cellPickerInit = cell.color; cellPickerCb = { updateCell(row.id, cell.copy(color = it)) }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GhostButton("إضافة صف", icon = Icons.Filled.Add) {
                val id = Store.newId()
                setRows(
                    template.rows + CardRow(
                        id = id,
                        heightMm = 4.94f,
                        cells = listOf(CardCell(id = id + 1, type = FieldType.CUSTOM_TEXT, customText = "نص جديد")),
                    )
                )
            }
            GhostButton("توزيع الارتفاع بالتساوي") {
                if (template.rows.isNotEmpty()) {
                    val usable = (template.heightMm - 2 * template.tablePaddingMm).coerceAtLeast(1f)
                    val each = usable / template.rows.size
                    setRows(template.rows.map { it.copy(heightMm = each) })
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            "الخلية الأولى في كل صف تُطبع على اليمين. العرض النسبي يعني: خليتان بـ1 و1 تتقاسمان الصف بالتساوي، وبـ2 و1 تأخذ الأولى الثلثين.",
            fontSize = 11.sp, color = TextLow,
        )
    }

    if (addCellToRow != null) {
        val rowId = addCellToRow!!
        AlertDialog(
            onDismissRequest = { addCellToRow = null },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("إضافة خلية", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    FieldType.entries.forEach { type ->
                        Text(
                            type.labelAr, fontSize = 14.sp, color = TextHi,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    val c = CardCell(
                                        id = Store.newId(),
                                        type = type,
                                        customText = if (type == FieldType.CUSTOM_TEXT) "نص جديد" else "",
                                    )
                                    setRows(template.rows.map { r -> if (r.id == rowId) r.copy(cells = r.cells + c) else r })
                                    selectedCellId = c.id
                                    addCellToRow = null
                                }
                                .padding(vertical = 11.dp),
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { addCellToRow = null }) { Text("إلغاء", color = TextLow) } },
        )
    }
}

private fun cellChipLabel(c: CardCell): String = when {
    c.type == FieldType.CUSTOM_TEXT && c.customText.isNotBlank() -> c.customText.take(12)
    c.type == FieldType.CUSTOM_TEXT -> "نص فارغ"
    else -> c.type.labelAr
}

private val ScreenPanelChip = Color(0xFF141A26)

@Composable
private fun Chip(label: String, on: Boolean, onClick: () -> Unit) {
    Text(
        label,
        fontSize = 11.sp,
        color = if (on) Neon else TextMid,
        fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
        modifier = Modifier
            .background(if (on) Neon.copy(alpha = 0.13f) else ScreenPanelChip, RoundedCornerShape(999.dp))
            .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
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
