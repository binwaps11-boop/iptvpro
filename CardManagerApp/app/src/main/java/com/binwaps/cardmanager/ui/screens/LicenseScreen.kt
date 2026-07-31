package com.binwaps.cardmanager.ui.screens

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import com.binwaps.cardmanager.license.LicenseLink
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
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn

/**
 * شاشة الاشتراك:
 * 1) غير مسجّل → يُدخل بريده (جيميل) فتبدأ تجربة أسبوع.
 * 2) التجربة جارية → عدّاد الأيام المتبقية.
 * 3) انتهت → زر يفتح واتساب مزوّد الخدمة برسالة الطلب جاهزة.
 */
@Composable
fun LicenseScreen(
    blocking: Boolean,
    onActivated: () -> Unit,
    onBack: (() -> Unit)? = null,
    incomingKey: String? = null,
    onIncomingConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    val state by LicenseManager.state.collectAsState()
    val deviceCode = remember { LicenseManager.deviceCode() }
    var name by remember { mutableStateOf(LicenseManager.customerName()) }
    var email by remember { mutableStateOf(LicenseManager.customerEmail()) }
    var phone by remember { mutableStateOf(LicenseManager.customerPhone()) }
    var key by remember { mutableStateOf(LicenseManager.savedLicense()) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val serverReason by LicenseManager.reason.collectAsState()

    fun clipboard() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun copy(label: String, text: String) {
        clipboard().setPrimaryClip(android.content.ClipData.newPlainText(label, text))
        Toast.makeText(context, "نُسخ: $text", Toast.LENGTH_SHORT).show()
    }

    fun activate(value: String) {
        val message = LicenseManager.activate(value)
        if (message == null) {
            key = value
            error = null
            success = "تم التفعيل بنجاح"
            onActivated()
        } else {
            error = message
            success = null
        }
    }

    // تفعيل تلقائي عند وصول رابط تفعيل من مزوّد الخدمة
    LaunchedEffect(incomingKey) {
        val k = incomingKey ?: return@LaunchedEffect
        key = k
        activate(k)
        onIncomingConsumed()
    }

    val isRenewal = state is LicenseState.Expired ||
        (state as? LicenseState.Licensed)?.let { !it.lifetime && it.daysLeft <= 7 } == true

    val cloudReady by com.binwaps.cardmanager.data.Backend.ready.collectAsState()
    var requestSent by remember { mutableStateOf(false) }
    val accountId = remember(email) {
        if (email.isBlank()) "" else com.binwaps.cardmanager.data.Backend.accountId(email, deviceCode)
    }

    // استماع حي لحساب المشترك — يُفعَّل تلقائياً فور موافقة الأدمن
    androidx.compose.runtime.DisposableEffect(accountId, cloudReady) {
        val reg = if (accountId.isNotBlank() && cloudReady)
            com.binwaps.cardmanager.data.Backend.listenAccount(accountId) { acc ->
                if (acc != null && acc.approved) activate(acc.key)
            } else null
        onDispose { reg?.remove() }
    }

    /** يرسل الطلب: للخادم إن كان مُهيّأً، ثم سحابياً، وإلا عبر واتساب */
    fun sendRequest() {
        LicenseManager.setCustomerName(name)
        LicenseManager.setCustomerPhone(phone)
        if (com.binwaps.cardmanager.data.BackendConfig.licenseServerEnabled) {
            // الطلب يصل لوحة مزوّد الخدمة مباشرة ويبقى مسجّلاً حتى لو أُغلق التطبيق
            busy = true
            scope.launch {
                val msg = LicenseManager.requestOnline(isRenewal, "من التطبيق")
                busy = false
                if (msg == null) { requestSent = true; error = null } else error = msg
            }
            return
        }
        if (cloudReady) {
            com.binwaps.cardmanager.data.Backend.submitRequest(email, name, phone, deviceCode, isRenewal) { ok, _ ->
                requestSent = ok
            }
            return
        }
        val message = LicenseLink.requestMessage(deviceCode, name, isRenewal, email, phone)
        val wa = Intent(Intent.ACTION_VIEW, Uri.parse(LicenseLink.whatsappLink(message)))
        val opened = runCatching { context.startActivity(wa); true }.getOrDefault(false)
        if (!opened) {
            context.startActivity(
                Intent.createChooser(
                    Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, message)
                    },
                    "إرسال الطلب لمزوّد الخدمة",
                )
            )
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(22.dp))

        Box(
            Modifier.size(64.dp).background(NeonGradient, RoundedCornerShape(19.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                when (state) {
                    is LicenseState.Licensed -> Icons.Filled.VerifiedUser
                    is LicenseState.NeedsRegister -> Icons.Filled.PersonAdd
                    else -> Icons.Filled.Lock
                },
                null, tint = Ink, modifier = Modifier.size(32.dp),
            )
        }
        Spacer(Modifier.height(13.dp))

        when (val s = state) {
            is LicenseState.NeedsRegister -> {
                Text("مرحباً بك", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "سجّل بياناتك لتبدأ تجربة مجانية ٧ أيام",
                    fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }
            is LicenseState.Trial -> {
                Text("النسخة التجريبية", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "متبقٍ ${s.daysLeft} ${dayWord(s.daysLeft)} من التجربة المجانية",
                    fontSize = 13.sp, color = Warn, textAlign = TextAlign.Center,
                )
            }
            is LicenseState.Licensed -> {
                Text("الاشتراك مفعّل", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Lime)
                Text(
                    if (s.lifetime) "ترخيص دائم" else "اشتراك ${s.plan.labelAr} — متبقٍ ${s.daysLeft} يوم",
                    fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }
            LicenseState.TrialEnded -> {
                Text("انتهت التجربة", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "اطلب ترخيصاً لمتابعة الاستخدام",
                    fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }
            LicenseState.Expired -> {
                Text("انتهى الاشتراك", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Danger)
                Text("اطلب التجديد بضغطة واحدة", fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center)
            }
            LicenseState.Suspended -> {
                Text("تم إيقاف الاشتراك", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Danger)
                Text(
                    serverReason.ifBlank { "أوقف مزوّد الخدمة اشتراكك — تواصل معه لإعادة التفعيل" },
                    fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }
            LicenseState.ClockInvalid -> {
                Text("ساعة الجهاز غير صحيحة", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Warn)
                Text(
                    "تاريخ جهازك مُرجَع للخلف. صحّح التاريخ والوقت من إعدادات الجهاز، " +
                        "أو اتصل بالإنترنت مرة واحدة ليُضبط تلقائياً.",
                    fontSize = 13.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        if (state is LicenseState.ClockInvalid) {
            // مخرج واضح بدل تركه أمام رسالة بلا فعل
            GlassCard(Modifier.fillMaxWidth(), glow = Warn.copy(alpha = 0.45f), padding = 16) {
                Text("كيف تصلحها", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Spacer(Modifier.height(7.dp))
                Text(
                    "١) إعدادات الجهاز ← التاريخ والوقت ← فعّل «الضبط التلقائي».\n" +
                        "٢) أو اتصل بالإنترنت واضغط الزر بالأسفل.",
                    fontSize = 12.5.sp, lineHeight = 21.sp, color = TextMid,
                )
                Spacer(Modifier.height(12.dp))
                NeonButton(
                    if (busy) "جارٍ التحقق…" else "تحقق الآن عبر الإنترنت",
                    Modifier.fillMaxWidth(),
                    Icons.Filled.VerifiedUser,
                    enabled = !busy,
                ) {
                    busy = true
                    error = null
                    scope.launch {
                        val msg = LicenseManager.syncOnline(userInitiated = true)
                        busy = false
                        // syncOnline يعيد null أيضاً حين لا يوجد ما يُتحقق منه،
                        // فلا نترك الزر بلا أي رد فعل ظاهر
                        error = msg ?: if (state is LicenseState.ClockInvalid) {
                            "ما زالت ساعة الجهاز غير صحيحة — صحّحها من الإعدادات"
                        } else null
                    }
                }
                error?.let {
                    Spacer(Modifier.height(10.dp))
                    Text(it, fontSize = 12.sp, color = Danger)
                }
            }
            Spacer(Modifier.height(30.dp))
            return@Column
        }

        if (state is LicenseState.NeedsRegister) {
            // ===== التسجيل =====
            // الترتيب يتبع المنطق: من أنت ← كيف نصلك ← بريدك (معرّف الحساب).
            // كل حقل إلزامي ويُتحقق منه فور الكتابة لا بعد الضغط.
            val nameOk = name.trim().length >= 3
            val digits = phone.filter { it.isDigit() }
            val phoneOk = digits.length in 9..15
            val emailOk = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$").matches(email.trim())
            val formOk = nameOk && phoneOk && emailOk

            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.4f), padding = 16) {
                Text("إنشاء حسابك", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "بيانات صحيحة تضمن وصول ترخيصك ودعمك عند الحاجة",
                    fontSize = 11.sp, color = TextLow,
                )
                Spacer(Modifier.height(14.dp))

                FieldWithHint(
                    label = "الاسم الكامل",
                    value = name,
                    onChange = { name = it; error = null },
                    ok = nameOk,
                    hint = if (name.isBlank()) "مثال: علي واقص" else "أدخل ثلاثة أحرف على الأقل",
                )
                Spacer(Modifier.height(11.dp))

                FieldWithHint(
                    label = "رقم الجوال (واتساب)",
                    value = phone,
                    onChange = { phone = it.filter { c -> c.isDigit() }; error = null },
                    ok = phoneOk,
                    hint = if (phone.isBlank()) "مثال: 776831921" else "الرقم يجب أن يكون بين ٩ و١٥ رقماً",
                    numeric = true,
                    ltr = true,
                )
                Spacer(Modifier.height(11.dp))

                FieldWithHint(
                    label = "البريد الإلكتروني",
                    value = email,
                    onChange = { email = it.trim(); error = null },
                    ok = emailOk,
                    hint = if (email.isBlank()) "مثال: name@gmail.com" else "أدخل بريداً صحيحاً يحوي @ ونطاقاً",
                    ltr = true,
                    email = true,
                )

                error?.let {
                    Spacer(Modifier.height(11.dp))
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .background(Danger.copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                            .border(1.dp, Danger.copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                            .padding(11.dp),
                    ) { Text(it, fontSize = 12.sp, color = Danger) }
                }

                Spacer(Modifier.height(16.dp))
                NeonButton(
                    if (busy) "جارٍ إنشاء حسابك…" else "ابدأ التجربة المجانية — ٧ أيام",
                    Modifier.fillMaxWidth(),
                    Icons.Filled.PersonAdd,
                    enabled = formOk && !busy,
                ) {
                    busy = true
                    error = null
                    scope.launch {
                        // التسجيل على الخادم أولاً — هو من يقرر أهليّة الجهاز
                        val msg = LicenseManager.registerFull(email, name, phone)
                        busy = false
                        if (msg != null) {
                            error = msg
                        } else {
                            if (cloudReady) {
                                com.binwaps.cardmanager.data.Backend
                                    .registerAccount(email, name, phone, deviceCode)
                            }
                            onActivated()
                        }
                    }
                }
                Spacer(Modifier.height(9.dp))
                Text(
                    when {
                        busy -> "نتحقق من جهازك لدى مزوّد الخدمة…"
                        formOk -> "بياناتك مكتملة — اضغط للبدء"
                        else -> "أكمل الحقول الثلاثة لتفعيل الزر"
                    },
                    fontSize = 12.sp,
                    color = if (formOk) Lime else TextMid,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "يُسجَّل حسابك لدى مزوّد الخدمة ليُربط ترخيصك برقم جوالك وجهازك.",
                    fontSize = 11.5.sp, lineHeight = 18.sp, color = TextMid,
                    modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center,
                )
            }
        } else {
            // ===== طلب الترخيص عبر واتساب =====
            GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.45f), padding = 16) {
                Text(
                    if (isRenewal) "طلب تجديد الاشتراك" else "طلب الترخيص",
                    fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextHi,
                )
                Spacer(Modifier.height(9.dp))
                // الطلب كان يُرسل باسم وجوال فارغين فيصل الأدمن بلا وسيلة تواصل
                val reqNameOk = name.trim().length >= 3
                val reqPhoneOk = phone.filter { it.isDigit() }.length in 9..15
                AppField(
                    name, { name = it; LicenseManager.setCustomerName(it) }, "اسمك",
                    Modifier.fillMaxWidth(),
                    error = if (!reqNameOk) "الاسم مطلوب (٣ أحرف على الأقل)" else null,
                )
                Spacer(Modifier.height(8.dp))
                AppField(
                    phone,
                    { v -> phone = v.filter { it.isDigit() }; LicenseManager.setCustomerPhone(phone) },
                    "رقم جوالك (واتساب)",
                    Modifier.fillMaxWidth(), numeric = true, ltr = true,
                    error = if (!reqPhoneOk) "أدخل رقماً بين ٩ و١٥ خانة" else null,
                )
                Spacer(Modifier.height(11.dp))

                Text("رمز جهازك — اضغط عليه لنسخه", fontSize = 12.sp, color = TextMid)
                Spacer(Modifier.height(4.dp))
                // هذا هو ما يجب أن يرسله المستخدم؛ كان نصاً غير قابل للتحديد
                Box(
                    Modifier
                        .fillMaxWidth()
                        .background(Neon.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
                        .border(1.dp, Neon.copy(alpha = 0.40f), RoundedCornerShape(12.dp))
                        .clickable { copy("رمز الجهاز", deviceCode) }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        deviceCode,
                        fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Neon,
                        letterSpacing = 2.sp,
                    )
                }
                Spacer(Modifier.height(13.dp))

                val serverMode = com.binwaps.cardmanager.data.BackendConfig.licenseServerEnabled
                NeonButton(
                    when {
                        busy -> "جارٍ الإرسال…"
                        requestSent -> "أُرسل الطلب ✓ — بانتظار الموافقة"
                        serverMode || cloudReady -> if (isRenewal) "طلب التجديد" else "طلب الترخيص"
                        isRenewal -> "طلب التجديد عبر واتساب"
                        else -> "طلب الترخيص عبر واتساب"
                    },
                    Modifier.fillMaxWidth(), Icons.Filled.Chat,
                    enabled = !requestSent && !busy && reqNameOk && reqPhoneOk,
                ) { sendRequest() }

                if (requestSent) {
                    Spacer(Modifier.height(9.dp))
                    // التأكيد كان نصاً داخل زر معطّل فلا يكاد يُرى — الآن شريط واضح
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .background(Lime.copy(alpha = 0.12f), RoundedCornerShape(11.dp))
                            .border(1.dp, Lime.copy(alpha = 0.40f), RoundedCornerShape(11.dp))
                            .padding(12.dp),
                    ) {
                        Text(
                            "وصل طلبك لمزوّد الخدمة. فور الموافقة يُفعَّل التطبيق تلقائياً.",
                            fontSize = 12.5.sp, lineHeight = 19.sp, color = Lime,
                        )
                    }
                }

                Spacer(Modifier.height(7.dp))
                Text(
                    when {
                        serverMode ->
                            "طلبك يصل مزوّد الخدمة فوراً مربوطاً برقم جوالك ورمز جهازك، " +
                                "ويُفعَّل التطبيق تلقائياً عند الموافقة."
                        cloudReady ->
                            "طلبك يصل مزوّد الخدمة لحظياً، ويمكنك مراسلته بالأسفل. " +
                                "فور الموافقة يُفعَّل التطبيق تلقائياً دون أي خطوة منك."
                        else ->
                            "يفتح محادثة واتساب مع مزوّد الخدمة ورسالة الطلب جاهزة — أرسلها فقط، " +
                                "وسيصلك مفتاح التفعيل لتضغطه فيُفعَّل التطبيق تلقائياً."
                    },
                    fontSize = 12.sp, lineHeight = 19.sp, color = TextMid, textAlign = TextAlign.Center,
                )
            }

            // الدردشة الحية مع مزوّد الخدمة — تظهر عند تفعيل الربط السحابي
            if (cloudReady && accountId.isNotBlank()) {
                Spacer(Modifier.height(14.dp))
                ChatPanel(accountId = accountId, asAdmin = false)
            }

            Spacer(Modifier.height(14.dp))

            // إدخال المفتاح يدوياً (احتياطي)
            GlassCard(Modifier.fillMaxWidth(), glow = Neon.copy(alpha = 0.35f), padding = 16) {
                Text("لديك مفتاح؟", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text(
                    "إن ضغطت رابط التفعيل سيتم كل شيء تلقائياً — هذا الحقل للحالات الاستثنائية.",
                    fontSize = 10.5.sp, color = TextLow,
                )
                Spacer(Modifier.height(9.dp))
                AppField(
                    key, { key = it; error = null }, "الصق المفتاح هنا",
                    Modifier.fillMaxWidth(), ltr = true,
                )
                Spacer(Modifier.height(8.dp))
                GhostButton("لصق من الحافظة", Modifier.fillMaxWidth(), Icons.Filled.ContentPaste) {
                    val text = clipboard().primaryClip?.getItemAt(0)?.text?.toString().orEmpty()
                    if (text.isBlank()) {
                        Toast.makeText(context, "الحافظة فارغة", Toast.LENGTH_SHORT).show()
                    } else {
                        // يستخرج المفتاح من الرسالة كاملة أو الرابط — لا يتأثر بالنص المحيط
                        key = LicenseLink.extractKey(text) ?: text.trim()
                        error = null
                    }
                }

                error?.let {
                    Spacer(Modifier.height(10.dp))
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .background(Danger.copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                            .border(1.dp, Danger.copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                            .padding(11.dp)
                    ) { Text(it, fontSize = 12.sp, color = Danger) }
                }
                success?.let {
                    Spacer(Modifier.height(10.dp))
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .background(Lime.copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                            .border(1.dp, Lime.copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                            .padding(11.dp)
                    ) { Text(it, fontSize = 12.sp, color = Lime) }
                }

                Spacer(Modifier.height(12.dp))
                NeonButton("تفعيل", Modifier.fillMaxWidth(), Icons.Filled.VerifiedUser, enabled = key.isNotBlank()) {
                    activate(LicenseLink.extractKey(key) ?: key)
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

        Spacer(Modifier.height(30.dp))
    }
}

private fun dayWord(n: Int): String = when (n) {
    1 -> "يوم"
    2 -> "يومان"
    in 3..10 -> "أيام"
    else -> "يوماً"
}

/**
 * حقل إدخال بعنوان فوقه وتحقق فوري تحته.
 *
 * سبب وجوده: الحقول القديمة كانت تعتمد على نص داخلي واحد يختفي عند الكتابة،
 * فلا يعرف المستخدم ما المطلوب ولا لماذا رُفض إدخاله إلا بعد الضغط.
 * هنا العنوان ثابت، والحالة تظهر لحظياً: ✓ خضراء عند الصحة، وتلميح عند النقص.
 */
@Composable
private fun FieldWithHint(
    label: String,
    value: String,
    onChange: (String) -> Unit,
    ok: Boolean,
    hint: String,
    numeric: Boolean = false,
    ltr: Boolean = false,
    email: Boolean = false,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, fontSize = 12.5.sp, color = TextMid, fontWeight = FontWeight.SemiBold)
            if (ok) {
                Spacer(Modifier.width(6.dp))
                Text("✓", fontSize = 13.sp, color = Lime, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.height(5.dp))
        AppField(
            value = value,
            onValueChange = onChange,
            label = label,
            modifier = Modifier.fillMaxWidth(),
            numeric = numeric,
            // التلميح يظهر تحت الحقل نفسه لا في صندوق بعيد أسفل البطاقة،
            // ويصير أحمر عند النقص فيعرف المستخدم أي حقل يصلح بالضبط
            error = if (value.isNotBlank() && !ok) hint else null,
            supporting = if (value.isBlank()) hint else null,
            ltr = ltr,
            email = email,
        )
    }
}
