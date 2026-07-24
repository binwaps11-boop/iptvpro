package com.binwaps.cardmanager.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ===== لوحة الألوان: داكن احترافي + أزرق نيون =====
val Ink = Color(0xFF070B14)          // خلفية الشاشة
val Panel = Color(0xFF111827)         // البطاقات
val PanelHi = Color(0xFF18213A)       // بطاقة مرتفعة
val Stroke = Color(0xFF23304D)        // الحدود
val Neon = Color(0xFF00D4FF)          // اللون المميز الأساسي
val Violet = Color(0xFF7C4DFF)        // اللون المميز الثانوي
val Lime = Color(0xFF4ADE80)          // حالة: متصل / نجاح
val Warn = Color(0xFFFBBF24)          // حالة: تنبيه
val Danger = Color(0xFFFF5470)        // حالة: خطأ / حذف
val TextHi = Color(0xFFEAF2FF)        // نص أساسي
val TextMid = Color(0xFF93A4C4)       // نص ثانوي
val TextLow = Color(0xFF5B6B8A)       // نص خافت

val NeonGradient = Brush.horizontalGradient(listOf(Neon, Violet))
val PanelGradient = Brush.verticalGradient(listOf(PanelHi, Panel))
val ScreenGradient = Brush.verticalGradient(listOf(Color(0xFF0B1220), Ink))

private val Scheme = darkColorScheme(
    primary = Neon,
    onPrimary = Color(0xFF00212B),
    secondary = Violet,
    onSecondary = Color.White,
    tertiary = Lime,
    background = Ink,
    onBackground = TextHi,
    surface = Panel,
    onSurface = TextHi,
    surfaceVariant = PanelHi,
    onSurfaceVariant = TextMid,
    outline = Stroke,
    error = Danger,
)

private val AppTypography = Typography(
    headlineMedium = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold, color = TextHi),
    titleLarge = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Bold, color = TextHi),
    titleMedium = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextHi),
    bodyLarge = TextStyle(fontSize = 15.sp, color = TextHi),
    bodyMedium = TextStyle(fontSize = 13.sp, color = TextMid),
    labelSmall = TextStyle(fontSize = 11.sp, color = TextLow, letterSpacing = 0.6.sp),
)

@Composable
fun CardManagerTheme(content: @Composable () -> Unit) {
    // واجهة عربية: اتجاه من اليمين لليسار دائماً
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        MaterialTheme(
            colorScheme = Scheme,
            typography = AppTypography,
            shapes = Shapes(
                small = RoundedCornerShape(10.dp),
                medium = RoundedCornerShape(16.dp),
                large = RoundedCornerShape(22.dp),
            ),
            content = content,
        )
    }
}

/** بطاقة زجاجية: تدرج داكن + حد رفيع مضيء */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    glow: Color = Stroke,
    padding: Int = 14,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .background(PanelGradient, RoundedCornerShape(16.dp))
            .border(1.dp, glow.copy(alpha = 0.55f), RoundedCornerShape(16.dp))
            .padding(padding.dp),
        content = content,
    )
}
