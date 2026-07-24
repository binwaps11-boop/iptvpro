package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.ui.components.CardPreview
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.Violet

@Composable
fun TemplatesScreen(navController: NavController) {
    val templates by Store.templates.collectAsState()

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                SectionHeader("قوالب الكروت", "${templates.size} قالب", Icons.Filled.Layers)
            }
            GhostButton("قالب جديد", icon = Icons.Filled.Add) {
                val t = Store.defaultTemplate().copy(id = Store.newId(), name = "قالب جديد")
                Store.upsertTemplate(t)
                navController.navigate("editor/${t.id}")
            }
        }
        Spacer(Modifier.height(14.dp))

        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(templates.size) { i ->
                val t = templates[i]
                GlassCard(
                    Modifier.fillMaxWidth().clickable { navController.navigate("editor/${t.id}") },
                    padding = 10,
                ) {
                    CardPreview(template = t, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(9.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(t.name, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
                            Text(
                                "${t.widthMm.toInt()}×${t.heightMm.toInt()} مم  •  ${t.fields.size} حقل" +
                                    if (t.backgroundPath.isNotBlank()) "  •  خلفية مخصصة" else "",
                                fontSize = 11.sp, color = TextLow,
                            )
                        }
                        IconButton(onClick = { navController.navigate("editor/${t.id}") }) {
                            Icon(Icons.Filled.Edit, "تعديل", tint = Neon, modifier = Modifier.size(19.dp))
                        }
                        IconButton(onClick = {
                            Store.upsertTemplate(t.copy(id = Store.newId(), name = t.name + " (نسخة)"))
                        }) {
                            Icon(Icons.Filled.ContentCopy, "نسخ", tint = Violet, modifier = Modifier.size(19.dp))
                        }
                        if (templates.size > 1) {
                            IconButton(onClick = { Store.deleteTemplate(t.id) }) {
                                Icon(Icons.Filled.Delete, "حذف", tint = Danger, modifier = Modifier.size(19.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}
