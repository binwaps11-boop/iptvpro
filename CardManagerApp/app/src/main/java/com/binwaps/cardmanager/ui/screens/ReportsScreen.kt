package com.binwaps.cardmanager.ui.screens

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.CardSource
import com.binwaps.cardmanager.model.CardStatus
import com.binwaps.cardmanager.model.SaleKind
import com.binwaps.cardmanager.util.toMoneyOrNull
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.Warn
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import java.text.SimpleDateFormat
import java.util.Locale

private enum class ReportTab(val labelAr: String) {
    PROFILE("بحسب الباقة"),
    PRINT_DATE("بحسب تاريخ الطباعة"),
    BATCH("بحسب الدفعة"),
    DEVICE("بحسب الجهاز"),
    CUSTOMER("بحسب المشتري"),
}

/** صف واحد في التقرير — العنوان وأربعة أرقام */
private data class ReportRow(
    val title: String,
    val subtitle: String = "",
    val count: Int = 0,
    val money: Double = 0.0,
    val extraLabel: String = "",
    val extra: String = "",
    /** دين حقيقي متبقٍ — للتلوين */
    val debt: Double = 0.0,
)

/**
 * التقارير — نفس تقسيم سمارت كريتور (الباقة، تاريخ الطباعة، الجهاز، المشتري)
 * مع إضافة تقرير الدفعات، ويمكن مشاركة أي تقرير كملف CSV.
 */
