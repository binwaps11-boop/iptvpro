package com.binwaps.cardmanager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Print
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.ProductionEngine
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.*
import com.binwaps.cardmanager.performance.CodePool
import com.binwaps.cardmanager.print.PdfExporter
import com.binwaps.cardmanager.print.PrintEngine
import com.binwaps.cardmanager.ui.components.*
import com.binwaps.cardmanager.ui.theme.*
import com.binwaps.cardmanager.util.toCountOrNull
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/** A batch workspace: configure once, then inspect each independent production stage. */
@Composable
fun ExpressScreen() {
    val context = LocalContext.current
    val templates by Store.templates.collectAsState()
    val profiles by Store.profiles.collectAsState()
    val settings by Store.settings.collectAsState()
    val routers by Store.routers.collectAsState()
    val users by Store.users.collectAsState()
    val production by ProductionEngine.state.collectAsState()
    val printing by PrintEngine.state.collectAsState()
    val pdfMetrics by PrintEngine.pdfMetrics.collectAsState()
    LaunchedEffect(Unit) { withContext(Dispatchers.IO) { PrintEngine.restoreIfAny() } }

    var templateId by rememberSaveable { mutableStateOf(Store.defaultTemplateOrFirst()?.id) }
    val template = templates.firstOrNull { it.id == templateId } ?: Store.defaultTemplateOrFirst()
    var countText by rememberSaveable { mutableStateOf("1000") }
    var lengthText by rememberSaveable { mutableStateOf("8") }
    var mode by rememberSaveable { mutableStateOf(settings.cardMode) }
    var target by rememberSaveable { mutableStateOf(settings.uploadTarget) }
    var profile by rememberSaveable { mutableStateOf("") }
    var price by rememberSaveable { mutableStateOf("") }
    var validity by rememberSaveable { mutableStateOf("") }
    var uploadEnabled by rememberSaveable { mutableStateOf(routers.isNotEmpty()) }
    var splitLargePdf by rememberSaveable { mutableStateOf(settings.splitLargePdf) }
    var previewOpen by remember { mutableStateOf(false) }
    var issue by remember { mutableStateOf<String?>(null) }
    val busy = production.busy || printing is PrintEngine.State.Running
    val pendingPrint = printing is PrintEngine.State.Failed || printing is PrintEngine.State.Restorable
    val count = countText.toCountOrNull() ?: 0
    val displayCount = if (busy && production.count > 0) production.count else count
    val length = lengthText.toCountOrNull() ?: 0
    val countError = if (count !in 1..100000) "أدخل عددًا بين 1 و100,000" else null
    val lengthError = if (length !in 3..20) "اختر طولًا بين 3 و20 خانة" else null
    val effectiveLength = maxOf(length, CodePool.minimumLength(count.coerceIn(0, 100000), 10, users.size))
    val source = if (target == UploadTarget.HOTSPOT) CardSource.HOTSPOT else CardSource.USER_MANAGER
    val targetProfiles = remember(profiles, source) { profiles.filter { it.source == source } }
    val quickSettings = settings.copy(cardMode = mode, uploadTarget = target, printFrom = 0, printTo = 0, startCell = 1, copies = 1, splitLargePdf = splitLargePdf)
    val layout = remember(template, settings.layout, displayCount) {
        template?.let { PdfExporter.computeLayout(it, settings, displayCount.coerceIn(0, 100000)) }
    }

    LaunchedEffect(targetProfiles) {
        if (profile.isBlank()) targetProfiles.firstOrNull()?.let { profile = it.name; price = it.price }
    }

    Column(
        Modifier.fillMaxSize().background(ScreenGradient).verticalScroll(rememberScrollState()).padding(Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("استوديو الكروت", fontSize = 27.sp, fontWeight = FontWeight.Bold, color = TextHi)
                Text("إنشاء. رفع. تجهيز للطباعة.", fontSize = 13.sp, color = TextMid)
            }
            Icon(Icons.Filled.CreditCard, null, tint = Neon, modifier = Modifier.size(32.dp))
        }

        GlassCard(Modifier.fillMaxWidth(), glow = Stroke, padding = 20) {
            Text(if (busy) "دفعتك قيد المعالجة" else "الدفعة التالية", color = TextMid, fontSize = 13.sp)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                Text(number(displayCount.coerceAtLeast(0)), color = TextHi, fontSize = 42.sp, lineHeight = 58.sp, fontWeight = FontWeight.Bold)
                Text("كرت", color = Neon, fontSize = 17.sp, modifier = Modifier.padding(bottom = Space.sm))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                SummaryItem("صفحة PDF", number(layout?.pages ?: 0), Modifier.weight(1f))
                SummaryItem("كرت / صفحة", number(layout?.perPage ?: 0), Modifier.weight(1f))
                SummaryItem("خانات الرمز", effectiveLength.toString(), Modifier.weight(1f))
            }
            Spacer(Modifier.height(Space.md))
            Text("${template?.name ?: "اختر قالبًا"} • ${if (uploadEnabled && routers.isNotEmpty()) target.labelAr else "PDF فقط"}",
                color = TextMid, fontSize = 12.sp)
        }

        if (production.batchId.isNotBlank()) {
            Text("متابعة الدفعة", color = TextHi, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            StageCard("01", "توليد الرموز", production.generation)
            StageCard("02", "رفع الكروت", production.upload)
            if (production.generation.status == ProductionEngine.Status.RUNNING) {
                GhostButton("إلغاء التوليد", Modifier.fillMaxWidth(), color = Warn) { ProductionEngine.cancelGeneration() }
            }
            if (production.upload.status == ProductionEngine.Status.RUNNING) {
                GhostButton("إيقاف الرفع", Modifier.fillMaxWidth(), color = Warn) { ProductionEngine.stopUpload() }
            }
            if (production.upload.status == ProductionEngine.Status.PAUSED) {
                NeonButton("استكمال الكروت المتبقية", Modifier.fillMaxWidth()) { ProductionEngine.retryUpload() }
            }
        }
        when (val state = printing) {
            is PrintEngine.State.Running -> {
                val isPdf = state.kind == PrintEngine.Kind.PDF
                val metrics = if (isPdf) pdfMetrics else null
                StageCard("03", if (isPdf) "تجهيز PDF" else "الطباعة الحرارية", ProductionEngine.Stage(
                    ProductionEngine.Status.RUNNING,
                    metrics?.done ?: if (isPdf) 0 else state.done,
                    metrics?.total ?: if (isPdf) displayCount else state.total,
                    metrics?.perSecond ?: 0.0, metrics?.elapsedSeconds ?: 0.0,
                    metrics?.remainingSeconds ?: -1, state.label,
                ))
                GhostButton(if (isPdf) "إيقاف وحفظ التقدم" else "إيقاف الطباعة", Modifier.fillMaxWidth(), color = Warn) { PrintEngine.cancel() }
            }
            is PrintEngine.State.Done -> GlassCard(Modifier.fillMaxWidth(), glow = Lime.copy(alpha = AlphaBorderSoft), padding = 18) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Icon(Icons.Filled.CheckCircle, null, tint = Lime)
                    Text(if (state.kind == PrintEngine.Kind.PDF) "ملفاتك جاهزة" else "اكتمل الإرسال للطابعة", color = TextHi, fontSize = 19.sp, fontWeight = FontWeight.Bold)
                }
                Text("${number(state.total)} كرت • ${pdfMetrics?.secondsLabel() ?: ""}", fontSize = 13.sp, color = TextMid)
                Spacer(Modifier.height(Space.md))
                PdfDeliveryActions(state.files)
                GhostButton("إنهاء المتابعة", Modifier.fillMaxWidth()) { PrintEngine.acknowledge() }
            }
            is PrintEngine.State.Failed -> GlassCard(Modifier.fillMaxWidth(), glow = Warn.copy(alpha = AlphaBorderSoft)) {
                Text(state.error, color = TextMid, fontSize = 13.sp)
                Spacer(Modifier.height(Space.sm))
                if (state.kind == PrintEngine.Kind.PDF) {
                    NeonButton("استكمال الأجزاء المتبقية", Modifier.fillMaxWidth()) { PrintEngine.resume(context) }
                } else Text("افتح شاشة الطباعة لاستكمال المهمة الحرارية", color = TextMid, fontSize = 13.sp)
                DiscardPrintJobButton(Modifier.fillMaxWidth())
            }
            is PrintEngine.State.Restorable -> GlassCard(Modifier.fillMaxWidth(), glow = Warn.copy(alpha = AlphaBorderSoft)) {
                Text("لديك مهمة طباعة محفوظة لم تكتمل", color = TextHi, fontSize = 14.sp)
                if (state.kind == PrintEngine.Kind.PDF) {
                    NeonButton("استعادة المهمة", Modifier.fillMaxWidth()) { PrintEngine.resumeRestored(context) }
                } else Text("افتح شاشة الطباعة لاختيار الطابعة الحرارية واستكمال المهمة", color = TextMid, fontSize = 13.sp)
                DiscardPrintJobButton(Modifier.fillMaxWidth())
            }
            else -> Unit
        }

        GlassCard(Modifier.fillMaxWidth(), glow = Stroke, padding = 18) {
            FormHeading("01", "حجم الدفعة", "اختر الكمية وشكل رمز الدخول")
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                listOf(1000, 10000, 50000, 100000).forEach { preset ->
                    AppChip(number(preset), count == preset) { if (!busy) countText = preset.toString() }
                }
            }
            Spacer(Modifier.height(Space.md))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                AppField(countText, { if (!busy) countText = it }, "عدد الكروت", Modifier.weight(1f), numeric = true, error = countError)
                AppField(lengthText, { if (!busy) lengthText = it }, "خانات الرمز", Modifier.weight(1f), numeric = true, error = lengthError)
            }
            if (lengthError == null && effectiveLength > length) Text(
                "سيُستخدم $effectiveLength خانات حتى تكفي الرموز الفريدة لهذه الدفعة.", color = TextMid, fontSize = 12.sp)
            Spacer(Modifier.height(Space.sm))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                CardMode.entries.forEach { m -> AppChip(m.labelAr, mode == m) { if (!busy) mode = m } }
            }
        }

        GlassCard(Modifier.fillMaxWidth(), glow = Stroke, padding = 18) {
            FormHeading("02", "التصميم والطباعة", "اختر القالب وطريقة إخراج الدفعة")
            if (templates.isEmpty()) Text("أضف قالبًا من قسم القوالب لبدء العمل", color = TextMid, fontSize = 13.sp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                templates.forEach { t -> AppChip(t.name, template?.id == t.id) { if (!busy) templateId = t.id } }
            }
            Spacer(Modifier.height(Space.sm))
            PdfOutputOptions(splitLargePdf, !busy) { splitLargePdf = it }
            Text("الملفات المتوقعة: ${com.binwaps.cardmanager.performance.PdfParts(layout?.pages ?: 0, 1, splitLargePdf).size}", color = TextMid, fontSize = 12.sp)
            template?.let { t ->
                Spacer(Modifier.height(Space.sm))
                GhostButton(if (previewOpen) "إخفاء معاينة الكرت" else "معاينة الكرت", Modifier.fillMaxWidth()) { previewOpen = !previewOpen }
                if (previewOpen) CardPreview(t, modifier = Modifier.fillMaxWidth())
            }
        }

        GlassCard(Modifier.fillMaxWidth(), glow = Stroke, padding = 18) {
            FormHeading("03", "الشبكة والباقة", "يُحفظ اختيارك مع الدفعة عند بدء العمل")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                AppChip("PDF فقط", !uploadEnabled) { if (!busy) uploadEnabled = false }
                UploadTarget.entries.forEach { tg ->
                    AppChip(tg.labelAr, uploadEnabled && target == tg) { if (!busy) { uploadEnabled = true; target = tg; profile = "" } }
                }
            }
            Spacer(Modifier.height(Space.md))
            if (uploadEnabled) Text(Store.activeRouter()?.let { "الراوتر: ${it.name}" } ?: "احفظ راوترًا في الإعدادات لتفعيل الرفع", color = TextMid, fontSize = 13.sp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                targetProfiles.forEach { p ->
                    AppChip(p.name, profile == p.name) {
                        if (!busy) { profile = p.name; price = p.price; validity = p.sessionTimeout }
                    }
                }
            }
            Spacer(Modifier.height(Space.sm))
            AppField(profile, { if (!busy) profile = it }, "اسم الباقة", Modifier.fillMaxWidth(), code = true)
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                AppField(price, { if (!busy) price = it }, "السعر", Modifier.weight(1f), numeric = true)
                AppField(validity, { if (!busy) validity = it }, "الصلاحية", Modifier.weight(1f), code = true)
            }
        }
        if (pendingPrint) MessageBanner("استكمل مهمة الطباعة المحفوظة أو ألغِها قبل بدء دفعة جديدة.", BannerKind.INFO)
        issue?.let { MessageBanner(it, BannerKind.ERROR) }
        NeonButton(if (busy) "الدفعة قيد المعالجة" else "بدء الدفعة • ${number(count.coerceAtLeast(0))} كرت",
            Modifier.fillMaxWidth(), Icons.Filled.Bolt,
            enabled = !busy && !pendingPrint && template != null && countError == null && lengthError == null && (!uploadEnabled || routers.isNotEmpty()),
        ) {
            val selectedTemplate = template ?: return@NeonButton
            issue = null
            val errors = PrintEngine.preflight(selectedTemplate, listOf(UserEntry(username = "preview")), quickSettings, thermal = false)
            if (errors.isNotEmpty()) issue = errors.joinToString("\n")
            else {
                Store.updateSettings(quickSettings)
                ProductionEngine.start(context, selectedTemplate, quickSettings, count, length, profile, price, validity, uploadEnabled)
            }
        }
        Text("تستمر الدفعة عند التنقل داخل التطبيق. السرعة والوقت المتبقي يُحسبان من التقدم الفعلي.", color = TextMid, fontSize = 12.sp)
        Spacer(Modifier.height(Space.lg))
    }
}

