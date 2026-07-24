package com.binwaps.cardmanager.ui.screens

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.license.LicenseManager
import com.binwaps.cardmanager.license.LicenseState
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Ink
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.NeonGradient
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn

/**
 * شاشة التفعيل: تعرض رمز الجهاز ليُرسل للأدمن، وتستقبل مفتاح الترخيص.
 * [blocking] = التجربة انتهت ولا يمكن استخدام التطبيق حتى التفعيل.
 */
@Composable
fun LicenseScreen(blocking: Boolean, onActivated: () -> Unit, onBack: (() -> Unit)? = null) {
    val context = LocalContext.current
    val state by LicenseManager.state.collectAsState()
    val deviceCode = remember { LicenseManager.deviceCode() }
    var key by remember { mutableStateOf(LicenseManager.savedLicense()) }
    var error by remember { mutableStateOf<String?>(null) }

    fun clipboard() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(24.dp))

        Box(
            Modifier.size(64.dp).background(NeonGradient, RoundedCornerShape(19.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (state is LicenseState.Licensed) Icons.Filled.VerifiedUser else Icons.Filled.Lock,
                null, tint = Ink, modifier = Modifier.size(32.dp),
            )
        }
        Spacer(Modifier.height(13.dp))

        // الحالة الحالية
        when (val s = state) {
            is LicenseState.Trial -> {
                Text("النسخة التجريبية", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "متبقٍ ${s.daysLeft} ${if (s.daysLeft == 1) "يوم" else "أيام"} من الفترة التجريبية",
                    fontSize = 13.sp, color = Warn, textAlign = TextAlign.Center,
                )
            }
            is LicenseState.Licensed -> {
                Text("التطبيق مفعّل", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Lime)
                Text(
                    if (s.lifetime) "ترخيص دائم" else "اشتراك ${s.plan.labelAr} — متبقٍ ${s.daysLeft} يوم",
                    fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }
            LicenseState.TrialEnded -> {
                Text("انتهت الفترة التجريبية", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text("أدخل مفتاح الترخيص لمتابعة الاستخدام", fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center)
            }
            LicenseState.Expired -> {
                Text("انتهى الاشتراك", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Danger)
                Text("جدّد اشتراكك بمفتاح جديد", fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center)
            }
        }

        Spacer(Modifier.height(22.dp))

        // رمز الجهاز
        GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.4f), padding = 16) {
            Text("رمز جهازك", fontSize = 12.sp, color = TextLow)
            Spacer(Modifier.height(7.dp))
            Text(
                deviceCode,
                fontSize = 25.sp, fontWeight = FontWeight.Bold, color = Neon,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(9.dp))
            Text(
                "أرسل هذا الرمز لمزوّد الخدمة ليصدر لك مفتاح ترخيص خاصاً بهذا الجوال فقط.",
                fontSize = 11.5.sp, color = TextMid, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                GhostButton("نسخ الرمز", Modifier.weight(1f), Icons.Filled.ContentCopy) {
                    clipboard().setPrimaryClip(android.content.ClipData.newPlainText("device", deviceCode))
                    Toast.makeText(context, "تم نسخ رمز الجهاز", Toast.LENGTH_SHORT).show()
                }
                GhostButton("إرسال", Modifier.weight(1f), Icons.Filled.Share, color = Violet) {
                    context.startActivity(
                        Intent.createChooser(
                            Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, "رمز جهازي لتفعيل مدير الكروت:\n$deviceCode")
                            },
                            "إرسال رمز الجهاز",
                        )
                    )
                }
            }
        }

        Spacer(Modifier.height(16.dp))

        // إدخال المفتاح
        GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 16) {
            Text("مفتاح الترخيص", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
            Spacer(Modifier.height(10.dp))
            AppField(key, { key = it; error = null }, "الصق المفتاح هنا", Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            GhostButton("لصق من الحافظة", Modifier.fillMaxWidth(), Icons.Filled.ContentPaste) {
                val text = clipboard().primaryClip?.getItemAt(0)?.text?.toString().orEmpty()
                if (text.isBlank()) {
                    Toast.makeText(context, "الحافظة فارغة", Toast.LENGTH_SHORT).show()
                } else {
                    key = text.trim(); error = null
                }
            }

            if (error != null) {
                Spacer(Modifier.height(10.dp))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(Danger.copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                        .border(1.dp, Danger.copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                        .padding(11.dp)
                ) { Text(error!!, fontSize = 12.sp, color = Danger) }
            }

            Spacer(Modifier.height(13.dp))
            NeonButton("تفعيل", Modifier.fillMaxWidth(), Icons.Filled.VerifiedUser, enabled = key.isNotBlank()) {
                val message = LicenseManager.activate(key)
                if (message == null) {
                    Toast.makeText(context, "تم التفعيل بنجاح ✓", Toast.LENGTH_LONG).show()
                    onActivated()
                } else {
                    error = message
                }
            }
        }

        if (!blocking && onBack != null) {
            Spacer(Modifier.height(14.dp))
            Text(
                "رجوع",
                fontSize = 13.sp, color = TextMid,
                modifier = Modifier.clickable(onClick = onBack).padding(10.dp),
            )
        }

        if (state is LicenseState.Trial && blocking.not() && onBack != null) {
            Text(
                "يمكنك متابعة التجربة حتى انتهاء المدة",
                fontSize = 11.sp, color = TextLow,
            )
        }

        Spacer(Modifier.height(30.dp))
    }
}