@Composable
fun ReportsScreen() {
    val users by Store.users.collectAsState()
    val batches by Store.batches.collectAsState()
    val sales by Store.sales.collectAsState()
    val activeUsers by Store.activeUsers.collectAsState()
    val profiles by Store.profiles.collectAsState()
    val settings by Store.settings.collectAsState()
    val context = LocalContext.current

    var tab by remember { mutableStateOf(ReportTab.PROFILE) }
    val dayFmt = remember { SimpleDateFormat("yyyy/MM/dd", Locale.US) }
    val timeFmt = remember { SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.US) }
    val cur = settings.currency
    val connected by Store.connected.collectAsState()
    var loading by remember { mutableStateOf(false) }
    var loadNote by remember { mutableStateOf<String?>(null) }

    // التقرير يقرأ من الذاكرة (تملؤها المزامنة) فيفتح فوراً بلا انتظار. نجلب
    // من الراوتر **مرة واحدة فقط** إن لم تكن كروت الراوتر محمّلة بعد — بمفتاح
    // Unit لا connected (فلا يُعاد الجلب الثقيل عند تذبذب VPN)، وبأولوية
    // (foreground) فلا يصطف خلف المزامنة، وبمهلة فلا يعلق «جاري الجلب» أبداً.
    androidx.compose.runtime.LaunchedEffect(Unit) {
        val hasRouterCards = users.any { it.source != CardSource.LOCAL }
        if (!hasRouterCards && connected && Store.activeRouter() != null) {
            loading = true
            val res = kotlinx.coroutines.withTimeoutOrNull(40_000) {
                com.binwaps.cardmanager.mikrotik.MikrotikClient.fetchAllCards(
                    Store.activeRouter(), foreground = true,
                )
            }
            when {
                res == null -> loadNote = "الجلب بطيء عبر الشبكة — ستُحدَّث القائمة تلقائياً بالمزامنة"
                res.isSuccess -> res.getOrNull()?.let { Store.mergeRouterCards(it) }
                else -> loadNote = "تعذّر جلب كروت الراوتر — تحقق من الاتصال"
            }
            loading = false
        }
    }

    // الحساب ثقيل مع آلاف الكروت — يُحسب مرة عند تغيّر المدخلات لا كل إعادة تركيب
    val rows: List<ReportRow> = remember(tab, users, batches, sales, activeUsers, profiles, cur) { when (tab) {
        ReportTab.PROFILE -> users.groupBy { it.profile.ifBlank { "بدون باقة" } }
            .map { (profile, list) ->
                val p = profiles.firstOrNull { it.name == profile }
                val unit = p?.price?.toMoneyOrNull() ?: list.firstNotNullOfOrNull { it.price.toMoneyOrNull() } ?: 0.0
                val cost = p?.cost?.toMoneyOrNull() ?: 0.0
                // الإيراد من سعر كل كرت وقت توليده — لا من سعر الباقة الحالي بأثر رجعي
                val money = list.filter { !it.isFree }.sumOf { it.price.toMoneyOrNull() ?: unit }
                // التكلفة على كل الكروت — المجاني يكلفك وإن لم يُدرّ إيراداً
                val profit = money - cost * list.size
                ReportRow(
                    title = profile,
                    subtitle = "غير مستهلك ${list.count { it.status == CardStatus.UNUSED }}" +
                        "  •  قيد الاستخدام ${list.count { it.status == CardStatus.IN_USE }}" +
                        "  •  منتهي ${list.count { it.status == CardStatus.EXPIRED }}",
                    count = list.size,
                    money = money,
                    extraLabel = "الربح",
                    extra = fmt(profit) + " " + cur,
                )
            }.sortedByDescending { it.count }

        ReportTab.PRINT_DATE -> batches.groupBy { dayFmt.format(java.util.Date(it.createdAt)) }
            .map { (day, list) ->
                ReportRow(
                    title = day,
                    subtitle = "${list.size} دفعة  •  ${list.sumOf { it.printCount }} طباعة",
                    count = list.sumOf { it.users.size },
                    money = list.sumOf { it.total },
                    extraLabel = "الباقات",
                    extra = list.mapNotNull { it.profile.ifBlank { null } }.distinct().take(3).joinToString("، "),
                )
            }.sortedByDescending { it.title }

        ReportTab.BATCH -> batches.map { b ->
            ReportRow(
                title = b.templateName.ifBlank { "دفعة" } + "  #${b.id % 100000}",
                subtitle = timeFmt.format(java.util.Date(b.createdAt)) +
                    (if (b.profile.isNotBlank()) "  •  ${b.profile}" else ""),
                count = b.users.size,
                money = b.total,
                extraLabel = "مرات الطباعة",
                extra = b.printCount.toString(),
            )
        }

        // الجهاز = عنوان MAC — الأجهزة المتصلة الآن فقط
        ReportTab.DEVICE -> activeUsers.groupBy { it.macAddress.ifBlank { "غير معروف" } }
            .map { (mac, list) ->
                ReportRow(
                    title = mac,
                    subtitle = list.joinToString("، ") { it.username }.take(60),
                    count = list.size,
                    money = 0.0,
                    extraLabel = "الاستهلاك",
                    extra = human(list.sumOf { it.bytesIn + it.bytesOut }),
                )
            }.sortedByDescending { it.count }

        ReportTab.CUSTOMER -> {
            // دين كل زبون بعد سداداته — نفس صيغة شاشة المبيعات والرئيسية
            val debts = com.binwaps.cardmanager.util.Ledger.perCustomerDebt(sales)
            sales.filter { it.kind == SaleKind.SALE }
                .groupBy { it.customer.ifBlank { "زبون نقدي" } }
                .map { (customer, list) ->
                    val remaining = debts[customer] ?: 0.0
                    ReportRow(
                        title = customer,
                        subtitle = "${list.size} عملية  •  آخرها ${dayFmt.format(java.util.Date(list.maxOf { it.at }))}",
                        count = list.sumOf { it.quantity },
                        money = list.sumOf { it.total },
                        extraLabel = "دين متبقٍ",
                        extra = fmt(remaining) + " " + cur,
                        debt = remaining,
                    )
                }.sortedByDescending { it.money }
        }
    } }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                SectionHeader(
                    "التقارير",
                    when {
                        loading -> "جاري جلب كروت الراوتر…"
                        loadNote != null -> loadNote!!
                        else -> "${rows.size} سجل — يشمل كل كروت الراوتر"
                    },
                    Icons.Filled.Assessment,
                )
            }
            GhostButton("مشاركة", icon = Icons.Filled.Share) {
                shareCsv(context, tab.labelAr, rows, cur)
            }
        }
        Spacer(Modifier.height(12.dp))

        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            ReportTab.entries.forEach { t ->
                val on = tab == t
                Text(
                    t.labelAr,
                    fontSize = 11.5.sp,
                    color = if (on) Neon else TextMid,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier
                        .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                        .clickable { tab = t }
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                )
            }
        }
        if (tab == ReportTab.DEVICE) {
            Spacer(Modifier.height(8.dp))
            Text("يعرض الأجهزة المتصلة الآن فقط — ليس سجلاً تاريخياً", fontSize = 10.5.sp, color = TextLow)
        }
        Spacer(Modifier.height(12.dp))

        // الإجماليات
        GlassCard(Modifier.fillMaxWidth(), glow = Violet.copy(alpha = 0.28f), padding = 12) {
            Row {
                Total("عدد الكروت", rows.sumOf { it.count }.toString(), Neon, Modifier.weight(1f))
                Total("الإجمالي", fmt(rows.sumOf { it.money }) + " " + cur, Warn, Modifier.weight(1f))
                Total("السجلات", rows.size.toString(), Violet, Modifier.weight(1f))
            }
        }
        Spacer(Modifier.height(12.dp))

        if (rows.isEmpty()) {
            Column(
                Modifier.fillMaxWidth().padding(top = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Filled.Assessment, null, tint = TextLow, modifier = Modifier.size(46.dp))
                Spacer(Modifier.height(10.dp))
                Text(emptyHint(tab), fontSize = 12.5.sp, color = TextLow)
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                items(rows.size) { i ->
                    val r = rows[i]
                    GlassCard(Modifier.fillMaxWidth(), padding = 11) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(r.title, fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = TextHi)
                                if (r.subtitle.isNotBlank()) {
                                    Text(r.subtitle, fontSize = 10.5.sp, color = TextLow)
                                }
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text("${r.count} كرت", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Neon)
                                if (r.money != 0.0) {
                                    Text(fmt(r.money) + " " + cur, fontSize = 11.sp, color = Warn)
                                }
                                if (r.extra.isNotBlank()) {
                                    Text(
                                        "${r.extraLabel}: ${r.extra}",
                                        fontSize = 10.sp,
                                        color = if (r.debt > 0.005) Danger else TextMid,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun emptyHint(tab: ReportTab): String = when (tab) {
    ReportTab.PROFILE -> "لا توجد كروت بعد — أنشئ كروتاً أو اجلبها من الراوتر"
    ReportTab.PRINT_DATE, ReportTab.BATCH -> "لا توجد دفعات مطبوعة بعد"
    ReportTab.DEVICE -> "لا توجد أجهزة متصلة الآن — حدّث قسم المتصلين"
    ReportTab.CUSTOMER -> "لا توجد مبيعات مسجّلة — سجّل بيعاً من قسم المبيعات"
}

@Composable
private fun Total(label: String, value: String, color: androidx.compose.ui.graphics.Color, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 10.sp, color = TextLow)
    }
}

private fun fmt(v: Double): String =
    if (v == v.toLong().toDouble()) v.toLong().toString() else String.format(Locale.US, "%.2f", v)

private fun human(bytes: Long): String = when {
    bytes >= 1_073_741_824 -> String.format(Locale.US, "%.2f GB", bytes / 1_073_741_824.0)
    bytes >= 1_048_576 -> String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)
    bytes >= 1024 -> String.format(Locale.US, "%.0f KB", bytes / 1024.0)
    else -> "$bytes B"
}

/** يكتب التقرير كملف CSV بترميز UTF-8 مع BOM حتى تفتحه إكسل بالعربية صحيحة */
private fun shareCsv(
    context: android.content.Context,
    reportName: String,
    rows: List<ReportRow>,
    currency: String,
) {
    runCatching {
        val file = com.binwaps.cardmanager.util.CsvExporter.exportReport(
            context,
            listOf("البيان", "التفصيل", "عدد الكروت", "الإجمالي ($currency)", "إضافي"),
            rows.map {
                listOf(it.title, it.subtitle, it.count.toString(), fmt(it.money), "${it.extraLabel} ${it.extra}".trim())
            },
        )
        com.binwaps.cardmanager.util.CsvExporter.share(context, file, "تقرير $reportName")
    }
}
