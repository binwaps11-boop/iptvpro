package com.binwaps.cardmanager.util

import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.model.CardSource

/**
 * دوال مساعدة نقية للكروت — بلا حالة ولا اتصال، فتُختبر وحدها بسهولة.
 */
object CardUtils {

    /**
     * هل رصيد باقة تحت عتبة التنبيه؟ العتبة ≤ 0 تعني «معطّل» فلا تنبيه.
     * تُستعمل لإظهار تحذير نفاد الكروت في اللوحة/الباقات.
     */
    fun isLowStock(unusedCount: Int, threshold: Int): Boolean =
        threshold > 0 && unusedCount in 0..threshold

    /**
     * أسماء الكروت المكرّرة بين قائمة واردة وقائمة قائمة (استيراد/توليد).
     * المقارنة على اسم المستخدم فقط (هو المفتاح على الراوتر)، بلا حساسية لحالة
     * الأحرف والمسافات الطرفية. تمنع رفع كرت باسمٍ موجود مسبقاً فيُرفض أو يُكرّر.
     */
    fun duplicateUsernames(incoming: List<UserEntry>, existing: List<UserEntry>): Set<String> {
        val have = existing.mapTo(HashSet()) { it.username.trim().lowercase() }
        return incoming.mapNotNull { u ->
            u.username.trim().lowercase().takeIf { it.isNotBlank() && it in have }
        }.toSet()
    }

    /**
     * يزيل من الواردة كل ما اسمه موجود في القائمة القائمة أو مكرّر داخلها،
     * محافظاً على أول ظهور. يعيد القائمة المنقّاة.
     */
    fun dropDuplicates(incoming: List<UserEntry>, existing: List<UserEntry>): List<UserEntry> {
        val seen = existing.mapTo(HashSet()) { it.username.trim().lowercase() }
        val out = ArrayList<UserEntry>(incoming.size)
        for (u in incoming) {
            val key = u.username.trim().lowercase()
            if (key.isNotBlank() && seen.add(key)) out.add(u)
        }
        return out
    }
    /** A user without a completed upload must retain its intended profile and credentials. */
    fun mergeRouterCards(
        current: List<UserEntry>,
        fetched: List<UserEntry>,
        sources: Set<CardSource>,
    ): List<UserEntry> {
        val pending = current.filter { it.source == CardSource.LOCAL && !it.uploaded && it.routerId.isBlank() }
        val pendingNames = pending.mapTo(HashSet()) { it.username }
        val fetchedNames = fetched.mapTo(HashSet()) { it.username }
        val prices = current.associate { it.username to it.price }
        val remote = fetched.filter { it.username !in pendingNames }.map { f ->
            val price = prices[f.username].orEmpty()
            if (f.price.isBlank() && price.isNotBlank()) f.copy(price = price) else f
        }
        val kept = current.filter {
            (it.source == CardSource.LOCAL && it.username !in pendingNames && it.username !in fetchedNames) ||
                (it.source != CardSource.LOCAL && it.source !in sources)
        }
        return remote + pending + kept
    }

}
