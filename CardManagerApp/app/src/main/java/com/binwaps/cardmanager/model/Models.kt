package com.binwaps.cardmanager.model

import kotlinx.serialization.Serializable

/** نوع الكرت — يحدد ما يُطبع عليه وكيف يُولَّد */
@Serializable
enum class CardMode(val labelAr: String, val hintAr: String) {
    USERNAME_ONLY("اسم مستخدم فقط", "الدخول باسم المستخدم بدون كلمة مرور"),
    USER_PASS("اسم مستخدم وكلمة مرور", "رمزان مختلفان على الكرت"),
    SAME("متشابه (رمز واحد)", "اسم المستخدم = كلمة المرور"),
}

/** حالة الكرت على الراوتر */
@Serializable
enum class CardStatus(val labelAr: String) {
    UNUSED("غير مستهلك"),
    IN_USE("قيد الاستخدام"),
    EXPIRED("منتهي"),
    DISABLED("معطّل"),
    UNKNOWN("—"),
}

/** مصدر الكرت */
@Serializable
enum class CardSource(val labelAr: String) {
    LOCAL("محلي"),
    HOTSPOT("هوتسبوت"),
    USER_MANAGER("يوزر منجر"),
}

/** مستخدم واحد (من اليوزر منجر أو الهوتسبوت أو مولّد محلياً) */
@Serializable
data class UserEntry(
    val username: String,
    val password: String = "",
    val profile: String = "",
    val price: String = "",
    val validity: String = "",
    val serial: String = "",
    val comment: String = "",
    /** معرّف السجل على الراوتر — يُستخدم للحذف والتعديل */
    val routerId: String = "",
    val source: CardSource = CardSource.LOCAL,
    val status: CardStatus = CardStatus.UNKNOWN,
    /** الوقت المستهلك كما يعرضه الراوتر */
    val uptime: String = "",
    val bytesUsed: Long = 0,
    val disabled: Boolean = false,
)

/** جلسة — نشطة الآن أو من السجل */
@Serializable
data class SessionEntry(
    val id: String = "",
    val username: String = "",
    val address: String = "",
    val macAddress: String = "",
    val uptime: String = "",
    val bytesIn: Long = 0,
    val bytesOut: Long = 0,
    val startedAt: String = "",
    val endedAt: String = "",
    val active: Boolean = true,
)

/** أنواع الحقول التي يمكن وضعها على الكرت */
@Serializable
enum class FieldType(val labelAr: String) {
    USERNAME("اسم المستخدم"),
    PASSWORD("كلمة المرور"),
    PRICE("السعر"),
    VALIDITY("الصلاحية"),
    PROFILE("الباقة"),
    SERIAL("الرقم التسلسلي"),
    QR_CODE("رمز QR"),
    CUSTOM_TEXT("نص ثابت"),
}

@Serializable
enum class QrContent(val labelAr: String) {
    LOGIN_URL("رابط دخول تلقائي"),
    WIFI("اتصال واي فاي"),
    USER_PASS("اسم المستخدم وكلمة المرور"),
}

/** حقل واحد على قالب الكرت. الإحداثيات والقياسات كنِسب من أبعاد الكرت (0..1) */
@Serializable
data class CardField(
    val id: Long,
    val type: FieldType,
    val xFrac: Float = 0.5f,
    val yFrac: Float = 0.5f,
    /** حجم الخط كنسبة من ارتفاع الكرت */
    val sizeFrac: Float = 0.10f,
    val color: Long = 0xFF000000,
    val bold: Boolean = true,
    val customText: String = "",
    /** يظهر قبل القيمة، مثال: "المستخدم: " */
    val prefix: String = "",
    val visible: Boolean = true,
)

