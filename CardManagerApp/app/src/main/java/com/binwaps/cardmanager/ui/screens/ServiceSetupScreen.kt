package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.license.LicenseConnection
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextMid

/** شاشة توافق قديمة: نقطة الخدمة ثابتة ولا تحتاج إعداداً يدوياً. */
@Composable
fun ServiceSetupScreen(onSaved: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(ScreenGradient).padding(24.dp),
    ) {
        Spacer(Modifier.height(32.dp))
        Text("خدمة الاشتراكات جاهزة", color = TextHi, fontSize = 22.sp, lineHeight = 32.sp)
        Spacer(Modifier.height(12.dp))
        Text(
            "تم ربط التطبيق تلقائياً بالخدمة الرسمية المشتركة بين مدير الكروت ولوحة التراخيص. لا تحتاج إلى إدخال VPS أو رابط HTTPS.",
            color = TextMid,
        )
        Spacer(Modifier.height(20.dp))
        NeonButton("متابعة", enabled = true) { onSaved() }
        Spacer(Modifier.height(20.dp))
        Text("نقطة الاتصال: ${LicenseConnection.DEFAULT_URL}", color = TextMid, fontSize = 12.sp)
    }
}
