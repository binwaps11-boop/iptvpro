package com.binwaps.cardmanager.model

import kotlinx.serialization.Serializable

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

/** إعدادات عامة */
@Serializable
data class AppSettings(
    val hotspotLoginUrl: String = "http://192.168.88.1/login",
    val wifiSsid: String = "",
    val wifiPassword: String = "",
    val currency: String = "ريال",
    val paperType: PaperType = PaperType.A4,
    /** ارتفاع الكرت على الطابعة الحرارية بالمليمتر */
    val thermalCardHeightMm: Float = 45f,
    /** تغذية الورق بعد كل كرت بالمليمتر */
    val thermalFeedMm: Float = 8f,
    val thermalDpi: Int = 203,
    val a4MarginMm: Float = 8f,
    val a4SpacingMm: Float = 3f,
    val cutMarks: Boolean = true,
    val mikrotikHost: String = "192.168.88.1",
    val mikrotikPort: Int = 8728,
    val mikrotikUser: String = "admin",
    val mikrotikPassword: String = "",
)
