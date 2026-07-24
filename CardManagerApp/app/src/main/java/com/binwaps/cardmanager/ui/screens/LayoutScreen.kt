package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.Image
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.CutMarkStyle
import com.binwaps.cardmanager.model.PageOrientation
import com.binwaps.cardmanager.model.PaperSize
import com.binwaps.cardmanager.print.PdfExporter
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.components.StatTile
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

/**
 * شاشة تخطيط الصفحة: مقاس الورق، الاتجاه، عدد الكروت في الصف والعمود،
 * المسافات والهوامش وعلامات القص — مع معاينة حية للصفحة كاملة.
 */
@Composable
fun LayoutScreen(templateId: Long, onDone: () -> Unit) {
    val settings by Store.settings.collectAsState()
    val users by Store.users.collectAsState()
    val templates by Store.templates.collectAsState()
    val template = templates.firstOrNull { it.id == templateId } ?: templates.firstOrNull()
    val layout = settings.layout

    fun update(block: (com.binwaps.cardmanager.model.PageLayout) -> com.binwaps.cardmanager.model.PageLayout) {
        Store.updateSettings(settings.copy(layout = block(settings.layout)))
    }

    val info = remember(template, layout, users.size) {
        template?.let { PdfExporter.computeLayout(it, settings, maxOf(users.size, 1)) }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDone) { Icon(Icons.Filled.ArrowForward, "رجوع", tint = TextMid) }
            Box(Modifier.weight(1f)) {
                SectionHeader("تخطيط الصفحة", template?.name, Icons.Filled.GridView)
            }
        }
        Spacer(Modifier.height(12.dp))

        // ملخص التخطيط
        if (info != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
                StatTile("في الصفحة", info.perPage.toString(), Modifier.weight(1f), Neon, "${info.columns}×${info.rows}")
                StatTile("عدد الصفحات", info.pages.toString(), Modifier.weight(1f), Violet, "${users.size} كرت")
                StatTile(
                    "مقاس الكرت",
                    "${info.cardWidthMm.toInt()}×${info.cardHeightMm.toInt()}",
                    Modifier.weight(1f), Lime, "مم",
                )
            }
            Spacer(Modifier.height(14.dp))
        }

        // المعاينة الحية للصفحة
        if (template != null) {
            val preview = remember(template, layout, users.firstOrNull()) {
                PdfExporter.renderPagePreview(template, users, settings, 560)
            }
            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 10) {
                Image(
                    bitmap = preview.asImageBitmap(),
                    contentDescription = "معاينة الصفحة",
                    modifier = Modifier.fillMaxWidth(),
                    contentScale = ContentScale.FillWidth,
                )
            }
            Text(
                "معاينة الصفحة كما ستُطبع",
                fontSize = 11.5.sp, color = TextLow,
                modifier = Modifier.padding(top = 6.dp),
            )
        }

        Spacer(Modifier.height(16.dp))

        // مقاس الورق
        Text("مقاس الورق", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(7.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            PaperSize.entries.forEach { p ->
                Chip(p.labelAr, layout.paper == p) { update { it.copy(paper = p) } }
            }
        }

        Spacer(Modifier.height(12.dp))
        Text("اتجاه الصفحة", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(7.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            PageOrientation.entries.forEach { o ->
                Chip(o.labelAr, layout.orientation == o) { update { it.copy(orientation = o) } }
            }
        }

        Spacer(Modifier.height(14.dp))
        GlassCard(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("توزيع تلقائي", fontSize = 13.5.sp, color = TextHi, fontWeight = FontWeight.SemiBold)
                    Text("يحسب عدد الكروت في الصفحة تلقائياً من مقاس الكرت", fontSize = 11.sp, color = TextLow)
                }
                Switch(
                    checked = layout.autoFit,
                    onCheckedChange = { update { l -> l.copy(autoFit = it) } },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Ink, checkedTrackColor = Neon,
                        uncheckedThumbColor = TextLow, uncheckedTrackColor = Panel,
                    ),
                )
            }

            if (!layout.autoFit) {
                Spacer(Modifier.height(12.dp))
                Counter("عدد الأعمدة (كروت بالعرض)", layout.columns, 1, 10) { update { l -> l.copy(columns = it) } }
                Spacer(Modifier.height(8.dp))
                Counter("عدد الصفوف (كروت بالطول)", layout.rows, 1, 20) { update { l -> l.copy(rows = it) } }
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("تكبير الكروت لملء الخلية", fontSize = 12.5.sp, color = TextHi)
                        Text("يحافظ على نسبة الكرت ويكبّره لأقصى حد", fontSize = 10.5.sp, color = TextLow)
                    }
                    Switch(
                        checked = layout.stretchToFit,
                        onCheckedChange = { update { l -> l.copy(stretchToFit = it) } },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Ink, checkedTrackColor = Neon,
                            uncheckedThumbColor = TextLow, uncheckedTrackColor = Panel,
                        ),
                    )
                }
            }
        }

        Spacer(Modifier.height(14.dp))
        GlassCard(Modifier.fillMaxWidth()) {
            Text("المسافات والهوامش", fontSize = 13.5.sp, color = TextHi, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            LabeledSlider("هامش الصفحة", layout.marginMm, 0f, 25f, "مم") { update { l -> l.copy(marginMm = it) } }
            LabeledSlider("المسافة الأفقية بين الكروت", layout.hSpacingMm, 0f, 20f, "مم") { update { l -> l.copy(hSpacingMm = it) } }
            LabeledSlider("المسافة الرأسية بين الكروت", layout.vSpacingMm, 0f, 20f, "مم") { update { l -> l.copy(vSpacingMm = it) } }
        }

        Spacer(Modifier.height(14.dp))
        Text("علامات القص", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(7.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CutMarkStyle.entries.forEach { c ->
                Chip(c.labelAr, layout.cutMarks == c) { update { it.copy(cutMarks = c) } }
            }
        }

        Spacer(Modifier.height(14.dp))
        Text("قوالب توزيع جاهزة", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(7.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(
                Triple("2×5 — 10 كروت", 2, 5),
                Triple("3×8 — 24 كرت", 3, 8),
                Triple("4×10 — 40 كرت", 4, 10),
                Triple("2×4 — 8 كروت", 2, 4),
                Triple("5×13 — 65 كرت", 5, 13),
            ).forEach { (label, c, r) ->
                val on = !layout.autoFit && layout.columns == c && layout.rows == r
                Chip(label, on) { update { it.copy(autoFit = false, columns = c, rows = r) } }
            }
        }

        Spacer(Modifier.height(34.dp))
    }
}

@Composable
private fun Chip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        label,
        fontSize = 11.5.sp,
        color = if (selected) Neon else TextMid,
        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
        modifier = Modifier
            .background(if (selected) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
            .border(1.dp, if (selected) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun Counter(label: String, value: Int, min: Int, max: Int, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 12.5.sp, color = TextMid, modifier = Modifier.weight(1f))
        Row(
            Modifier
                .background(Panel, RoundedCornerShape(999.dp))
                .border(1.dp, Stroke, RoundedCornerShape(999.dp)),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { if (value > min) onChange(value - 1) }, modifier = Modifier.size(34.dp)) {
                Icon(Icons.Filled.Remove, "نقص", tint = if (value > min) Neon else TextLow, modifier = Modifier.size(16.dp))
            }
            Text(
                value.toString(),
                fontSize = 15.sp, color = TextHi, fontWeight = FontWeight.Bold,
                modifier = Modifier.width(32.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            IconButton(onClick = { if (value < max) onChange(value + 1) }, modifier = Modifier.size(34.dp)) {
                Icon(Icons.Filled.Add, "زيادة", tint = if (value < max) Neon else TextLow, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun LabeledSlider(
    label: String, value: Float, min: Float, max: Float, unit: String,
    onChange: (Float) -> Unit,
) {
    Column {
        Row {
            Text(label, fontSize = 12.sp, color = TextMid, modifier = Modifier.weight(1f))
            Text("${"%.1f".format(value)} $unit", fontSize = 12.sp, color = Neon, fontWeight = FontWeight.SemiBold)
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = min..max,
            colors = SliderDefaults.colors(thumbColor = Neon, activeTrackColor = Neon, inactiveTrackColor = Stroke),
        )
    }
}
