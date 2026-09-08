package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.license.LicenseConnection
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.theme.*

@Composable
fun ServiceSetupScreen(onSaved: () -> Unit) {
    var endpoint by remember { mutableStateOf(LicenseConnection.url) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().background(ScreenGradient).verticalScroll(rememberScrollState()).padding(24.dp)) {
        Spacer(Modifier.height(32.dp))
        Text("ربط خدمة الاشتراكات", color = TextHi, fontSize = 22.sp, lineHeight = 32.sp)
        Spacer(Modifier.height(12.dp))
        Text("أدخل عنوان الخدمة من المهندس علي واقص. تستخدم لوحة التراخيص وتطبيق الطباعة العنوان نفسه.", color = TextMid)
        Spacer(Modifier.height(20.dp))
        AppField(endpoint, { endpoint = it; error = null }, "عنوان الخدمة HTTPS", Modifier.fillMaxWidth(), code = true, error = error)
        Spacer(Modifier.height(16.dp))
        NeonButton("حفظ ومتابعة", enabled = endpoint.isNotBlank()) {
            error = LicenseConnection.save(endpoint)
            if (error == null) onSaved()
        }
        Spacer(Modifier.height(20.dp))
        Text("الدعم: المهندس علي واقص — 776831921", color = TextMid)
    }
}
