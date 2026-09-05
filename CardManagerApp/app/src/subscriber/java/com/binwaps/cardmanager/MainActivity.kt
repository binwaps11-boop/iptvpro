package com.binwaps.cardmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.SpaceDashboard
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.license.LicenseManager
import com.binwaps.cardmanager.ui.screens.ConnectScreen
import com.binwaps.cardmanager.ui.screens.DashboardScreen
import com.binwaps.cardmanager.ui.screens.ExpressScreen
import com.binwaps.cardmanager.ui.screens.HistoryScreen
import com.binwaps.cardmanager.ui.screens.LayoutScreen
import com.binwaps.cardmanager.ui.screens.LicenseScreen
import com.binwaps.cardmanager.ui.screens.PrintScreen
import com.binwaps.cardmanager.ui.screens.ProfilesScreen
import com.binwaps.cardmanager.ui.screens.ReportsScreen
import com.binwaps.cardmanager.ui.screens.RouterAdminScreen
import com.binwaps.cardmanager.ui.screens.SalesScreen
import com.binwaps.cardmanager.ui.screens.SessionsScreen
import com.binwaps.cardmanager.ui.screens.SettingsScreen
import com.binwaps.cardmanager.ui.screens.TemplateEditorScreen
import com.binwaps.cardmanager.ui.screens.TemplatesScreen
import com.binwaps.cardmanager.ui.screens.UsersScreen
import com.binwaps.cardmanager.ui.theme.CardManagerTheme
import com.binwaps.cardmanager.ui.theme.Ink
import com.binwaps.cardmanager.ui.theme.Neon
import com.binwaps.cardmanager.ui.theme.Panel
import com.binwaps.cardmanager.ui.theme.TextLow

private data class Tab(val route: String, val labelAr: String, val icon: ImageVector)

// خمس وجهات عليا فقط في الشريط السفلي — أنظف وأوضح على الشاشات الضيقة.
// البقية (الباقات/التقارير/المبيعات/السجل/المتصلون/الراوتر/السريع) وجهات
// ثانوية يصلها المستخدم من بلاطات لوحة التحكم — فلا ازدواج بين الشريط واللوحة.
private val tabs = listOf(
    Tab("dashboard", "اللوحة", Icons.Filled.SpaceDashboard),
    Tab("users", "الكروت", Icons.Filled.CreditCard),
    Tab("templates", "القوالب", Icons.Filled.Layers),
    Tab("print", "الطباعة", Icons.Filled.Print),
    Tab("settings", "الإعدادات", Icons.Filled.Settings),
)

/** الشاشات التي تُخفى فيها قائمة التنقل السفلية */
private val fullScreenRoutes = listOf("connect", "editor", "layout", "license")

class MainActivity : ComponentActivity() {

    /** مفتاح وصل عبر رابط تفعيل من لوحة التراخيص */
    private val incomingKey = androidx.compose.runtime.mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        com.binwaps.cardmanager.data.CrashLogger.install(this)
        com.binwaps.cardmanager.render.CardRenderer.init(this)
        com.binwaps.cardmanager.data.Backend.init(this)
        Store.init(this)
        com.binwaps.cardmanager.data.EventLog.init(this)
        com.binwaps.cardmanager.data.EventLog.log("تشغيل", "فتح التطبيق")
        LicenseManager.init(this)
        // راوتر محفوظ ⇒ اتصال تلقائي فوري بالخلفية وفتح اللوحة مباشرة. كان كل فتح
        // للتطبيق يعرض شاشة الاتصال ويطلب ضغط «اتصال» يدوياً رغم وجود الراوتر.
        // اكتساب القفل محدود زمنياً وعمليات المستخدم لها الأولوية، فلا يعيق
        // المزامنةَ اتصالٌ يدوي لاحق من شاشة الاتصال.
        val savedRouter = Store.activeRouter()
        if (savedRouter != null) {
            com.binwaps.cardmanager.data.EventLog.log("تشغيل", "اتصال تلقائي بـ ${savedRouter.name}")
            com.binwaps.cardmanager.data.SyncEngine.start()
        }
        startCloudAutoActivate()
        handleLink(intent)

