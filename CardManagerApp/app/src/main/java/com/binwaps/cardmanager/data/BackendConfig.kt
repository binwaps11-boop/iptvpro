package com.binwaps.cardmanager.data

/** Optional messaging configuration. Subscription authority belongs to the separate HTTPS service. */
object BackendConfig {
    const val API_KEY = ""
    const val APP_ID = ""
    const val PROJECT_ID = ""
    // اختيارية — تُملأ إن ظهرت في إعدادات مشروعك
    const val SENDER_ID = ""      // messagingSenderId
    const val STORAGE_BUCKET = "" // storageBucket

    /** هل الربط السحابي مُهيَّأ؟ */
    val enabled: Boolean get() = API_KEY.isNotBlank() && PROJECT_ID.isNotBlank() && APP_ID.isNotBlank()

    // The endpoint may change, but only this provider's signed responses are accepted.
    val LICENSE_SERVER: String get() = com.binwaps.cardmanager.license.LicenseConnection.url
    const val SERVER_PUBLIC_KEY = "MFkwEwYHKoZIzj0CAQYIKZIzj0DAQcDQgAE1MWT9dlUXw/GbGmCN1vgR0TDigSjBSiSzv4aDYOCbwBN1/UR9kFaiHlBi+kJrKPN9YkaIN1wItF+vygS7UoYsw=="
    val licenseServerEnabled: Boolean get() = LICENSE_SERVER.isNotBlank()
}