private fun number(value: Int): String = String.format(Locale.US, "%,d", value)
private fun duration(seconds: Long): String = if (seconds < 0) "يُحسب بعد بدء التقدم" else if (seconds < 60) "$seconds ث" else "${seconds / 60} د ${seconds % 60} ث"
private fun com.binwaps.cardmanager.performance.ThroughputMeter.Snapshot.secondsLabel() = duration(elapsedSeconds.toLong())

@Composable
private fun FormHeading(step: String, title: String, detail: String) {
    Text("$step  /  $title", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = TextHi)
    Text(detail, fontSize = 12.sp, color = TextMid)
    Spacer(Modifier.height(Space.md))
}

@Composable
private fun SummaryItem(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(value, color = TextHi, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Text(label, color = TextMid, fontSize = 11.sp)
    }
}

@Composable
private fun StageCard(step: String, title: String, stage: ProductionEngine.Stage) {
    val accent = when (stage.status) {
        ProductionEngine.Status.DONE -> Lime
        ProductionEngine.Status.PAUSED -> Warn
        ProductionEngine.Status.RUNNING -> Neon
        else -> TextLow
    }
    GlassCard(Modifier.fillMaxWidth(), glow = Stroke, padding = 18) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("$step  /  $title", color = TextHi, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(when (stage.status) {
                ProductionEngine.Status.DONE -> "مكتمل"
                ProductionEngine.Status.RUNNING -> "جارٍ"
                ProductionEngine.Status.PAUSED -> "متوقف"
                ProductionEngine.Status.SKIPPED -> "غير مطلوب"
                else -> "بانتظار التوليد"
            }, color = accent, fontSize = 12.sp)
        }
        if (stage.total > 0) {
            Spacer(Modifier.height(Space.sm))
            Text("${number(stage.done)} / ${number(stage.total)} كرت", color = TextHi, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            NeonProgress(stage.done.toFloat() / stage.total.coerceAtLeast(1))
            Spacer(Modifier.height(Space.sm))
            Text("${String.format(Locale.US, "%.1f", stage.rate)} كرت/ث • ${duration(stage.seconds.toLong())}", color = TextMid, fontSize = 12.sp)
            if (stage.status == ProductionEngine.Status.RUNNING && stage.remaining >= 0)
                Text("المتبقي تقديريًا: ${duration(stage.remaining)}", color = TextMid, fontSize = 12.sp)
        }
        if (stage.detail.isNotBlank()) Text(stage.detail, color = TextMid, fontSize = 12.sp)
    }
}