        setContent {
            CardManagerTheme {
                val navController = rememberNavController()
                val backStack by navController.currentBackStackEntryAsState()
                val currentRoute = backStack?.destination?.route.orEmpty()

                // الترخيص لا يحجب التطبيق أبداً: يفتح مباشرةً ويعمل بالكامل
                // (اتصال/جلب/رفع/طباعة) دون أي اعتماد على خادم خارجي. شاشة
                // الترخيص تبقى متاحة اختيارياً من الإعدادات لمن يريد التفعيل
                // أونلاين لاحقاً، لكنها لم تعد بوابة حجب. هذا يزيل العائق الذي
                // كان يقفل المستخدم خارج تطبيقه عندما يتعذّر الوصول للخادم.
                val showBar = fullScreenRoutes.none { currentRoute.startsWith(it) }

                // وصل رابط تفعيل ← افتح شاشة الترخيص فوراً
                androidx.compose.runtime.LaunchedEffect(incomingKey.value) {
                    if (incomingKey.value != null && currentRoute != "license") {
                        navController.navigate("license")
                    }
                }

                // نبضة تحقق/رفع اختيارية: تعمل فقط عند ضبط خادم تراخيص. بلا
                // خادم مضبوط (الوضع الافتراضي) لا تفعل شيئاً ولا تحجب أي شيء.
                androidx.compose.runtime.LaunchedEffect(Unit) {
                    while (true) {
                        LicenseManager.syncOnline()
                        // نرفع ملخّص الراوترات (اسم + عنوان فقط) فيراها الأدمن
                        // في لوحته المركزية — بلا كلمات مرور
                        runCatching {
                            val routers = Store.routers.value.map { it.name to it.host }
                            if (routers.isNotEmpty()) LicenseManager.pushRouters(routers)
                        }
                        kotlinx.coroutines.delay(6 * 3600_000L)
                    }
                }

                Scaffold(
                    containerColor = Ink,
                    bottomBar = {
                        if (showBar) {
                            NavigationBar(containerColor = Panel, tonalElevation = 0.dp) {
                                tabs.forEach { tab ->
                                    NavigationBarItem(
                                        selected = currentRoute == tab.route,
                                        onClick = {
                                            navController.navigate(tab.route) {
                                                // «اللوحة» هي جذر التبويبات فعلياً بعد الاتصال —
                                                // الوجهة الأصلية (connect) تُحذف من المكدس فلا
                                                // يقتطع popUpTo شيئاً وينمو المكدس بلا حد
                                                popUpTo("dashboard") { saveState = true }
                                                launchSingleTop = true
                                                restoreState = true
                                            }
                                        },
                                        icon = { Icon(tab.icon, contentDescription = tab.labelAr, modifier = Modifier.size(20.dp)) },
                                        // ٨٫٥sp كان غير مقروء للعربية على أي جهاز
                                        label = {
                                            Text(
                                                tab.labelAr,
                                                fontSize = 11.sp,
                                                lineHeight = 14.sp,
                                                maxLines = 1,
                                            )
                                        },
                                        alwaysShowLabel = true,
                                        colors = NavigationBarItemDefaults.colors(
                                            selectedIconColor = Ink,
                                            selectedTextColor = Neon,
                                            indicatorColor = Neon,
                                            unselectedIconColor = TextLow,
                                            unselectedTextColor = TextLow,
                                        ),
                                    )
                                }
                            }
                        }
                    }
                ) { padding ->
                    NavHost(
                        navController = navController,
                        // راوتر محفوظ ⇒ اللوحة مباشرة (المزامنة تتصل بالخلفية)؛ وإلا شاشة الاتصال
                        startDestination = if (Store.activeRouter() != null) "dashboard" else "connect",
                        modifier = Modifier.padding(padding).background(Ink),
                    ) {
                        composable("license") {
                            LicenseScreen(
                                blocking = false,
                                incomingKey = incomingKey.value,
                                onIncomingConsumed = { incomingKey.value = null },
                                onActivated = {
                                    navController.navigate("connect") { popUpTo("license") { inclusive = true } }
                                },
                                onBack = { navController.popBackStack(); Unit },
                            )
                        }
                        composable("connect") {
                            ConnectScreen(
                                onConnected = {
                                    com.binwaps.cardmanager.data.SyncEngine.start()
                                    navController.navigate("dashboard") { popUpTo("connect") { inclusive = true } }
                                },
                                onSkip = { navController.navigate("dashboard") { popUpTo("connect") { inclusive = true } } },
                            )
                        }
                        composable("dashboard") { DashboardScreen(navController) }
                        composable("users") { UsersScreen() }
                        composable("templates") { TemplatesScreen(navController) }
                        composable(
                            "editor/{templateId}",
                            arguments = listOf(navArgument("templateId") { type = NavType.LongType })
                        ) { entry ->
                            TemplateEditorScreen(
                                templateId = entry.arguments?.getLong("templateId") ?: 0L,
                                onDone = { navController.popBackStack() },
                            )
                        }
                        composable(
                            "layout/{templateId}",
                            arguments = listOf(navArgument("templateId") { type = NavType.LongType })
                        ) { entry ->
                            LayoutScreen(
                                templateId = entry.arguments?.getLong("templateId") ?: 0L,
                                onDone = { navController.popBackStack() },
                            )
                        }
                        composable("print") { PrintScreen(navController) }
                        composable("profiles") { ProfilesScreen() }
                        composable("history") { HistoryScreen() }
                        composable("active") { SessionsScreen() }
                        composable("sales") { SalesScreen() }
                        composable("reports") { ReportsScreen() }
                        composable("express") { ExpressScreen() }
                        composable("router") { RouterAdminScreen() }
                        composable("settings") {
                            SettingsScreen(
                                onDisconnect = {
                                    // قطع فعلي: إيقاف المزامنة أولاً وإلا أعادت فتح الجلسة خلال ثوانٍ
                                    com.binwaps.cardmanager.data.SyncEngine.stop()
                                    com.binwaps.cardmanager.mikrotik.MikrotikClient.disconnect()
                                    navController.navigate("connect") { popUpTo("dashboard") { inclusive = true } }
                                },
                                onLicense = { navController.navigate("license") },
                            )
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLink(intent)
    }

    /** يلتقط رابط التفعيل cardmanager://activate?k=... */
    private fun handleLink(intent: android.content.Intent?) {
        val key = com.binwaps.cardmanager.license.LicenseLink.parseActivation(intent?.data)
        if (key != null) incomingKey.value = key
    }

    private var cloudReg: com.google.firebase.firestore.ListenerRegistration? = null

    /**
     * يستمع لحساب المشترك في السحابة: بمجرد أن يوافق الأدمن ويُصدر المفتاح
     * يُفعَّل التطبيق تلقائياً دون أي خطوة من المشترك.
     */
    private fun startCloudAutoActivate() {
        val email = LicenseManager.customerEmail()
        if (email.isBlank()) return
        val id = com.binwaps.cardmanager.data.Backend.accountId(email, LicenseManager.deviceCode())
        cloudReg?.remove()
        cloudReg = com.binwaps.cardmanager.data.Backend.listenAccount(id) { acc ->
            if (acc == null) {
                // حُذف الحساب من السحابة = لا قرار إيقاف قائم — نرفع القفل حتى
                // لا يبقى المشترك محبوساً دون إشارة (سيناريو إيقاف ← حذف ← إعادة بيع)
                if (LicenseManager.isRemoteSuspended()) LicenseManager.setRemoteSuspended(false)
                return@listenAccount
            }
            // إيقاف عن بعد: قرار الأدمن نافذ لحظياً ويُرجّح فوق التجربة والمفتاح
            val suspended = acc.status == "suspended" || acc.status == "blocked"
            if (suspended != LicenseManager.isRemoteSuspended()) {
                LicenseManager.setRemoteSuspended(suspended)
            }
            if (suspended) return@listenAccount
            if (acc.approved && acc.key != LicenseManager.savedLicense()) {
                LicenseManager.activate(acc.key)
            }
        }
    }

    override fun onDestroy() {
        cloudReg?.remove()
        super.onDestroy()
    }
}
