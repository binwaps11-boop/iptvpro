package com.binwaps.cardmanager.ui.screens

import android.content.Intent
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.SaleEntry
import com.binwaps.cardmanager.model.SaleKind
import com.binwaps.cardmanager.util.Ledger
import com.binwaps.cardmanager.util.toCountOrNull
import com.binwaps.cardmanager.util.toMoneyOrNull
import com.binwaps.cardmanager.ui.components.AppField
import com.binwaps.cardmanager.ui.components.EmptyState
import com.binwaps.cardmanager.ui.components.GhostButton
import com.binwaps.cardmanager.ui.components.NeonButton
import com.binwaps.cardmanager.ui.components.SectionHeader
import com.binwaps.cardmanager.ui.theme.Danger
import com.binwaps.cardmanager.ui.theme.GlassCard
import com.binwaps.cardmanager.ui.theme.Lime
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.NeonGradient
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.ScreenGradient
import com.binwaps.cardmanager.ui.theme.Stroke
import com.binwaps.cardmanager.ui.theme.TextHi
import com.binwaps.cardmanager.ui.theme.TextLow
import com.binwaps.cardmanager.ui.theme.TextMid
import com.binwaps.cardmanager.ui.theme.Violet
import com.binwaps.cardmanager.ui.theme.Warn
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private enum class Period(val labelAr: String) { DAY("اليوم"), WEEK("الأسبوع"), MONTH("الشهر"), ALL("الكل") }

