package com.binwaps.cardmanager.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Colorize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid

/**
 * زرّ لون مخصّص — دائرة بأيقونة قطّارة يفتح منتقي ألوان حرّ.
 * يُوضع بجانب صفّ الألوان الجاهزة فيمنح المستخدم أي لون يريده.
 */
@Composable
fun CustomColorDot(onOpen: () -> Unit) {
    Box(
        Modifier
            .size(30.dp)
            .background(Panel, RoundedCornerShape(50))
            .border(1.5.dp, Neon, RoundedCornerShape(50))
            .clickable(onClick = onOpen),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.Colorize, "لون مخصّص", tint = Neon, modifier = Modifier.size(16.dp))
    }
}

/**
 * منتقي ألوان حرّ عبر منزلقات R/G/B مع معاينة حيّة وقيمة HEX.
 * منزلقات بدل عجلة لون على Canvas: أبسط وأمتن ولا يكسر البناء، ويعطي أي لون.
 * القيمة الراجعة ARGB (Long) بنفس صيغة تخزين ألوان القالب (0xAARRGGBB).
 */
@Composable
fun ColorPickerDialog(initial: Long, onPick: (Long) -> Unit, onDismiss: () -> Unit) {
    var r by remember { mutableStateOf(((initial shr 16) and 0xFF).toFloat()) }
    var g by remember { mutableStateOf(((initial shr 8) and 0xFF).toFloat()) }
    var b by remember { mutableStateOf((initial and 0xFF).toFloat()) }
    val argb = 0xFF000000L or (r.toLong() shl 16) or (g.toLong() shl 8) or b.toLong()

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        titleContentColor = TextHi,
        shape = RoundedCornerShape(20.dp),
        title = { Text("لون مخصّص", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
        text = {
            Column {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(46.dp)
                        .background(Color(argb), RoundedCornerShape(12.dp))
                        .border(1.dp, Stroke, RoundedCornerShape(12.dp)),
                )
                Spacer(Modifier.height(12.dp))
                ChannelSlider("أحمر", r, Color(0xFFE53935)) { r = it }
                ChannelSlider("أخضر", g, Color(0xFF43A047)) { g = it }
                ChannelSlider("أزرق", b, Color(0xFF1E88E5)) { b = it }
                Spacer(Modifier.height(4.dp))
                Text(
                    "HEX: #%06X".format(argb and 0xFFFFFFL),
                    fontSize = 12.5.sp, color = TextMid,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onPick(argb); onDismiss() }) {
                Text("اختيار", color = Neon, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("إلغاء", color = TextLow) } },
    )
}

@Composable
private fun ChannelSlider(label: String, value: Float, tint: Color, onChange: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 12.sp, color = TextMid, modifier = Modifier.width(42.dp))
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = 0f..255f,
            colors = SliderDefaults.colors(
                thumbColor = tint, activeTrackColor = tint, inactiveTrackColor = Stroke,
            ),
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(6.dp))
        Text(value.toInt().toString(), fontSize = 11.sp, color = TextLow, modifier = Modifier.width(30.dp))
    }
}
