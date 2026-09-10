package com.binwaps.cardmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import com.binwaps.cardmanager.license.LicenseConnection
import com.binwaps.cardmanager.ui.theme.CardManagerTheme

/** لوحة الإدارة تستخدم نقطة الخدمة المضمّنة نفسها التي يستخدمها تطبيق المشترك. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        com.binwaps.cardmanager.data.CrashLogger.install(this)
        LicenseConnection.init(this)
        AdminApi.init(this)
        setContent {
            CardManagerTheme {
                ServerAdminScreen()
            }
        }
    }
}