/** قسم المبيعات والصندوق — مستقل عن سجل الطباعة */
@Composable
fun SalesScreen() {
    val context = LocalContext.current
    val sales by Store.sales.collectAsState()
    val settings by Store.settings.collectAsState()
    val profiles by Store.profiles.collectAsState()
    var period by remember { mutableStateOf(Period.DAY) }
    var showAdd by remember { mutableStateOf(false) }
    var addKind by remember { mutableStateOf(SaleKind.SALE) }

    val fmt = remember { SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.US) }
    val cur = settings.currency

    // يُحسب في كل إعادة تركيب حتى لا تبقى "اليوم" على يوم أمس بعد منتصف الليل
    val from = run {
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, 0); c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
        when (period) {
            Period.DAY -> c.timeInMillis
            Period.WEEK -> c.timeInMillis - 6L * 86_400_000L
            Period.MONTH -> { c.set(Calendar.DAY_OF_MONTH, 1); c.timeInMillis }
            Period.ALL -> 0L
        }
    }

    val inPeriod = sales.filter { it.at >= from }
    val revenue = inPeriod.filter { it.kind == SaleKind.SALE }.sumOf { it.total }
    val collected = inPeriod.filter { it.kind == SaleKind.SALE }.sumOf { it.paid } +
        inPeriod.filter { it.kind == SaleKind.DEBT_PAID }.sumOf { it.total } +
        inPeriod.filter { it.kind == SaleKind.DEPOSIT }.sumOf { it.total }
    val expenses = inPeriod.filter { it.kind == SaleKind.EXPENSE }.sumOf { it.total }
    val cardsSold = inPeriod.filter { it.kind == SaleKind.SALE }.sumOf { it.quantity }
    // تكلفة ما بيع، من أسعار التكلفة المسجّلة على الباقات
    val costByProfile = profiles.associate { it.name to (it.cost.toDoubleOrNull() ?: 0.0) }
    val profitCost = inPeriod.filter { it.kind == SaleKind.SALE }
        .sumOf { (costByProfile[it.profile] ?: 0.0) * it.quantity }
    // إجمالي الديون المتراكمة (كل الفترات) — لكل زبون على حدة، والسداد الزائد
    // لزبونٍ لا يلغي دين زبونٍ آخر
    val debtByCustomer = Ledger.perCustomerDebt(sales)
    val totalDebt = debtByCustomer.values.sum()

    // الأكثر مبيعاً
    val byProfile = inPeriod.filter { it.kind == SaleKind.SALE && it.profile.isNotBlank() }
        .groupBy { it.profile }
        .map { (n, l) -> n to l.sumOf { it.quantity } }
        .sortedByDescending { it.second }
        .take(6)
    val maxSold = (byProfile.maxOfOrNull { it.second } ?: 1).coerceAtLeast(1)

    // الديون حسب الزبون — بعد خصم سداد كل زبون
    val debtors = debtByCustomer.toList().sortedByDescending { it.second }

    Column(
        Modifier
            .fillMaxSize()
            .background(ScreenGradient)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        SectionHeader("المبيعات والصندوق", "${sales.size} حركة مسجّلة", Icons.Filled.Payments)
        Spacer(Modifier.height(12.dp))

        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Period.entries.forEach { p ->
                val on = period == p
                Text(
                    p.labelAr, fontSize = 12.sp,
                    color = if (on) Neon else TextMid,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier
                        .background(if (on) Neon.copy(alpha = 0.12f) else Panel, RoundedCornerShape(999.dp))
                        .border(1.dp, if (on) Neon.copy(alpha = 0.5f) else Stroke, RoundedCornerShape(999.dp))
                        .clickable { period = p }
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                )
            }
        }

        Spacer(Modifier.height(13.dp))

        // الملخص المالي
        GlassCard(Modifier.fillMaxWidth(), glow = Lime.copy(alpha = 0.4f)) {
            Row {
                Column(Modifier.weight(1f)) {
                    Text("إجمالي المبيعات", fontSize = 11.sp, color = TextLow)
                    Text(
                        "${Ledger.money(revenue)} $cur",
                        fontSize = 23.sp, fontWeight = FontWeight.Bold, color = Lime,
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("عدد الكروت", fontSize = 11.sp, color = TextLow)
                    Text(cardsSold.toString(), fontSize = 23.sp, fontWeight = FontWeight.Bold, color = Neon)
                }
            }
            Spacer(Modifier.height(11.dp))
            MoneyRow("المحصّل نقداً", collected, cur, Lime)
            MoneyRow("المصروفات", expenses, cur, Danger)
            MoneyRow("الصافي", collected - expenses, cur, if (collected - expenses >= 0) Lime else Danger)
            if (profitCost > 0) {
                MoneyRow("تكلفة الكروت المباعة", profitCost, cur, TextMid)
                MoneyRow("الربح", revenue - profitCost, cur, if (revenue - profitCost >= 0) Lime else Danger)
            }
            if (totalDebt > 0) MoneyRow("الديون المستحقة", totalDebt, cur, Warn)
        }

        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f)) {
                NeonButton("تسجيل بيع", icon = Icons.Filled.Add) { addKind = SaleKind.SALE; showAdd = true }
            }
            GhostButton("مصروف", color = Danger) { addKind = SaleKind.EXPENSE; showAdd = true }
            GhostButton("سداد دين", color = Warn) { addKind = SaleKind.DEBT_PAID; showAdd = true }
            GhostButton("إيداع", color = Neon) { addKind = SaleKind.DEPOSIT; showAdd = true }
        }

        // الأكثر مبيعاً
        if (byProfile.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text("الأكثر مبيعاً", fontSize = 13.sp, color = TextLow)
            Spacer(Modifier.height(8.dp))
            GlassCard(Modifier.fillMaxWidth()) {
                byProfile.forEach { (name, qty) ->
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 4.dp)) {
                        Text(name, fontSize = 12.sp, color = TextHi, modifier = Modifier.width(85.dp))
                        Box(
                            Modifier.weight(1f).height(9.dp)
                                .background(Stroke.copy(alpha = 0.4f), RoundedCornerShape(999.dp))
                        ) {
                            Box(
                                Modifier
                                    .fillMaxWidth(qty.toFloat() / maxSold)
                                    .height(9.dp)
                                    .background(NeonGradient, RoundedCornerShape(999.dp))
                            )
                        }
                        Spacer(Modifier.width(8.dp))
                        Text("$qty", fontSize = 12.sp, color = Neon, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        // الديون
        if (debtors.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text("الديون على الزبائن", fontSize = 13.sp, color = TextLow)
            Spacer(Modifier.height(8.dp))
            debtors.forEach { (name, amount) ->
                GlassCard(Modifier.fillMaxWidth().padding(bottom = 6.dp), glow = Warn.copy(alpha = 0.3f), padding = 11) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(name, fontSize = 13.5.sp, color = TextHi, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Text("${Ledger.money(amount)} $cur", fontSize = 14.sp, color = Warn, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        // سجل الحركات
        Spacer(Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("سجل الحركات (${inPeriod.size})", fontSize = 13.sp, color = TextLow, modifier = Modifier.weight(1f))
            if (inPeriod.isNotEmpty()) {
                GhostButton("تصدير CSV") {
                    val f = com.binwaps.cardmanager.util.CsvExporter.exportSales(context, inPeriod, cur)
                    com.binwaps.cardmanager.util.CsvExporter.share(context, f, "تصدير المبيعات")
                }
                Spacer(Modifier.width(6.dp))
                GhostButton("مشاركة التقرير", icon = Icons.Filled.Share) {
                    val report = buildString {
                        appendLine("تقرير المبيعات — ${period.labelAr}")
                        appendLine("إجمالي المبيعات: ${Ledger.money(revenue)} $cur")
                        appendLine("المحصّل: ${Ledger.money(collected)} $cur")
                        appendLine("المصروفات: ${Ledger.money(expenses)} $cur")
                        appendLine("الصافي: ${Ledger.money(collected - expenses)} $cur")
                        appendLine("عدد الكروت المباعة: $cardsSold")
                        if (totalDebt > 0.005) appendLine("الديون المستحقة: ${Ledger.money(totalDebt)} $cur")
                        appendLine()
                        inPeriod.take(100).forEach {
                            appendLine("${fmt.format(Date(it.at))} — ${it.kind.labelAr} — ${it.customer} — ${Ledger.money(it.total)} $cur")
                        }
                    }
                    context.startActivity(
                        Intent.createChooser(
                            Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"; putExtra(Intent.EXTRA_TEXT, report)
                            },
                            "مشاركة تقرير المبيعات",
                        )
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))

        if (inPeriod.isEmpty()) {
            EmptyState(Icons.Filled.Payments, "لا توجد حركات", "سجّل أول عملية بيع بالضغط على «تسجيل بيع»")
        } else {
            inPeriod.take(200).forEach { s ->
                val color = when (s.kind) {
                    SaleKind.SALE -> Lime
                    SaleKind.EXPENSE -> Danger
                    SaleKind.DEPOSIT -> Neon
                    SaleKind.DEBT_PAID -> Warn
                }
                GlassCard(Modifier.fillMaxWidth().padding(bottom = 6.dp), padding = 11) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(7.dp).background(color, RoundedCornerShape(999.dp)))
                        Spacer(Modifier.width(9.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                buildString {
                                    append(s.kind.labelAr)
                                    if (s.customer.isNotBlank()) append(" — ${s.customer}")
                                },
                                fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = TextHi,
                            )
                            Text(
                                buildList {
                                    add(fmt.format(Date(s.at)))
                                    if (s.quantity > 0) add("${s.quantity} كرت")
                                    if (s.profile.isNotBlank()) add(s.profile)
                                    if (s.debt > 0) add("دين ${Ledger.money(s.debt)}")
                                    if (s.note.isNotBlank()) add(s.note)
                                }.joinToString("  •  "),
                                fontSize = 10.5.sp, color = TextLow,
                            )
                        }
                        Text("${Ledger.money(s.total)} $cur", fontSize = 14.sp, color = color, fontWeight = FontWeight.Bold)
                        IconButton(onClick = { Store.deleteSale(s.id) }) {
                            Icon(Icons.Filled.Delete, "حذف", tint = TextLow, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }

    if (showAdd) {
        AddSaleDialog(
            kind = addKind,
            profiles = profiles.map { it.name to it.price },
            currency = cur,
            onDismiss = { showAdd = false },
            onSave = { Store.addSale(it); showAdd = false },
        )
    }
}

@Composable
private fun MoneyRow(label: String, value: Double, currency: String, color: Color) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
        Text(label, fontSize = 12.5.sp, color = TextMid, modifier = Modifier.weight(1f))
        Text("${Ledger.money(value)} $currency", fontSize = 12.5.sp, color = color, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun AddSaleDialog(
    kind: SaleKind,
    profiles: List<Pair<String, String>>,
    currency: String,
    onDismiss: () -> Unit,
    onSave: (SaleEntry) -> Unit,
) {
    var customer by remember { mutableStateOf("") }
    var profile by remember { mutableStateOf("") }
    var quantity by remember { mutableStateOf("1") }
    var unitPrice by remember { mutableStateOf("") }
    var paid by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }

    val qty = (quantity.toCountOrNull() ?: 1).coerceAtLeast(1)
    val price = unitPrice.toMoneyOrNull() ?: 0.0
    val total = if (kind == SaleKind.SALE) qty * price else price

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Panel,
        titleContentColor = TextHi,
        shape = RoundedCornerShape(20.dp),
        title = { Text(kind.labelAr, fontWeight = FontWeight.Bold, fontSize = 16.sp) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                AppField(
                    customer, { customer = it },
                    if (kind == SaleKind.EXPENSE) "الجهة (اختياري)" else "اسم الزبون",
                    Modifier.fillMaxWidth(),
                )
                if (kind == SaleKind.SALE) {
                    AppField(profile, { profile = it }, "الباقة", Modifier.fillMaxWidth())
                    if (profiles.isNotEmpty()) {
                        Row(
                            Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            profiles.forEach { (n, p) ->
                                Text(
                                    n, fontSize = 11.sp, color = Lime,
                                    modifier = Modifier
                                        .background(Lime.copy(alpha = 0.10f), RoundedCornerShape(999.dp))
                                        .clickable { profile = n; if (p.isNotBlank()) unitPrice = p }
                                        .padding(horizontal = 10.dp, vertical = 5.dp),
                                )
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppField(quantity, { quantity = it.filter { c -> c.isDigit() } }, "عدد الكروت", Modifier.weight(1f), numeric = true)
                        AppField(unitPrice, { unitPrice = it }, "سعر الكرت", Modifier.weight(1f), numeric = true)
                    }
                    Text("الإجمالي: ${Ledger.money(total)} $currency", fontSize = 13.sp, color = Neon, fontWeight = FontWeight.Bold)
                    AppField(paid, { paid = it }, "المدفوع (اتركه فارغاً = دفع كامل)", Modifier.fillMaxWidth(), numeric = true)
                } else {
                    AppField(unitPrice, { unitPrice = it }, "المبلغ", Modifier.fillMaxWidth(), numeric = true)
                }
                AppField(note, { note = it }, "ملاحظة", Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onSave(
                    SaleEntry(
                        id = Store.newId(),
                        at = System.currentTimeMillis(),
                        kind = kind,
                        customer = customer,
                        profile = profile,
                        quantity = if (kind == SaleKind.SALE) qty else 0,
                        unitPrice = price,
                        paid = if (kind == SaleKind.SALE) (paid.toMoneyOrNull() ?: total) else price,
                        note = note,
                    )
                )
            }) { Text("حفظ", color = Neon, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("إلغاء", color = TextLow) } },
    )
}