/** قالب كرت */
@Serializable
data class CardTemplate(
    val id: Long,
    val name: String,
    val widthMm: Float = 85.6f,
    val heightMm: Float = 54f,
    /** مسار صورة الخلفية داخل مجلد التطبيق، أو فارغ */
    val backgroundPath: String = "",
    val backgroundColor: Long = 0xFFFFFFFF,
    val borderColor: Long = 0xFF0B5E4F,
    val borderWidthMm: Float = 0.6f,
    val cornerRadiusMm: Float = 2.5f,
    val fields: List<CardField> = emptyList(),
    val qrContent: QrContent = QrContent.LOGIN_URL,
)

@Serializable
enum class PaperType(val labelAr: String) {
    A4("ورق A4 (طابعة عادية / PDF)"),
    THERMAL_58("طابعة حرارية 58مم"),
    THERMAL_80("طابعة حرارية 80مم"),
}

/** مقاس الورق */
@Serializable
enum class PaperSize(val labelAr: String, val widthMm: Float, val heightMm: Float) {
    A4("A4 — 210×297", 210f, 297f),
    A5("A5 — 148×210", 148f, 210f),
    A3("A3 — 297×420", 297f, 420f),
    LETTER("Letter — 216×279", 215.9f, 279.4f),
}

@Serializable
enum class PageOrientation(val labelAr: String) {
    PORTRAIT("عمودي"),
    LANDSCAPE("أفقي"),
}

@Serializable
enum class CutMarkStyle(val labelAr: String) {
    NONE("بدون"),
    BORDER("إطار حول كل كرت"),
    CORNERS("علامات زوايا"),
    DASHED("خطوط قص متقطعة"),
}

/**
 * تخطيط الصفحة — عدد الكروت في الصف والعمود، المسافات، الهوامش، والاتجاه.
 * إذا كان autoFit مفعّلاً يُحسب عدد الأعمدة والصفوف تلقائياً من مقاس الكرت.
 */
@Serializable
data class PageLayout(
    val paper: PaperSize = PaperSize.A4,
    val orientation: PageOrientation = PageOrientation.PORTRAIT,
    val autoFit: Boolean = true,
    val columns: Int = 2,
    val rows: Int = 5,
    val marginMm: Float = 8f,
    val hSpacingMm: Float = 3f,
    val vSpacingMm: Float = 3f,
    val cutMarks: CutMarkStyle = CutMarkStyle.BORDER,
    /** ملء الصفحة: يمدد الكروت لتملأ عرض الصفحة بالكامل */
    val stretchToFit: Boolean = false,
) {
    val pageWidthMm: Float get() = if (orientation == PageOrientation.PORTRAIT) paper.widthMm else paper.heightMm
    val pageHeightMm: Float get() = if (orientation == PageOrientation.PORTRAIT) paper.heightMm else paper.widthMm

    /** عدد الأعمدة والصفوف الفعلي لمقاس كرت معيّن */
    fun gridFor(cardWidthMm: Float, cardHeightMm: Float): Pair<Int, Int> {
        if (!autoFit) return columns.coerceAtLeast(1) to rows.coerceAtLeast(1)
        val usableW = pageWidthMm - 2 * marginMm
        val usableH = pageHeightMm - 2 * marginMm
        val c = ((usableW + hSpacingMm) / (cardWidthMm + hSpacingMm)).toInt().coerceAtLeast(1)
        val r = ((usableH + vSpacingMm) / (cardHeightMm + vSpacingMm)).toInt().coerceAtLeast(1)
        return c to r
    }

    fun perPage(cardWidthMm: Float, cardHeightMm: Float): Int {
        val (c, r) = gridFor(cardWidthMm, cardHeightMm)
        return c * r
    }
}

/** راوتر محفوظ — محلي أو عن بعد عبر دومين/كلاود */
@Serializable
data class RouterProfile(
    val id: Long,
    val name: String = "الراوتر",
    /** عنوان IP أو دومين مثل xxxxx.sn.mynetname.net */
    val host: String = "192.168.88.1",
    val port: Int = 8728,
    val username: String = "admin",
    val password: String = "",
    /** اتصال مشفّر api-ssl (المنفذ 8729) — مهم للاتصال عن بعد */
    val useSsl: Boolean = false,
    /** مهلة الاتصال بالثواني — تُزاد للاتصال عن بعد البطيء */
    val timeoutSec: Int = 12,
)

