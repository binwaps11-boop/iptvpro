package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Style
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.ui.components.CardPreview
import com.binwaps.cardmanager.ui.theme.Teal

@Composable
fun HomeScreen(navController: NavController) {
    val users by Store.users.collectAsState()
    val templates by Store.templates.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("مدير الكروت", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Teal)
        Text(
            "إنشاء وطباعة كروت اليوزر منجر والهوتسبوت",
            fontSize = 14.sp,
            color = Color.Gray,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            StatCard("المستخدمون", users.size.toString(), Icons.Filled.People, Modifier.weight(1f)) {
                navController.navigate("users")
            }
            StatCard("القوالب", templates.size.toString(), Icons.Filled.Style, Modifier.weight(1f)) {
                navController.navigate("templates")
            }
        }

        templates.firstOrNull()?.let { t ->
            Text("معاينة القالب", fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Card(elevation = CardDefaults.cardElevation(4.dp)) {
                CardPreview(template = t, modifier = Modifier.fillMaxWidth().padding(10.dp))
            }
        }

        Text("إجراءات سريعة", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        ActionRow("إنشاء دفعة كروت جديدة", Icons.Filled.Add) { navController.navigate("users") }
        ActionRow("تصميم قالب كرت", Icons.Filled.Style) { navController.navigate("templates") }
        ActionRow("طباعة الكروت", Icons.Filled.Print) { navController.navigate("print") }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun StatCard(title: String, value: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Card(modifier = modifier.clickable(onClick = onClick), elevation = CardDefaults.cardElevation(2.dp)) {
        Column(Modifier.padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null, tint = Teal, modifier = Modifier.size(28.dp))
            Text(value, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text(title, fontSize = 13.sp, color = Color.Gray)
        }
    }
}

@Composable
private fun ActionRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(
                Modifier
                    .size(38.dp)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), CircleShape),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(icon, contentDescription = null, tint = Teal, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.size(12.dp))
            Text(title, fontSize = 15.sp)
        }
    }
}
