package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.ui.components.CardPreview

@Composable
fun TemplatesScreen(navController: NavController) {
    val templates by Store.templates.collectAsState()

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("قوالب الكروت", fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Button(onClick = {
                val t = Store.defaultTemplate().copy(id = Store.newId(), name = "قالب جديد")
                Store.upsertTemplate(t)
                navController.navigate("editor/${t.id}")
            }) {
                Icon(Icons.Filled.Add, null); Text("جديد")
            }
        }
        Spacer(Modifier.height(12.dp))

        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(templates, key = { it.id }) { t ->
                Card(
                    elevation = CardDefaults.cardElevation(3.dp),
                    modifier = Modifier.fillMaxWidth().clickable { navController.navigate("editor/${t.id}") },
                ) {
                    Column(Modifier.padding(10.dp)) {
                        CardPreview(template = t, modifier = Modifier.fillMaxWidth())
                        Spacer(Modifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(t.name, fontWeight = FontWeight.Bold)
                                Text(
                                    "${t.widthMm}×${t.heightMm} مم  •  ${t.fields.size} حقل",
                                    fontSize = 12.sp, color = Color.Gray,
                                )
                            }
                            IconButton(onClick = { navController.navigate("editor/${t.id}") }) {
                                Icon(Icons.Filled.Edit, "تعديل")
                            }
                            IconButton(onClick = {
                                Store.upsertTemplate(t.copy(id = Store.newId(), name = t.name + " (نسخة)"))
                            }) {
                                Icon(Icons.Filled.ContentCopy, "نسخ")
                            }
                            IconButton(onClick = { Store.deleteTemplate(t.id) }) {
                                Icon(Icons.Filled.Delete, "حذف", tint = Color.Red)
                            }
                        }
                    }
                }
            }
        }
    }
}
