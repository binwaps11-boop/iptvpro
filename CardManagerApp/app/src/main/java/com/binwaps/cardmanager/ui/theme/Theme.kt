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

// ===== حبر داكن وأخضر نعناعي: تباين واضح وهرمية هادئة =====
val Ink = Color(0xFF091216)          // خلفية الشاشة
val Panel = Color(0xFF112026)         // البطاقات
val PanelHi = Color(0xFF172B32)       // بطاقة مرتفعة
val Stroke = Color(0xFF263B42)        // حدود خفيفة (زينة فقط)
val StrokeHi = Color(0xFF47616A)      // حدود الحقول غير المركّزة — تُرى فعلاً
val Neon = Color(0xFF70E4C1)          // اللون المميز الأساسي
val Violet = Color(0xFFA2B8F5)        // اللون المميز الثانوي
val Lime = Color(0xFF4ADE80)          // حالة: متصل / نجاح
val Warn = Color(0xFFFBBF24)          // حالة: تنبيه
val Danger = Color(0xFFFF5470)        // حالة: خطأ / حذف

// سلّم النصوص مضبوط على تباين مقروء فوق Panel/PanelHi.
// كان TextLow (5B6B8A) يُستخدم لجُمل كاملة بتباين ٢٫٩:١ — أقل من نصف الحد
// الأدنى ٤٫٥:١، فالنص الإرشادي كان يكاد لا يُقرأ. الآن:
val TextHi = Color(0xFFF0F6F7)        // نص أساسي وعناوين
val TextMid = Color(0xFFB1C5CC)       // نص ثانوي وإرشادي — يُقرأ بلا جهد
val TextLow = Color(0xFF91ABB5)       // تسميات قصيرة فقط، لا جُمل
val Muted = Color(0xFF617F8A)         // زينة وأيقونات معطّلة — لا نص أبداً

val NeonGradient = Brush.horizontalGradient(listOf(Neon, Color(0xFF8DE9D4)))
val PanelGradient = Brush.verticalGradient(listOf(PanelHi, Panel))
val ScreenGradient = Brush.verticalGradient(listOf(Color(0xFF0F1D23), Ink))

// ===== رموز تباعد دلالية =====
// بدل الأرقام السحرية المتناثرة (6..30dp) — نظام تباعد واحد متسق.
object Space {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 24.dp
}

// ===== رموز ألفا دلالية =====
// كانت 0.08..0.5 عشوائية لأغراض متشابهة — الآن أسماء تصف الغرض.
const val AlphaGlow = 0.40f       // توهّج حدود البطاقة المميّزة
const val AlphaFillSoft = 0.12f   // تعبئة خفيفة (خلفية شريحة/شارة)
const val AlphaBorderSoft = 0.35f // حدّ خفيف حول عنصر مميّز
const val AlphaFillFaint = 0.10f  // تعبئة أخفت (شرائط الرسائل)

private val Scheme = darkColorScheme(
    primary = Neon,
    onPrimary = Color(0xFF00212B),
    secondary = Violet,
    onSecondary = Ink,
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

// lineHeight إلزامي للعربية: بدونه تُقصّ التشكيلات وأذيال الحروف (ج، ح، ي)
private val AppTypography = Typography(
    headlineMedium = TextStyle(fontSize = 24.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, color = TextHi),
    titleLarge = TextStyle(fontSize = 19.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, color = TextHi),
    titleMedium = TextStyle(fontSize = 15.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold, color = TextHi),
    // Material3 animates the input label between bodyLarge and bodySmall.
    // Both must use sp: interpolating em and sp crashes when any field opens.
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 23.sp, color = TextHi),
    bodyMedium = TextStyle(fontSize = 13.sp, lineHeight = 21.sp, color = TextMid),
    labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 17.sp, color = TextLow, letterSpacing = 0.6.sp),
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
    glow: Color = StrokeHi,
    padding: Int = 14,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .background(PanelGradient, RoundedCornerShape(16.dp))
            // ألفا المتصل تُحترم: `copy(alpha = 0.55f)` كان يمسحها فتخرج كل
            // البطاقات بشدة توهج واحدة مهما مرّر المتصل، فتضيع الهرمية البصرية
            .border(1.dp, glow, RoundedCornerShape(16.dp))
            .padding(padding.dp),
        content = content,
    )
}
