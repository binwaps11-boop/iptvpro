package com.binwaps.cardmanager.util

import com.binwaps.cardmanager.model.SaleEntry
import com.binwaps.cardmanager.model.SaleKind
import java.util.Locale

/**
 * حسابات الدفتر المشتركة — صيغة واحدة للديون تستخدمها كل الشاشات
 * حتى لا يظهر رقم في الرئيسية يناقض رقم المبيعات.
 */
object Ledger {

    /**
     * دين كل زبون بعد خصم سداداته هو نفسه، ولا ينزل تحت الصفر.
     * السداد الزائد لزبون لا يلغي دين زبون آخر.
     */
    fun perCustomerDebt(sales: List<SaleEntry>): Map<String, Double> {
        val owed = sales.filter { it.kind == SaleKind.SALE && it.debt > 0 }
            .groupBy { it.customer.ifBlank { "زبون نقدي" } }
            .mapValues { (_, list) -> list.sumOf { it.debt } }
        val paid = sales.filter { it.kind == SaleKind.DEBT_PAID }
            .groupBy { it.customer.ifBlank { "زبون نقدي" } }
            .mapValues { (_, list) -> list.sumOf { it.total } }
        return owed.mapValues { (customer, debt) ->
            (debt - (paid[customer] ?: 0.0)).coerceAtLeast(0.0)
        }.filterValues { it > 0.005 }
    }

    /** إجمالي الديون = مجموع ديون الزبائن بعد السداد، كلٌّ على حدة */
    fun totalDebt(sales: List<SaleEntry>): Double = perCustomerDebt(sales).values.sum()

    /**
     * عرض مبلغ: فواصل آلاف، بلا كسور إن كان صحيحاً وإلا حتى رقمين عشريين —
     * أرقام إنجليزية دائماً (150,000 و 1,500.75 بدل 150000 و 1500.75)
     */
    fun money(v: Double): String {
        val nf = java.text.NumberFormat.getNumberInstance(Locale.US)
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        nf.isGroupingUsed = true
        return nf.format(v)
    }

    /** مبلغ مع وحدة العملة في نص واحد */
    fun moneyWithUnit(v: Double, currency: String): String = "${money(v)} $currency".trim()
}

/**
 * تحويل نص أدخله المستخدم إلى رقم مع قبول الأرقام العربية (٠١٢… و ۰۱۲…)
 * والفاصلة العشرية العربية '٫' — لوحات المفاتيح العربية تكتب بها.
 */
fun String.normalizeDigits(): String = buildString(length) {
    for (c in this@normalizeDigits) {
        append(
            when (c) {
                in '٠'..'٩' -> ('0' + (c - '٠'))   // ٠..٩
                in '۰'..'۹' -> ('0' + (c - '۰'))   // ۰..۹
                '٫', '،', '٬' -> '.'                          // فواصل عربية
                else -> c
            }
        )
    }
}

fun String.toMoneyOrNull(): Double? = normalizeDigits().trim().toDoubleOrNull()

fun String.toCountOrNull(): Int? = normalizeDigits().trim().toIntOrNull()
