package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Backend
import com.binwaps.cardmanager.data.ChatMessage
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Ink
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * لوحة دردشة حية بين الأدمن والمشترك — نفس المحادثة يراها الطرفان.
 * [asAdmin] يحدد جهة المرسِل ومحاذاة الفقاعات.
 */
@Composable
fun ChatPanel(accountId: String, asAdmin: Boolean, modifier: Modifier = Modifier) {
    var messages by remember(accountId) { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var draft by remember(accountId) { mutableStateOf("") }
    val listState = rememberLazyListState()
    val timeFmt = remember { SimpleDateFormat("HH:mm", Locale.US) }

    DisposableEffect(accountId) {
        val reg = Backend.listenChat(accountId) { messages = it }
        onDispose { reg?.remove() }
    }
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    GlassCard(modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.3f), padding = 12) {
        Text("الدردشة مع " + if (asAdmin) "المشترك" else "مزوّد الخدمة",
            fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextHi)
        Spacer(Modifier.height(9.dp))

        if (messages.isEmpty()) {
            Text("لا رسائل بعد — اكتب أول رسالة", fontSize = 11.5.sp, color = TextLow)
        }
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().heightIn(max = 260.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(messages.size) { i ->
                val m = messages[i]
                val mine = m.fromAdmin == asAdmin
                Row(Modifier.fillMaxWidth()) {
                    if (mine) Spacer(Modifier.weight(1f))
                    Column(
                        Modifier
                            .background(
                                if (mine) Neon.copy(alpha = 0.16f) else Panel,
                                RoundedCornerShape(12.dp),
                            )
                            .padding(horizontal = 11.dp, vertical = 7.dp),
                    ) {
                        Text(m.text, fontSize = 12.5.sp, color = TextHi)
                        Text(
                            timeFmt.format(Date(m.at)),
                            fontSize = 8.5.sp, color = TextLow,
                            modifier = Modifier.align(Alignment.End),
                        )
                    }
                    if (!mine) Spacer(Modifier.weight(1f))
                }
            }
        }

        Spacer(Modifier.height(9.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                AppField(draft, { draft = it }, "اكتب رسالة…", Modifier.fillMaxWidth())
            }
            Spacer(Modifier.width(8.dp))
            IconButton(
                onClick = {
                    val t = draft.trim()
                    if (t.isNotBlank()) {
                        Backend.sendMessage(accountId, asAdmin, t)
                        draft = ""
                    }
                },
                modifier = Modifier.background(Lime, RoundedCornerShape(12.dp)),
            ) { Icon(Icons.Filled.Send, "إرسال", tint = Ink) }
        }
    }
}
