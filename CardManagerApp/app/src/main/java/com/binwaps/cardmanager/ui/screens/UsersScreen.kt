package com.binwaps.cardmanager.ui.screens

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.binwaps.cardmanager.model.CardMode
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.UploadTarget
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.NeonProgress
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.components.formatBytes
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn
import com.binwaps.cardmanager.util.Charset
import com.binwaps.cardmanager.util.CsvImporter
import com.binwaps.cardmanager.util.UserGenerator
import kotlinx.coroutines.launch

private enum class CardFilter(val labelAr: String) {
    ALL("الكل"),
    UNUSED("غير مستهلك"),
    IN_USE("قيد الاستخدام"),
    EXPIRED("منتهي"),
    HOTSPOT("هوتسبوت"),
    USER_MANAGER("يوزر منجر"),
    LOCAL("محلي"),
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun UsersScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val users by Store.users.collectAsState()
    val settings by Store.settings.collectAsState()
    var showGenerate by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var busyLabel by remember { mutableStateOf("") }
    var progress by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var message by remember { mutableStateOf<Pair<String, Boolean>?>(null) } // النص، هل هو خطأ
    var filter by remember { mutableStateOf(CardFilter.ALL) }
    var query by remember { mutableStateOf("") }
    // عرض تدريجي — القوائم الكبيرة (عشرات الآلاف) تُعرض على دفعات
    var showLimit by remember(filter, query) { mutableStateOf(300) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var bulkDialog by remember { mutableStateOf<String?>(null) }
    var editCard by remember { mutableStateOf<UserEntry?>(null) }
    var confirmClear by remember { mutableStateOf(false) }
    val selecting = selected.isNotEmpty()
    // سلة الصف تزيل الكرت من القائمة فقط (يبقى على الراوتر) — تأكيد يوضّح ذلك بدل حذفٍ صامت بضغطة
    var confirmRemove by remember { mutableStateOf<UserEntry?>(null) }
    confirmRemove?.let { u ->
        com.binwaps.cardmanager.ui.components.ConfirmDialog(
            title = "إزالة «${u.username}» من القائمة؟",
            body = if (u.routerId.isNotBlank())
                "يُزال من قائمة التطبيق فقط ويبقى على الراوتر (وسيعود مع المزامنة). لحذفه من الراوتر نهائياً حدّده ثم استعمل «حذف» في شريط التحديد."
            else "كرت محلي لم يُرفع بعد — سيُحذف نهائياً من التطبيق.",
            confirmLabel = if (u.routerId.isNotBlank()) "إزالة" else "حذف",
            onConfirm = { Store.setUsers(Store.users.value - u) },
            onDismiss = { confirmRemove = null },
        )
    }

    val csvPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            // القراءة على خيط خلفي مع التقاط الأخطاء — ملف تالف كان يُسقط التطبيق
            scope.launch {
                val res = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    runCatching { CsvImporter.import(context, uri) }
                }
                res.onSuccess { imported ->
                    Store.addUsers(imported)
                    message = if (imported.isEmpty())
                        "لم يُعثر على كروت في الملف — تأكد من تنسيقه" to true
                    else "تم استيراد ${imported.size} كرت من الملف" to false
                }.onFailure {
                    message = "تعذّرت قراءة الملف: ${it.message ?: "ملف غير صالح"}" to true
                }
            }
        }
    }

    // المهمة الجارية — ليتمكن المستخدم من إلغائها بدل الانتظار بلا مخرج
    var currentJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }

    fun run(label: String, block: suspend () -> Result<String>) {
        busy = true; busyLabel = label; message = null
        currentJob = scope.launch {
            val r = block()
            busy = false; progress = null; currentJob = null
            r.onSuccess { message = it to false }
                .onFailure { message = (it.message ?: "فشلت العملية") to true }
        }
    }

    val shown = remember(users, filter, query) {
        val base = when (filter) {
            CardFilter.ALL -> users
            CardFilter.UNUSED -> users.filter { it.status == CardStatus.UNUSED }
            CardFilter.IN_USE -> users.filter { it.status == CardStatus.IN_USE }
            CardFilter.EXPIRED -> users.filter { it.status == CardStatus.EXPIRED || it.status == CardStatus.DISABLED }
            CardFilter.HOTSPOT -> users.filter { it.source == CardSource.HOTSPOT }
            CardFilter.USER_MANAGER -> users.filter { it.source == CardSource.USER_MANAGER }
            CardFilter.LOCAL -> users.filter { it.source == CardSource.LOCAL }
        }
        val q = query.trim()
        if (q.isBlank()) base
        else base.filter {
            it.username.contains(q, true) || it.profile.contains(q, true) ||
                it.comment.contains(q, true) || it.batchTag.contains(q, true)
        }
    }

    // الرأس (النوع/الرفع/الجلب/البحث/التصنيف) عنصرٌ داخل القائمة نفسها فيتمرّر معها —
    // كان ثابتاً يبتلع ثلثي الشاشة ولا يبقى للكروت إلا شريط ضيق
    LazyColumn(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        item(key = "header") { Column {
        SectionHeader("الكروت", "${users.size} كرت — يُعرض ${shown.size}", Icons.Filled.CreditCard)
        Spacer(Modifier.height(12.dp))

        // نوع الكرت
        Text("نوع الكرت", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CardMode.entries.forEach { m ->
                Chip(m.labelAr, settings.cardMode == m) { Store.updateSettings(settings.copy(cardMode = m)) }
            }
        }
        Text(settings.cardMode.hintAr, fontSize = 11.5.sp, color = TextLow, modifier = Modifier.padding(top = 4.dp))

        Spacer(Modifier.height(10.dp))
        Text("مكان الرفع على الراوتر", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            UploadTarget.entries.forEach { t ->
                Chip(t.labelAr, settings.uploadTarget == t) { Store.updateSettings(settings.copy(uploadTarget = t)) }
            }
        }

        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f)) {
                NeonButton("توليد كروت", icon = Icons.Filled.AutoAwesome) { showGenerate = true }
            }
            GhostButton("استيراد CSV", icon = Icons.Filled.FileOpen) {
                csvPicker.launch(arrayOf("text/*", "text/csv", "text/comma-separated-values", "application/*"))
            }
        }

        Spacer(Modifier.height(9.dp))
        Text("جلب من الراوتر", fontSize = 12.sp, color = TextLow)
        Spacer(Modifier.height(6.dp))
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            GhostButton("كل الكروت", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                run("جاري جلب كل الكروت من الراوتر…") {
                    MikrotikClient.fetchAllCardsDetailed(Store.activeRouter(), foreground = true).map { f ->
                        val list = f.cards
                        Store.mergeRouterCards(list, f.sources)
                        val unused = list.count { it.status == CardStatus.UNUSED }
                        val expired = list.count { it.status == CardStatus.EXPIRED }
                        "تم جلب ${list.size} كرت — $unused غير مستهلك، $expired منتهي" +
                            if (CardSource.USER_MANAGER !in f.sources) " (تعذّر جلب اليوزر منجر — كروته السابقة بقيت كما هي)" else ""
                    }
                }
            }
            // جلب مصدر واحد يدمج كروته فقط — كان يمسح كروت المصدر الآخر من القائمة
            GhostButton("الهوتسبوت", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                run("جاري الجلب من الهوتسبوت…") {
                    MikrotikClient.fetchHotspotUsers(Store.activeRouter(), foreground = true).map { list ->
                        Store.mergeRouterCards(list, setOf(CardSource.HOTSPOT)); "تم جلب ${list.size} كرت من الهوتسبوت"
                    }
                }
            }
            GhostButton("اليوزر منجر", icon = Icons.Filled.CloudDownload, enabled = !busy) {
                run("جاري الجلب من اليوزر منجر…") {
                    MikrotikClient.fetchUserManagerUsers(Store.activeRouter(), foreground = true).map { list ->
                        Store.mergeRouterCards(list, setOf(CardSource.USER_MANAGER)); "تم جلب ${list.size} مستخدم من اليوزر منجر"
                    }
                }
            }
            // يرفع الكروت المحلية غير المرفوعة فقط — رفع الكل كان يكرر الموجود على الراوتر.
            // remember على users: بدونه يُمسح آلاف الكروت في كل تحديث لشريط
            // التقدم أثناء الرفع فتتجمّد الواجهة
            val pendingUpload = remember(users) { users.filter { it.routerId.isBlank() && !it.uploaded } }
            GhostButton(
                "رفع الجديد (${pendingUpload.size}) إلى ${settings.uploadTarget.labelAr}",
                icon = Icons.Filled.CloudUpload, color = Violet,
                enabled = !busy && pendingUpload.isNotEmpty(),
            ) {
                progress = 0 to pendingUpload.size
                val target = settings.uploadTarget
                run("جاري رفع ${pendingUpload.size} كرت إلى ${target.labelAr}…") {
                    val t0 = System.currentTimeMillis()
                    val created = java.util.Collections.synchronizedList(mutableListOf<String>())
                    // خانق التقدّم: نبضة لكل كرت من خيط الشبكة كانت تعيد تركيب الشاشة
                    // كلها مئات المرات في الثانية — تجمّد محسوس أثناء الرفع
                    var lastEmit = 0L
                    val onProgress: (Int, Int) -> Unit = { d, t ->
                        val now = System.currentTimeMillis()
                        if (d >= t || now - lastEmit > 120) { lastEmit = now; progress = d to t }
                    }
                    val onCreated: (UserEntry) -> Unit = { u ->
                        created.add(u.username)
                        // وسم تدريجي: مغادرة الشاشة أو إلغاء لا يضيّع سجل ما رُفع
                        if (created.size % 200 == 0) Store.markUploaded(created.toList())
                    }
                    val res = try {
                        if (target == UploadTarget.USER_MANAGER) {
                            MikrotikClient.createUserManagerUsers(
                                Store.activeRouter(), pendingUpload, onProgress = onProgress, onCreated = onCreated,
                            )
                        } else {
                            MikrotikClient.createHotspotUsers(
                                Store.activeRouter(), pendingUpload, onProgress = onProgress, onCreated = onCreated,
                            )
                        }
                    } finally {
                        // يُنفَّذ حتى عند الإلغاء: ما وصل الراوتر يُوسم مرفوعاً فلا يُرفع ثانية
                        Store.markUploaded(created.toList())
                    }
                    res.onSuccess { com.binwaps.cardmanager.data.SyncEngine.syncNow() }
                    // الفشل الجزئي لم يعد يظهر كنجاح أخضر: يُذكر العدد الفاشل صراحة
                    val requested = pendingUpload.size
                    res.mapCatching { ok ->
                        val failed = requested - ok
                        if (failed > 0) {
                            throw Exception(
                                "رُفع $ok من $requested — فشل $failed. الكروت محفوظة محلياً، " +
                                    "اضغط «رفع الجديد» لإعادة محاولة الباقي"
                            )
                        }
                        uploadSpeedMessage(ok, target.labelAr, System.currentTimeMillis() - t0)
                    }
                }
            }
            GhostButton("حذف المنتهية", icon = Icons.Filled.Delete, color = Warn, enabled = !busy) {
                run("جاري حذف الكروت المنتهية…") {
                    MikrotikClient.removeExpiredUsers(Store.activeRouter()).map { "تم حذف $it كرت منتهي من الراوتر" }
                }
            }
        }

        if (busy) {
            Spacer(Modifier.height(10.dp))
            Text(busyLabel, fontSize = 12.sp, color = Neon)
            // الأرقام الحقيقية أمام المستخدم: يفرّق بين «يعمل» و«متوقف»
            progress?.let { (d, t) ->
                Text("$d من $t", fontSize = 11.sp, color = TextMid)
            }
            Spacer(Modifier.height(5.dp))
            progress?.let { (d, t) -> NeonProgress(d.toFloat() / t.coerceAtLeast(1)) } ?: NeonProgress(0.4f)
            Spacer(Modifier.height(7.dp))
            GhostButton("إلغاء العملية", color = Warn) {
                currentJob?.cancel()
                currentJob = null
                busy = false
                progress = null
                message = "أُلغيت العملية — ما رُفع فعلاً موسوم مرفوعاً، والباقي يبقى في «رفع الجديد»" to false
            }
        }

        message?.let { (text, isError) ->
            Spacer(Modifier.height(10.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .background((if (isError) Danger else Lime).copy(alpha = 0.10f), RoundedCornerShape(11.dp))
                    .border(1.dp, (if (isError) Danger else Lime).copy(alpha = 0.35f), RoundedCornerShape(11.dp))
                    .clickable { message = null }
                    .padding(11.dp)
            ) { Text(text, fontSize = 12.sp, color = if (isError) Danger else Lime) }
        }

        Spacer(Modifier.height(12.dp))

        // شريط العمليات الجماعية
        if (selecting) {
            val chosen = users.filter { it.username in selected }
            GlassCard(Modifier.fillMaxWidth(), glow = Neon, padding = 11) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "محدد: ${selected.size}",
                        fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Neon,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        "تحديد الكل",
                        fontSize = 11.5.sp, color = TextMid,
                        modifier = Modifier
                            .clickable { selected = shown.map { it.username }.toSet() }
                            .padding(6.dp),
                    )
                    Text(
                        "إلغاء",
                        fontSize = 11.5.sp, color = Danger,
                        modifier = Modifier.clickable { selected = emptySet() }.padding(6.dp),
                    )
                }
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    GhostButton("تعطيل", enabled = !busy, color = Warn) {
                        progress = 0 to chosen.size
                        run("جاري تعطيل ${chosen.size} كرت…") {
                            MikrotikClient.bulkSetEnabled(Store.activeRouter(), chosen, false) { d, t -> progress = d to t }
                                .map { "تم تعطيل ${it.ok} كرت" + if (it.failed > 0) " — فشل ${it.failed}" else "" }
                        }
                    }
                    GhostButton("تفعيل", enabled = !busy, color = Lime) {
                        progress = 0 to chosen.size
                        run("جاري تفعيل ${chosen.size} كرت…") {
                            MikrotikClient.bulkSetEnabled(Store.activeRouter(), chosen, true) { d, t -> progress = d to t }
                                .map { "تم تفعيل ${it.ok} كرت" + if (it.failed > 0) " — فشل ${it.failed}" else "" }
                        }
                    }
                    GhostButton("تصفير العدادات", enabled = !busy) {
                        progress = 0 to chosen.size
                        run("جاري التصفير…") {
                            MikrotikClient.bulkResetCounters(Store.activeRouter(), chosen) { d, t -> progress = d to t }
                                .map { "تم تصفير ${it.ok} كرت" }
                        }
                    }
                    GhostButton("إرجاع غير مستهلك", enabled = !busy, color = Lime) {
                        progress = 0 to chosen.size
                        run("جاري الإرجاع…") {
                            MikrotikClient.bulkResetToUnused(Store.activeRouter(), chosen, "") { d, t -> progress = d to t }
                                .map { "تم إرجاع ${it.ok} كرت غير مستهلك" }
                        }
                    }
                    GhostButton("تغيير الباقة", enabled = !busy, color = Violet) { bulkDialog = "profile" }
                    GhostButton("نقل إلى اليوزر منجر", enabled = !busy, color = Neon) {
                        progress = 0 to chosen.size
                        run("جاري النقل إلى اليوزر منجر…") {
                            MikrotikClient.moveCards(
                                Store.activeRouter(), chosen,
                                com.binwaps.cardmanager.model.UploadTarget.USER_MANAGER,
                                deleteFromSource = false,
                            ) { d, t -> progress = d to t }.map { "تم نقل $it كرت إلى اليوزر منجر" }
                        }
                    }
                    GhostButton("نقل إلى الهوتسبوت", enabled = !busy, color = Neon) {
                        progress = 0 to chosen.size
                        run("جاري النقل إلى الهوتسبوت…") {
                            MikrotikClient.moveCards(
                                Store.activeRouter(), chosen,
                                com.binwaps.cardmanager.model.UploadTarget.HOTSPOT,
                                deleteFromSource = false,
                            ) { d, t -> progress = d to t }.map { "تم نقل $it كرت إلى الهوتسبوت" }
                        }
                    }
                    GhostButton("تمديد الصلاحية", enabled = !busy, color = Violet) { bulkDialog = "extend" }
                    GhostButton("فك الربط بالجهاز", enabled = !busy, color = Warn) {
                        progress = 0 to chosen.size
                        run("جاري فك الربط…") {
                            MikrotikClient.clearBoundDevice(Store.activeRouter(), chosen) { d, t -> progress = d to t }
                                .map { "تم فك ربط $it كرت — يعمل الآن على أي جهاز" }
                        }
                    }
                    GhostButton("تصدير CSV", enabled = !busy) {
                        // الكتابة على خيط خلفي مع التقاط الأخطاء — امتلاء الذاكرة
                        // كان يُسقط التطبيق بدل إظهار رسالة
                        scope.launch {
                            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                runCatching { com.binwaps.cardmanager.util.CsvExporter.exportCards(context, chosen) }
                            }.onSuccess { f ->
                                com.binwaps.cardmanager.util.CsvExporter.share(context, f, "تصدير الكروت")
                            }.onFailure {
                                message = "تعذّر التصدير: ${it.message ?: "تأكد من وجود مساحة كافية"}" to true
                            }
                        }
                    }
                    GhostButton("حذف", enabled = !busy, color = Danger) { bulkDialog = "delete" }
                }
            }
            Spacer(Modifier.height(10.dp))
        }

        if (users.isNotEmpty()) {
            AppField(query, { query = it }, "بحث باسم المستخدم أو الباقة", Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            // مسحة واحدة تحسب كل العدادات — كانت سبع مسحات كاملة في كل إعادة
            // تركيب، وشريط التقدم أثناء الرفع يعيد التركيب آلاف المرات
            val counts = remember(users) {
                var unused = 0; var inUse = 0; var expired = 0
                var hotspot = 0; var um = 0; var local = 0
                users.forEach {
                    when (it.status) {
                        CardStatus.UNUSED -> unused++
                        CardStatus.IN_USE -> inUse++
                        CardStatus.EXPIRED, CardStatus.DISABLED -> expired++
                        else -> {}
                    }
                    when (it.source) {
                        CardSource.HOTSPOT -> hotspot++
                        CardSource.USER_MANAGER -> um++
                        CardSource.LOCAL -> local++
                    }
                }
                mapOf(
                    CardFilter.ALL to users.size,
                    CardFilter.UNUSED to unused,
                    CardFilter.IN_USE to inUse,
                    CardFilter.EXPIRED to expired,
                    CardFilter.HOTSPOT to hotspot,
                    CardFilter.USER_MANAGER to um,
                    CardFilter.LOCAL to local,
                )
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                CardFilter.entries.forEach { f ->
                    val count = counts[f] ?: 0
                    if (count > 0 || f == CardFilter.ALL) {
                        Chip("${f.labelAr} ($count)", filter == f) { filter = f }
                    }
                }
            }
            // الدفعات — الأسماء وأعدادها في مسحة واحدة بدل مسحة لكل دفعة
            val batches = remember(users) {
                users.asSequence()
                    .map { it.batchTag }
                    .filter { it.isNotBlank() }
                    .groupingBy { it }
                    .eachCount()
                    .toList()
                    .sortedByDescending { it.first }
            }
            if (batches.isNotEmpty()) {
                Spacer(Modifier.height(7.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("الدفعات:", fontSize = 11.sp, color = TextLow, modifier = Modifier.padding(top = 7.dp))
                    batches.take(12).forEach { (tag, n) ->
                        Chip("$tag ($n)", query == tag) { query = if (query == tag) "" else tag }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                // تأكيد إلزامي: كان يمحو كل الكروت بضغطة واحدة بلا رجعة
                TextButton(onClick = { confirmClear = true }) {
                    Icon(Icons.Filled.Delete, null, tint = Danger, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("إفراغ القائمة", color = Danger, fontSize = 12.sp)
                }
            }
        }

        } } // نهاية عنصر الرأس

        if (shown.isEmpty()) {
            item(key = "empty") {
                EmptyState(
                    Icons.Filled.CreditCard,
                    if (users.isEmpty()) "لا توجد كروت بعد" else "لا كروت بهذا التصنيف",
                    if (users.isEmpty()) "ولّد دفعة، أو استورد CSV، أو اجلب الكروت الموجودة من الراوتر" else "جرّب تصنيفاً آخر",
                )
            }
        } else {
            val visible = if (shown.size > showLimit) shown.subList(0, showLimit) else shown
            // مفاتيح ثابتة: بدونها كان كل دمج مزامنة يعيد تركيب كل الصفوف الظاهرة بالموضع
                items(visible.size, key = { i -> visible[i].source.name + "/" + visible[i].username }) { i ->
                    val u = visible[i]
                    val isSel = u.username in selected
                    GlassCard(
                        Modifier
                            .fillMaxWidth()
                            .combinedClickable(
                                onClick = {
                                    if (selecting) {
                                        selected = if (isSel) selected - u.username else selected + u.username
                                    }
                                },
                                onLongClick = { selected = selected + u.username },
                            ),
                        glow = if (isSel) Neon else Stroke,
                        padding = 11,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier
                                    .size(34.dp)
                                    .background(
                                        (if (isSel) Neon else statusColor(u.status)).copy(alpha = 0.15f),
                                        RoundedCornerShape(9.dp),
                                    )
                                    .border(1.dp, if (isSel) Neon else Stroke, RoundedCornerShape(9.dp)),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (isSel) {
                                    Icon(Icons.Filled.Check, null, tint = Neon, modifier = Modifier.size(18.dp))
                                } else {
                                    Text(
                                        u.serial.ifBlank { (i + 1).toString() },
                                        fontSize = 11.5.sp, color = statusColor(u.status), fontWeight = FontWeight.Bold,
                                    )
                                }
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(u.username, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                Text(
                                    buildList {
                                        if (settings.cardMode == CardMode.USER_PASS && u.password.isNotBlank())
                                            add("الرمز: ${u.password}")
                                        if (u.profile.isNotBlank()) add(u.profile)
                                        if (u.price.isNotBlank()) add("${u.price} ${settings.currency}")
                                        if (u.validity.isNotBlank()) add(u.validity)
                                    }.joinToString("  •  "),
                                    fontSize = 11.sp, color = TextMid,
                                )
                                if (u.uptime.isNotBlank() || u.bytesUsed > 0) {
                                    Text(
                                        buildList {
                                            if (u.uptime.isNotBlank()) add("استُخدم ${u.uptime}")
                                            if (u.bytesUsed > 0) add(formatBytes(u.bytesUsed))
                                        }.joinToString("  •  "),
                                        fontSize = 11.sp, color = TextLow,
                                    )
                                }
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                if (u.status != CardStatus.UNKNOWN) {
                                    Text(
                                        u.status.labelAr, fontSize = 11.sp, color = statusColor(u.status),
                                        modifier = Modifier
                                            .background(statusColor(u.status).copy(alpha = 0.12f), RoundedCornerShape(999.dp))
                                            .padding(horizontal = 8.dp, vertical = 2.dp),
                                    )
                                }
                                Text(u.source.labelAr, fontSize = 11.sp, color = TextLow, modifier = Modifier.padding(top = 3.dp))
                            }
                            IconButton(onClick = {
                                val tpl = Store.defaultTemplateOrFirst()
                                if (tpl != null) {
                                    // رسم الكرت وضغط PNG وكتابة الملف كانت على الخيط الرئيسي — تجمّد لحظي
                                    scope.launch {
                                        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                                            runCatching { com.binwaps.cardmanager.print.PdfExporter.shareCardImage(context, tpl, u, settings) }
                                        }.onFailure { message = "تعذّرت مشاركة الكرت: ${it.message ?: ""}" to true }
                                    }
                                } else {
                                    android.widget.Toast.makeText(context, "أنشئ قالباً أولاً", android.widget.Toast.LENGTH_SHORT).show()
                                }
                            }) {
                                Icon(Icons.Filled.Share, "مشاركة كصورة", tint = Lime, modifier = Modifier.size(17.dp))
                            }
                            IconButton(onClick = { editCard = u }) {
                                Icon(Icons.Filled.Edit, "تعديل", tint = Neon, modifier = Modifier.size(17.dp))
                            }
                            IconButton(onClick = { confirmRemove = u }) {
                                Icon(Icons.Filled.RemoveCircleOutline, "إزالة من القائمة", tint = TextLow, modifier = Modifier.size(17.dp))
                            }
                        }
                    }
                }
                if (shown.size > showLimit) {
                    item(key = "more") {
                        Text(
                            "عرض المزيد (${shown.size - showLimit} كرت متبقٍ)",
                            fontSize = 13.sp, color = Neon, fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Neon.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                                .clickable { showLimit += 500 }
                                .padding(vertical = 12.dp),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                    }
                }
        }
    }

    // تعديل كرت واحد — محلياً وعلى الراوتر معاً
    editCard?.let { card ->
        var pw by remember(card.username) { mutableStateOf(card.password) }
        var prof by remember(card.username) { mutableStateOf(card.profile) }
        var validity by remember(card.username) { mutableStateOf(card.validity.ifBlank { card.limitUptime }) }
        var price by remember(card.username) { mutableStateOf(card.price) }
        var note by remember(card.username) { mutableStateOf(card.comment) }
        val onRouter = card.routerId.isNotBlank()
        AlertDialog(
            onDismissRequest = { editCard = null },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("تعديل الكرت ${card.username}", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    AppField(pw, { pw = it }, "كلمة المرور", Modifier.fillMaxWidth(), code = true)
                    Spacer(Modifier.height(8.dp))
                    AppField(prof, { prof = it }, "الباقة", Modifier.fillMaxWidth(), code = true)
                    // اختيار مباشر من باقات الراوتر — بدل الكتابة اليدوية
                    val routerProfiles = Store.profiles.collectAsState().value
                    if (routerProfiles.isNotEmpty()) {
                        Spacer(Modifier.height(7.dp))
                        Row(
                            Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(7.dp),
                        ) {
                            routerProfiles.forEach { p ->
                                Chip(p.name, prof == p.name) { prof = p.name }
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    AppField(validity, { validity = it }, "الصلاحية (مثل 30d أو 12h)", Modifier.fillMaxWidth(), code = true)
                    Spacer(Modifier.height(8.dp))
                    AppField(price, { price = it }, "السعر", Modifier.fillMaxWidth(), numeric = true)
                    Spacer(Modifier.height(8.dp))
                    AppField(note, { note = it }, "ملاحظة", Modifier.fillMaxWidth())
                    Spacer(Modifier.height(9.dp))
                    Text(
                        if (onRouter) "سيُعدّل الكرت على الراوتر أيضاً"
                        else "هذا الكرت محلي — سيُحفظ التعديل في التطبيق فقط",
                        fontSize = 11.5.sp, color = TextLow,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val updated = card.copy(
                        password = pw, profile = prof, validity = validity,
                        price = price, comment = note,
                    )
                    Store.setUsers(users.map { if (it.username == card.username && it.source == card.source) updated else it })
                    editCard = null
                    if (onRouter) {
                        run("حفظ التعديل على الراوتر") {
                            MikrotikClient.updateCard(
                                Store.activeRouter(), card,
                                password = pw.ifBlank { null },
                                profile = prof.ifBlank { null },
                                comment = note.ifBlank { null },
                                limitUptime = validity.ifBlank { null },
                            ).map { "تم تعديل الكرت على الراوتر" }
                        }
                    }
                }) { Text("حفظ", color = Neon, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { editCard = null }) { Text("إلغاء", color = TextLow) } },
        )
    }

    // حوارات العمليات الجماعية
    bulkDialog?.let { kind ->
        val chosen = users.filter { it.username in selected }
        var value by remember(kind) { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { bulkDialog = null },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = {
                Text(
                    when (kind) {
                        "delete" -> "حذف ${chosen.size} كرت من الراوتر"
                        "profile" -> "تغيير باقة ${chosen.size} كرت"
                        else -> "تمديد صلاحية ${chosen.size} كرت"
                    },
                    fontWeight = FontWeight.Bold, fontSize = 16.sp,
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    when (kind) {
                        "delete" -> Text(
                            "سيُحذف ${chosen.size} كرت نهائياً من الراوتر، وتُفصل جلساتهم النشطة. لا يمكن التراجع.",
                            fontSize = 13.sp, color = Danger,
                        )
                        "profile" -> {
                            AppField(value, { value = it }, "اسم الباقة الجديدة", Modifier.fillMaxWidth(), code = true)
                            val profiles = Store.profiles.value
                            if (profiles.isNotEmpty()) {
                                Row(
                                    Modifier.horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) { profiles.forEach { p -> Chip(p.name, value == p.name) { value = p.name } } }
                            }
                        }
                        else -> {
                            Text("أضف مدة إلى الصلاحية الحالية لكل كرت", fontSize = 12.sp, color = TextMid)
                            Row(
                                Modifier.horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                listOf("1h" to "ساعة", "1d" to "يوم", "7d" to "أسبوع", "30d" to "شهر")
                                    .forEach { (v, label) -> Chip(label, value == v) { value = v } }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                // لا تنفيذ بقيمة فارغة: «تمديد» بلا مدة كان يعرض «تم تمديد» بلا أثر
                TextButton(enabled = kind == "delete" || value.isNotBlank(), onClick = {
                    val target = chosen
                    bulkDialog = null
                    progress = 0 to target.size
                    when (kind) {
                        "delete" -> run("جاري حذف ${target.size} كرت…") {
                            MikrotikClient.bulkDelete(Store.activeRouter(), target) { d, t -> progress = d to t }
                                .map {
                                    Store.setUsers(Store.users.value - target.toSet())
                                    selected = emptySet()
                                    "تم حذف ${it.ok} كرت" + if (it.failed > 0) " — فشل ${it.failed}" else ""
                                }
                        }
                        "profile" -> run("جاري تغيير الباقة…") {
                            MikrotikClient.bulkSetProfile(Store.activeRouter(), target, value) { d, t -> progress = d to t }
                                .map { "تم تغيير باقة ${it.ok} كرت إلى $value" }
                        }
                        else -> run("جاري تمديد الصلاحية…") {
                            val secs = MikrotikClient.parseUptime(value)
                            MikrotikClient.bulkExtendValidity(Store.activeRouter(), target, secs) { d, t -> progress = d to t }
                                .map { "تم تمديد ${it.ok} كرت" }
                        }
                    }
                }) {
                    Text(
                        if (kind == "delete") "حذف نهائي" else "تنفيذ",
                        color = if (kind == "delete") Danger else Neon,
                        fontWeight = FontWeight.Bold,
                    )
                }
            },
            dismissButton = { TextButton(onClick = { bulkDialog = null }) { Text("إلغاء", color = TextLow) } },
        )
    }

    if (confirmClear) {
        val localOnly = users.count { it.routerId.isBlank() && !it.uploaded }
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            containerColor = Panel,
            titleContentColor = TextHi,
            shape = RoundedCornerShape(20.dp),
            title = { Text("إفراغ قائمة الكروت؟", fontWeight = FontWeight.Bold, fontSize = 16.sp) },
            text = {
                Text(
                    "ستُحذف ${users.size} كرت من التطبيق" +
                        (if (localOnly > 0) "، منها $localOnly كرت لم يُرفع للراوتر بعد وسيضيع نهائياً" else "") +
                        ".\nكروت الراوتر لا تُحذف منه — يمكنك جلبها مجدداً.",
                    fontSize = 12.5.sp, color = TextMid,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    Store.clearUsers(); message = null; confirmClear = false
                }) { Text("إفراغ", color = Danger, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { confirmClear = false }) { Text("إلغاء", color = TextLow) }
            },
        )
    }

    if (showGenerate) {
        GenerateDialog(onDismiss = { showGenerate = false }) { generated ->
            Store.addUsers(generated)
            com.binwaps.cardmanager.data.EventLog.log("توليد", "تم توليد ${generated.size} كرت")
            showGenerate = false
            // الرفع التلقائي الفوري — التوليد وحده كان يترك الكروت محلية فلا تعمل على الشبكة
            val router = Store.activeRouter()
            if (router == null) {
                message = "تم توليد ${generated.size} كرت — لا يوجد راوتر محفوظ، سترفع بزر «رفع الجديد» بعد الاتصال" to false
            } else {
                progress = 0 to generated.size
                val target = settings.uploadTarget
                run("تم توليد ${generated.size} كرت — جاري رفعها تلقائياً إلى ${target.labelAr}…") {
                    val t0 = System.currentTimeMillis()
                    val created = java.util.Collections.synchronizedList(mutableListOf<String>())
                    var lastEmit = 0L
                    val onProgress: (Int, Int) -> Unit = { d, t ->
                        val now = System.currentTimeMillis()
                        if (d >= t || now - lastEmit > 120) { lastEmit = now; progress = d to t }
                    }
                    val onCreated: (UserEntry) -> Unit = { u ->
                        created.add(u.username)
                        if (created.size % 200 == 0) Store.markUploaded(created.toList())
                    }
                    val res = try {
                        if (target == UploadTarget.USER_MANAGER)
                            MikrotikClient.createUserManagerUsers(router, generated, onProgress = onProgress, onCreated = onCreated)
                        else
                            MikrotikClient.createHotspotUsers(router, generated, onProgress = onProgress, onCreated = onCreated)
                    } finally {
                        Store.markUploaded(created.toList())
                    }
                    res.onSuccess { com.binwaps.cardmanager.data.SyncEngine.syncNow() }
                    res.mapCatching { ok ->
                        val failed = generated.size - ok
                        if (failed > 0) {
                            throw Exception(
                                "تم توليد ${generated.size} كرت، ورُفع $ok فقط — فشل $failed. " +
                                    "الكروت محفوظة، اضغط «رفع الجديد» لإعادة محاولة الباقي"
                            )
                        }
                        "تم توليد ${generated.size} كرت و" +
                            uploadSpeedMessage(ok, target.labelAr, System.currentTimeMillis() - t0, auto = true)
                    }
                }
            }
        }
    }
}

/**
 * رسالة سرعة رفع مقاسة حقيقية — المعدّل بفاصلة عشرية على المللي ثانية
 * (لا قسمة صحيحة تعرض «0 كرت/ث»)، ويُخفى المعدّل حين لا يكون ذا معنى.
 */
private fun uploadSpeedMessage(count: Int, target: String, elapsedMs: Long, auto: Boolean = false): String {
    val secs = (elapsedMs / 1000.0).coerceAtLeast(0.1)
    val rate = count / secs
    val head = if (auto) "رفع $count تلقائياً إلى $target" else "تم رفع $count كرت إلى $target"
    val secsText = if (secs < 1) "أقل من ثانية" else "${secs.toInt()} ثانية"
    val rateText = if (count >= 5 && rate >= 1) " (%.0f كرت/ث)".format(rate) else ""
    return "$head خلال $secsText$rateText"
}

private fun statusColor(s: CardStatus): Color = when (s) {
    CardStatus.UNUSED -> Lime
    CardStatus.IN_USE -> Neon
    CardStatus.EXPIRED -> Danger
    CardStatus.DISABLED -> Warn
    CardStatus.UNKNOWN -> TextMid
}

@Composable
private fun Chip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        label,
        fontSize = 11.5.sp,
        color = if (selected) Neon else TextMid,
        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
        modifier = Modifier
            .background(if (selected) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
            .border(1.dp, if (selected) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun GenerateDialog(onDismiss: () -> Unit, onGenerate: (List<UserEntry>) -> Unit) {
    val profiles by Store.profiles.collectAsState()
    val settings by Store.settings.collectAsState()
    val dialogScope = rememberCoroutineScope()
    var loadingProfiles by remember { mutableStateOf(false) }
    var profilesError by remember { mutableStateOf<String?>(null) }
    // جلب الباقات تلقائياً فور فتح الحوار إن كانت فارغة — دون أي ضغطة
    androidx.compose.runtime.LaunchedEffect(Unit) {
        if (profiles.isEmpty() && Store.activeRouter() != null) {
            loadingProfiles = true
            MikrotikClient.fetchProfiles(Store.activeRouter())
                .onSuccess { Store.setProfiles(it) }
                .onFailure { profilesError = it.message }
            loadingProfiles = false
        }
    }
    var count by remember { mutableStateOf("50") }
    var prefix by remember { mutableStateOf("") }
    var length by remember { mutableStateOf("6") }
    var charset by remember { mutableStateOf(Charset.DIGITS) }
    var mode by remember { mutableStateOf(settings.cardMode) }
    var passwordLength by remember { mutableStateOf("4") }
    var profile by remember { mutableStateOf("") }
    var price by remember { mutableStateOf("") }
    var validity by remember { mutableStateOf("") }
    var everyNOn by remember { mutableStateOf(settings.freeRules.everyNEnabled) }
    var everyN by remember { mutableStateOf(settings.freeRules.everyN.toString()) }
    var randomOn by remember { mutableStateOf(settings.freeRules.randomEnabled) }
    var randomCount by remember { mutableStateOf(settings.freeRules.randomCount.toString()) }
    var freeProfile by remember { mutableStateOf(settings.freeRules.freeProfile) }
    var bonusOn by remember { mutableStateOf(false) }
    var bonusCount by remember { mutableStateOf("10") }
    var bonusLength by remember { mutableStateOf("8") }
    var bonusPrefix by remember { mutableStateOf("B") }
    var bonusSuffix by remember { mutableStateOf("") }
    var bonusProfile by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        titleContentColor = TextHi,
        textContentColor = TextMid,
        shape = RoundedCornerShape(20.dp),
        title = { Text("توليد دفعة كروت", fontWeight = FontWeight.Bold) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Text("نوع الكرت", fontSize = 12.sp, color = TextLow)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CardMode.entries.forEach { m -> Chip(m.labelAr, mode == m) { mode = m } }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppField(count, { count = it.filter { c -> c.isDigit() } }, "عدد الكروت", Modifier.weight(1f), numeric = true)
                    AppField(length, { length = it.filter { c -> c.isDigit() } }, "عدد الأرقام", Modifier.weight(1f), numeric = true)
                }
                if (mode == CardMode.USER_PASS) {
                    AppField(
                        passwordLength, { passwordLength = it.filter { c -> c.isDigit() } },
                        "عدد أرقام كلمة المرور", Modifier.fillMaxWidth(), numeric = true,
                    )
                }
                AppField(prefix, { prefix = it }, "بادئة الاسم (اختياري)", Modifier.fillMaxWidth(), code = true)

                Text("نوع الرموز", fontSize = 12.sp, color = TextLow)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Charset.entries.forEach { c -> Chip(c.labelAr, charset == c) { charset = c } }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppField(price, { price = it }, "السعر", Modifier.weight(1f))
                    AppField(validity, { validity = it }, "الصلاحية (30d)", Modifier.weight(1f), code = true)
                }
                AppField(profile, { profile = it }, "الباقة / البروفايل", Modifier.fillMaxWidth(), code = true)

                // كروت مجانية
                Text("كروت مجانية", fontSize = 12.sp, color = TextLow)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Chip(if (everyNOn) "كل رقم ✓" else "كل كرت رقم…", everyNOn) { everyNOn = !everyNOn }
                    if (everyNOn) {
                        Spacer(Modifier.width(6.dp))
                        Box(Modifier.width(90.dp)) {
                            AppField(everyN, { everyN = it.filter { c -> c.isDigit() } }, "كل كم كرت؟", Modifier.fillMaxWidth(), numeric = true)
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Chip(if (randomOn) "عشوائي ✓" else "عدد عشوائي", randomOn) { randomOn = !randomOn }
                    if (randomOn) {
                        Spacer(Modifier.width(6.dp))
                        Box(Modifier.width(90.dp)) {
                            AppField(randomCount, { randomCount = it.filter { c -> c.isDigit() } }, "العدد", Modifier.fillMaxWidth(), numeric = true)
                        }
                    }
                }
                if (everyNOn || randomOn) {
                    AppField(freeProfile, { freeProfile = it }, "باقة الكرت المجاني (اختياري)", Modifier.fillMaxWidth(), code = true)
                    val n = count.toIntOrNull() ?: 0
                    val preview = UserGenerator.freePositions(
                        n,
                        com.binwaps.cardmanager.model.FreeCardRules(
                            everyNEnabled = everyNOn, everyN = everyN.toIntOrNull() ?: 10,
                            randomEnabled = randomOn, randomCount = randomCount.toIntOrNull() ?: 0,
                        ),
                    )
                    Text(
                        "سيكون ${preview.size} كرت مجانياً من $n",
                        fontSize = 11.5.sp, color = Lime, fontWeight = FontWeight.Bold,
                    )
                }
                if (profiles.isNotEmpty()) {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        profiles.forEach { p ->
                            Chip(p.name, profile == p.name) {
                                profile = p.name
                                if (p.price.isNotBlank()) price = p.price
                            }
                        }
                    }
                } else {
                    // جلب الباقات من هنا مباشرة — بدل مغادرة الحوار والذهاب لقسم الباقات
                    GhostButton(
                        if (loadingProfiles) "جاري جلب الباقات…" else "جلب باقات الراوتر للاختيار منها",
                        Modifier.fillMaxWidth(),
                        enabled = !loadingProfiles,
                    ) {
                        loadingProfiles = true; profilesError = null
                        dialogScope.launch {
                            MikrotikClient.fetchProfiles(Store.activeRouter())
                                .onSuccess { Store.setProfiles(it) }
                                .onFailure { profilesError = it.message ?: "فشل جلب الباقات" }
                            loadingProfiles = false
                        }
                    }
                    profilesError?.let { Text(it, fontSize = 11.5.sp, color = Danger) }
                }

                // أكواد بونص — دفعة إضافية برموز أطول وباقة خاصة، للهدايا والمسابقات
                Text("أكواد بونص", fontSize = 12.sp, color = TextLow)
                Chip(if (bonusOn) "مع الدفعة ✓" else "إضافة أكواد بونص", bonusOn) { bonusOn = !bonusOn }
                if (bonusOn) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppField(bonusCount, { bonusCount = it.filter { c -> c.isDigit() } }, "العدد", Modifier.weight(1f), numeric = true)
                        AppField(bonusLength, { bonusLength = it.filter { c -> c.isDigit() } }, "طول الرمز", Modifier.weight(1f), numeric = true)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppField(bonusPrefix, { bonusPrefix = it }, "بادئة", Modifier.weight(1f), code = true)
                        AppField(bonusSuffix, { bonusSuffix = it }, "لاحقة", Modifier.weight(1f), code = true)
                    }
                    AppField(bonusProfile, { bonusProfile = it }, "باقة البونص (اختياري)", Modifier.fillMaxWidth(), code = true)
                    Text(
                        "تُضاف ${bonusCount.toIntOrNull() ?: 0} كرت بونص بعد الدفعة، بوسم منفصل حتى تميّزها في التقارير",
                        fontSize = 11.5.sp, color = Lime,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val rules = com.binwaps.cardmanager.model.FreeCardRules(
                    everyNEnabled = everyNOn,
                    everyN = everyN.toIntOrNull()?.coerceAtLeast(2) ?: 10,
                    randomEnabled = randomOn,
                    randomCount = randomCount.toIntOrNull()?.coerceAtLeast(0) ?: 0,
                    useDifferentProfile = freeProfile.isNotBlank(),
                    freeProfile = freeProfile,
                )
                Store.updateSettings(Store.settings.value.copy(cardMode = mode, freeRules = rules))
                val stamp = java.text.SimpleDateFormat("yyMMdd-HHmm", java.util.Locale.US)
                    .format(java.util.Date())
                // التوليد على خيط حسابي — ١٠٠ ألف كرت داخل ضغطة الزر كانت تجمّد الواجهة
                dialogScope.launch {
                val (main, bonus) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                val main = UserGenerator.generate(
                    count = count.toIntOrNull()?.coerceIn(1, 100000) ?: 50,
                    prefix = prefix,
                    length = length.toIntOrNull()?.coerceIn(3, 20) ?: 6,
                    charset = charset,
                    mode = mode,
                    passwordLength = passwordLength.toIntOrNull()?.coerceIn(3, 20) ?: 4,
                    profile = profile,
                    price = price,
                    validity = validity,
                    serialStart = Store.users.value.size + 1,
                    batchTag = "vc-" + stamp,
                    freeRules = rules,
                )
                val bonus = if (!bonusOn) emptyList() else UserGenerator.generate(
                    count = bonusCount.toIntOrNull()?.coerceIn(1, 50000) ?: 10,
                    prefix = bonusPrefix,
                    length = bonusLength.toIntOrNull()?.coerceIn(3, 20) ?: 8,
                    charset = charset,
                    mode = mode,
                    passwordLength = passwordLength.toIntOrNull()?.coerceIn(3, 20) ?: 4,
                    profile = bonusProfile.ifBlank { profile },
                    price = price,
                    validity = validity,
                    serialStart = Store.users.value.size + main.size + 1,
                    batchTag = "bonus-" + stamp,
                    suffix = bonusSuffix,
                )
                main to bonus
                }
                onGenerate(main + bonus)
                }
            }) { Text("توليد", color = Neon, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("إلغاء", color = TextLow) } },
    )
}
