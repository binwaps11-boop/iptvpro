package com.binwaps.cardmanager.ui.screens

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings by Store.settings.collectAsState()
    var testBusy by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("الإعدادات", fontSize = 20.sp, fontWeight = FontWeight.Bold)

        Card {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("اتصال الراوتر (MikroTik API)", fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = settings.mikrotikHost,
                        onValueChange = { Store.updateSettings(settings.copy(mikrotikHost = it)) },
                        label = { Text("عنوان الراوتر") }, modifier = Modifier.weight(2f),
                    )
                    OutlinedTextField(
                        value = settings.mikrotikPort.toString(),
                        onValueChange = { it.toIntOrNull()?.let { p -> Store.updateSettings(settings.copy(mikrotikPort = p)) } },
                        label = { Text("المنفذ") }, modifier = Modifier.weight(1f),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = settings.mikrotikUser,
                        onValueChange = { Store.updateSettings(settings.copy(mikrotikUser = it)) },
                        label = { Text("المستخدم") }, modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = settings.mikrotikPassword,
                        onValueChange = { Store.updateSettings(settings.copy(mikrotikPassword = it)) },
                        label = { Text("كلمة المرور") }, modifier = Modifier.weight(1f),
                        visualTransformation = PasswordVisualTransformation(),
                    )
                }
                Button(enabled = !testBusy, onClick = {
                    testBusy = true
                    scope.launch {
                        val r = MikrotikClient.fetchHotspotUsers(Store.settings.value)
                        testBusy = false
                        r.onSuccess {
                            Toast.makeText(context, "نجح الاتصال ✓ (${it.size} مستخدم)", Toast.LENGTH_LONG).show()
                        }.onFailure {
                            Toast.makeText(context, "فشل الاتصال: ${it.message}", Toast.LENGTH_LONG).show()
                        }
                    }
                }) { Text(if (testBusy) "جاري الفحص…" else "اختبار الاتصال") }
            }
        }

        Card {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("رمز QR والدخول التلقائي", fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = settings.hotspotLoginUrl,
                    onValueChange = { Store.updateSettings(settings.copy(hotspotLoginUrl = it)) },
                    label = { Text("رابط صفحة دخول الهوتسبوت") }, modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = settings.wifiSsid,
                        onValueChange = { Store.updateSettings(settings.copy(wifiSsid = it)) },
                        label = { Text("اسم الشبكة SSID") }, modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = settings.wifiPassword,
                        onValueChange = { Store.updateSettings(settings.copy(wifiPassword = it)) },
                        label = { Text("كلمة مرور الواي فاي") }, modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        Card {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("الطباعة", fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = settings.currency,
                    onValueChange = { Store.updateSettings(settings.copy(currency = it)) },
                    label = { Text("العملة") }, modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = settings.a4MarginMm.toString(),
                        onValueChange = { it.toFloatOrNull()?.let { v -> Store.updateSettings(settings.copy(a4MarginMm = v)) } },
                        label = { Text("هامش A4 مم") }, modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = settings.a4SpacingMm.toString(),
                        onValueChange = { it.toFloatOrNull()?.let { v -> Store.updateSettings(settings.copy(a4SpacingMm = v)) } },
                        label = { Text("تباعد الكروت مم") }, modifier = Modifier.weight(1f),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = settings.thermalFeedMm.toString(),
                        onValueChange = { it.toFloatOrNull()?.let { v -> Store.updateSettings(settings.copy(thermalFeedMm = v)) } },
                        label = { Text("تغذية الورق مم") }, modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = settings.thermalDpi.toString(),
                        onValueChange = { it.toIntOrNull()?.let { v -> Store.updateSettings(settings.copy(thermalDpi = v)) } },
                        label = { Text("دقة الطابعة DPI") }, modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        Text(
            "مدير الكروت v1.0 — إنشاء وطباعة كروت اليوزر منجر والهوتسبوت",
            fontSize = 12.sp,
        )
        Spacer(Modifier.height(30.dp))
    }
}
