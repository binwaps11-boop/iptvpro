package com.binwaps.cardmanager.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

val Teal = Color(0xFF0B5E4F)
val TealLight = Color(0xFF3E8E7E)
val Amber = Color(0xFFFFB300)
val Surface = Color(0xFFF6F8F7)

private val LightColors = lightColorScheme(
    primary = Teal,
    secondary = TealLight,
    tertiary = Amber,
    background = Surface,
    surface = Color.White,
)

@Composable
fun CardManagerTheme(content: @Composable () -> Unit) {
    // واجهة عربية: اتجاه من اليمين لليسار دائماً
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        MaterialTheme(
            colorScheme = LightColors,
            shapes = Shapes(
                small = RoundedCornerShape(8.dp),
                medium = RoundedCornerShape(14.dp),
                large = RoundedCornerShape(20.dp),
            ),
            content = content,
        )
    }
}
