package com.binwaps.cardmanager.ui.screens

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.mikrotik.MikrotikClient
import com.binwaps.cardmanager.util.Charset
import com.binwaps.cardmanager.util.CsvImporter
import com.binwaps.cardmanager.util.UserGenerator
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UsersScreen() {
    val context = LocalContext.current
    val users by Store.users.collectAsState()
    val scope = rememberCoroutineScope()
    var showGenerate by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }

    val csvPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val imported = CsvImporter.import(context, uri)
            Store.addUsers(imported)
            Toast.makeText(context, "تم استيراد ${imported.size} مستخدم", Toast.LENGTH_LONG).show()
        }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text("المستخدمون (${users.size})", fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(10.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { showGenerate = true }) {
                Icon(Icons.Filled.Add, null); Spacer(Modifier.width(4.dp)); Text("توليد")
            }
            OutlinedButton(onClick = { csvPicker.launch(arrayOf("text/*", "text/csv", "application/*")) }) {
                Icon(Icons.Filled.FileOpen, null); Spacer(Modifier.width(4.dp)); Text("استيراد CSV")
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(enabled = !busy, onClick = {
                busy = true
                scope.launch {
                    val r = MikrotikClient.fetchHotspotUsers(Store.settings.value)
                    busy = false
                    r.onSuccess {
                        Store.addUsers(it)
                        Toast.makeText(context, "تم جلب ${it.size} من الهوتسبوت", Toast.LENGTH_LONG).show()
                    }.onFailure {
                        Toast.makeText(context, "فشل الاتصال: ${it.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }) {
                Icon(Icons.Filled.CloudDownload, null); Spacer(Modifier.width(4.dp)); Text("جلب هوتسبوت")
            }
            OutlinedButton(enabled = !busy && users.isNotEmpty(), onClick = {
                busy = true
                scope.launch {
                    val r = MikrotikClient.createHotspotUsers(Store.settings.value, users)
                    busy = false
                    r.onSuccess {
                        Toast.makeText(context, "تم رفع $it مستخدم إلى الراوتر", Toast.LENGTH_LONG).show()
                    }.onFailure {
                        Toast.makeText(context, "فشل الرفع: ${it.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }) {
                Icon(Icons.Filled.CloudUpload, null); Spacer(Modifier.width(4.dp)); Text("رفع للراوتر")
            }
        }
        if (busy) {
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.height(20.dp).width(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text("جاري الاتصال بالراوتر…", color = Color.Gray, fontSize = 13.sp)
            }
        }
        Spacer(Modifier.height(10.dp))

        if (users.isNotEmpty()) {
            TextButton(onClick = { Store.clearUsers() }) {
                Icon(Icons.Filled.Delete, null, tint = Color.Red)
                Text("مسح الكل", color = Color.Red)
            }
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(users) { u ->
                Card {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(u.username, fontWeight = FontWeight.Bold)
                            Text(
                                listOf(
                                    "الرمز: ${u.password}",
                                    u.profile.takeIf { it.isNotBlank() }?.let { "الباقة: $it" },
                                    u.price.takeIf { it.isNotBlank() }?.let { "السعر: $it" },
                                ).filterNotNull().joinToString("  •  "),
                                fontSize = 12.sp, color = Color.Gray,
                            )
                        }
                        IconButton(onClick = { Store.setUsers(users - u) }) {
                            Icon(Icons.Filled.Delete, "حذف", tint = Color.Gray)
                        }
                    }
                }
            }
        }
    }

    if (showGenerate) {
        GenerateDialog(onDismiss = { showGenerate = false }) { generated ->
            Store.addUsers(generated)
            showGenerate = false
            Toast.makeText(context, "تم توليد ${generated.size} كرت", Toast.LENGTH_LONG).show()
        }
    }
}

@Composable
private fun GenerateDialog(onDismiss: () -> Unit, onGenerate: (List<com.binwaps.cardmanager.model.UserEntry>) -> Unit) {
    var count by remember { mutableStateOf("50") }
    var prefix by remember { mutableStateOf("") }
    var length by remember { mutableStateOf("6") }
    var charset by remember { mutableStateOf(Charset.DIGITS) }
    var samePassword by remember { mutableStateOf(true) }
    var passwordLength by remember { mutableStateOf("4") }
    var profile by remember { mutableStateOf("") }
    var price by remember { mutableStateOf("") }
    var validity by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("توليد دفعة كروت") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(count, { count = it }, label = { Text("العدد") }, modifier = Modifier.weight(1f))
                    OutlinedTextField(length, { length = it }, label = { Text("طول الاسم") }, modifier = Modifier.weight(1f))
                }
                OutlinedTextField(prefix, { prefix = it }, label = { Text("بادئة الاسم (اختياري)") }, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Charset.entries.forEach { c ->
                        FilterChip(selected = charset == c, onClick = { charset = c }, label = { Text(c.labelAr, fontSize = 11.sp) })
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(samePassword, { samePassword = it })
                    Text("كلمة المرور نفس اسم المستخدم")
                }
                if (!samePassword) {
                    OutlinedTextField(passwordLength, { passwordLength = it }, label = { Text("طول كلمة المرور") }, modifier = Modifier.fillMaxWidth())
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(price, { price = it }, label = { Text("السعر") }, modifier = Modifier.weight(1f))
                    OutlinedTextField(validity, { validity = it }, label = { Text("الصلاحية") }, modifier = Modifier.weight(1f))
                }
                OutlinedTextField(profile, { profile = it }, label = { Text("الباقة/البروفايل") }, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            Button(onClick = {
                val generated = UserGenerator.generate(
                    count = count.toIntOrNull()?.coerceIn(1, 5000) ?: 50,
                    prefix = prefix,
                    length = length.toIntOrNull()?.coerceIn(3, 20) ?: 6,
                    charset = charset,
                    samePassword = samePassword,
                    passwordLength = passwordLength.toIntOrNull()?.coerceIn(3, 20) ?: 4,
                    profile = profile,
                    price = price,
                    validity = validity,
                    serialStart = Store.users.value.size + 1,
                )
                onGenerate(generated)
            }) { Text("توليد") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("إلغاء") } },
    )
}