/** حالة الراوتر المقروءة مباشرة عبر الـ API */
@Serializable
data class RouterStatus(
    val identity: String = "",
    val version: String = "",
    val board: String = "",
    val uptime: String = "",
    val cpuLoad: String = "",
    val freeMemory: String = "",
    val totalMemory: String = "",
    val activeUsers: Int = 0,
    /** إجمالي كروت الهوتسبوت الموجودة على الراوتر */
    val hotspotUsers: Int = 0,
    /** إجمالي مستخدمي اليوزر منجر */
    val userManagerUsers: Int = 0,
    /** الكروت التي استهلكت كامل وقتها */
    val usedUsers: Int = 0,
) {
    /** الكروت غير المستهلكة (المتبقية للبيع) */
    val unusedUsers: Int get() = (hotspotUsers - usedUsers).coerceAtLeast(0)
}

/** مستخدم متصل الآن بالهوتسبوت */
@Serializable
data class ActiveUser(
    val id: String = "",
    val username: String = "",
    val address: String = "",
    val macAddress: String = "",
    val uptime: String = "",
    val bytesIn: Long = 0,
    val bytesOut: Long = 0,
)

/** باقة — من الهوتسبوت أو من اليوزر منجر */
@Serializable
data class HotspotProfile(
    val id: String = "",
    val name: String = "",
    val rateLimit: String = "",
    val sessionTimeout: String = "",
    val sharedUsers: String = "1",
    /** السعر يُحفظ محلياً في التطبيق لأن الراوتر لا يخزنه */
    val price: String = "",
    val source: CardSource = CardSource.HOTSPOT,
    /** عدد الكروت المرتبطة بهذه الباقة */
    val userCount: Int = 0,
)

/** دفعة كروت مطبوعة — للسجل وإعادة الطباعة والتقارير */
@Serializable
data class PrintBatch(
    val id: Long,
    val createdAt: Long,
    val templateId: Long,
    val templateName: String = "",
    val profile: String = "",
    val unitPrice: String = "",
    val paper: PaperType = PaperType.A4,
    val users: List<UserEntry> = emptyList(),
    val printCount: Int = 1,
) {
    val total: Double
        get() = (unitPrice.toDoubleOrNull() ?: 0.0) * users.size
}

/** إعدادات عامة */
@Serializable
data class AppSettings(
    val hotspotLoginUrl: String = "http://192.168.88.1/login",
    val wifiSsid: String = "",
    val wifiPassword: String = "",
    val currency: String = "ريال",
    /** نوع الكرت: اسم فقط، اسم وكلمة مرور، أو متشابه */
    val cardMode: CardMode = CardMode.SAME,
    val paperType: PaperType = PaperType.A4,
    /** ارتفاع الكرت على الطابعة الحرارية بالمليمتر */
    val thermalCardHeightMm: Float = 45f,
    /** تغذية الورق بعد كل كرت بالمليمتر */
    val thermalFeedMm: Float = 8f,
    val thermalDpi: Int = 203,
    /** وضع توافق للطابعات المقلدة التي تشوه الصور (أمر ESC *) */
    val escAsteriskMode: Boolean = false,
    /** قص الورق تلقائياً بعد آخر كرت */
    val autoCut: Boolean = false,
    /** طابعة شبكة (TCP) اختيارية */
    val tcpPrinterIp: String = "",
    val tcpPrinterPort: Int = 9100,
    /** تخطيط الصفحة للطباعة الورقية */
    val layout: PageLayout = PageLayout(),
    /** معرّف الراوتر النشط حالياً */
    val activeRouterId: Long = 0,
)
