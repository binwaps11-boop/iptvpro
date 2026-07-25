package com.binwaps.cardmanager.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.NeonGradient
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid

/** عنوان قسم مع سطر وصف وأيقونة */
@Composable
fun SectionHeader(title: String, subtitle: String? = null, icon: ImageVector? = null) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Box(
                Modifier
                    .size(36.dp)
                    .background(Neon.copy(alpha = 0.12f), RoundedCornerShape(11.dp))
                    .border(1.dp, Neon.copy(alpha = 0.35f), RoundedCornerShape(11.dp)),
                contentAlignment = Alignment.Center,
            ) { Icon(icon, null, tint = Neon, modifier = Modifier.size(20.dp)) }
            Spacer(Modifier.width(10.dp))
        }
        Column {
            Text(title, fontSize = 19.sp, fontWeight = FontWeight.Bold, color = TextHi)
            if (subtitle != null) Text(subtitle, fontSize = 12.sp, color = TextLow)
        }
    }
}

/** زر أساسي بتدرج نيون */
@Composable
fun NeonButton(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .background(
                if (enabled) NeonGradient else Brush.horizontalGradient(listOf(Stroke, Stroke)),
                RoundedCornerShape(13.dp),
            )
    ) {
        Button(
            onClick = onClick,
            enabled = enabled,
            shape = RoundedCornerShape(13.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.Transparent,
                contentColor = Color(0xFF04121A),
                disabledContainerColor = Color.Transparent,
                disabledContentColor = TextLow,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)) }
            Text(text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        }
    }
}

/** زر ثانوي بحدود */
@Composable
fun GhostButton(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    color: Color = Neon,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(13.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = color.copy(alpha = 0.10f),
            contentColor = color,
            disabledContainerColor = Panel,
            disabledContentColor = TextLow,
        ),
        modifier = modifier,
    ) {
        if (icon != null) { Icon(icon, null, Modifier.size(17.dp)); Spacer(Modifier.width(5.dp)) }
        Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** حقل إدخال بنمط التطبيق الداكن */
@Composable
fun AppField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    numeric: Boolean = false,
    password: Boolean = false,
    leading: ImageVector? = null,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label, fontSize = 12.sp) },
        singleLine = true,
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        leadingIcon = leading?.let { { Icon(it, null, tint = TextLow, modifier = Modifier.size(18.dp)) } },
        visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            keyboardType = if (numeric) KeyboardType.Number else if (password) KeyboardType.Password else KeyboardType.Text
        ),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Neon,
            unfocusedBorderColor = Stroke,
            focusedLabelColor = Neon,
            unfocusedLabelColor = TextLow,
            focusedTextColor = TextHi,
            unfocusedTextColor = TextHi,
            cursorColor = Neon,
            focusedContainerColor = Panel.copy(alpha = 0.6f),
            unfocusedContainerColor = Panel.copy(alpha = 0.6f),
        ),
    )
}

/** بطاقة إحصائية صغيرة */
@Composable
fun StatTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    accent: Color = Neon,
    hint: String? = null,
) {
    GlassCard(modifier, glow = accent.copy(alpha = 0.4f), padding = 12) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).background(accent, CircleShape))
            Spacer(Modifier.width(6.dp))
            Text(label, fontSize = 11.sp, color = TextLow)
        }
        Spacer(Modifier.height(4.dp))
        Text(value, fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi)
        if (hint != null) Text(hint, fontSize = 10.sp, color = TextLow)
    }
}

/** شارة حالة الاتصال مع نبضة */
@Composable
fun StatusPill(connected: Boolean, label: String) {
    val color = if (connected) Lime else Danger
    val transition = rememberInfiniteTransition(label = "pulse")
    val alpha by transition.animateFloat(
        initialValue = 0.35f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Reverse),
        label = "alpha",
    )
    Row(
        Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
            .border(1.dp, color.copy(alpha = 0.4f), RoundedCornerShape(999.dp))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).background(color.copy(alpha = if (connected) alpha else 1f), CircleShape))
        Spacer(Modifier.width(6.dp))
        Text(label, fontSize = 11.sp, color = color, fontWeight = FontWeight.SemiBold)
    }
}

/** صف بيانات: عنوان يمين وقيمة يسار */
@Composable
fun InfoRow(label: String, value: String, valueColor: Color = TextHi) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, fontSize = 12.5.sp, color = TextMid)
        Text(value, fontSize = 12.5.sp, color = valueColor, fontWeight = FontWeight.SemiBold)
    }
}

/** شريط تقدم أفقي بسيط بلون نيون */
@Composable
fun NeonProgress(fraction: Float, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(7.dp)
            .background(Stroke.copy(alpha = 0.5f), RoundedCornerShape(999.dp))
    ) {
        Box(
            Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .height(7.dp)
                .background(NeonGradient, RoundedCornerShape(999.dp))
        )
    }
}

/** حالة فارغة */
@Composable
fun EmptyState(icon: ImageVector, title: String, hint: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 34.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(58.dp).background(Neon.copy(alpha = 0.08f), CircleShape)
                .border(1.dp, Stroke, CircleShape),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = TextLow, modifier = Modifier.size(26.dp)) }
        Text(title, fontSize = 14.sp, color = TextMid, fontWeight = FontWeight.SemiBold)
        Text(hint, fontSize = 12.sp, color = TextLow)
    }
}

/** تنسيق البايتات */
fun formatBytes(bytes: Long): String = when {
    bytes >= 1_073_741_824 -> String.format(java.util.Locale.US, "%.2f ج.ب", bytes / 1_073_741_824.0)
    bytes >= 1_048_576 -> String.format(java.util.Locale.US, "%.1f م.ب", bytes / 1_048_576.0)
    bytes >= 1024 -> String.format(java.util.Locale.US, "%.0f ك.ب", bytes / 1024.0)
    else -> "$bytes بايت"
}
