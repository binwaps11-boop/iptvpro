package com.binwaps.cardmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import com.binwaps.cardmanager.license.LicenseConnection
import com.binwaps.cardmanager.ui.screens.ServiceSetupScreen
import com.binwaps.cardmanager.ui.theme.CardManagerTheme

/** Administrative authority exists only on the server; this APK cannot issue licenses. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        com.binwaps.cardmanager.data.CrashLogger.install(this)
        LicenseConnection.init(this)
        AdminApi.init(this)
        setContent {
            CardManagerTheme {
                var configured by remember { mutableStateOf(AdminApi.configured) }
                if (!configured) ServiceSetupScreen { configured = AdminApi.configured }
                else ServerAdminScreen()
            }
        }
    }
}
