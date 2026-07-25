package com.binwaps.cardmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
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
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.license.LicenseManager
import com.binwaps.cardmanager.license.LicenseState
import com.binwaps.cardmanager.ui.screens.ConnectScreen
import com.binwaps.cardmanager.ui.screens.DashboardScreen
import com.binwaps.cardmanager.ui.screens.HistoryScreen
import com.binwaps.cardmanager.ui.screens.LayoutScreen
import com.binwaps.cardmanager.ui.screens.LicenseScreen
import com.binwaps.cardmanager.ui.screens.PrintScreen
import com.binwaps.cardmanager.ui.screens.ProfilesScreen
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

// أربعة تبويبات فقط — بقية الأقسام تفتح من شبكة الرئيسية
private val tabs = listOf(
    Tab("dashboard", "الرئيسية", Icons.Filled.SpaceDashboard),
    Tab("users", "الكروت", Icons.Filled.CreditCard),
    Tab("active", "المتصلون", Icons.Filled.People),
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
        Store.init(this)
        LicenseManager.init(this)
        handleLink(intent)

        setContent {
            CardManagerTheme {
                val navController = rememberNavController()
                val backStack by navController.currentBackStackEntryAsState()
                val currentRoute = backStack?.destination?.route.orEmpty()
                val licenseState by LicenseManager.state.collectAsState()

                val blocked = licenseState is LicenseState.TrialEnded || licenseState is LicenseState.Expired
                val showBar = fullScreenRoutes.none { currentRoute.startsWith(it) }

                // وصل رابط تفعيل ← افتح شاشة الترخيص فوراً
                androidx.compose.runtime.LaunchedEffect(incomingKey.value) {
                    if (incomingKey.value != null && currentRoute != "license") {
                        navController.navigate("license")
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
                                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                                launchSingleTop = true
                                                restoreState = true
                                            }
                                        },
                                        icon = { Icon(tab.icon, contentDescription = tab.labelAr) },
                                        label = { Text(tab.labelAr, fontSize = 9.5.sp) },
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
                        startDestination = if (blocked) "license" else "connect",
                        modifier = Modifier.padding(padding).background(Ink),
                    ) {
                        composable("license") {
                            LicenseScreen(
                                blocking = blocked,
                                incomingKey = incomingKey.value,
                                onIncomingConsumed = { incomingKey.value = null },
                                onActivated = {
                                    navController.navigate("connect") { popUpTo("license") { inclusive = true } }
                                },
                                onBack = if (blocked) null else ({ navController.popBackStack(); Unit }),
                            )
                        }
                        composable("connect") {
                            ConnectScreen(
                                onConnected = { navController.navigate("dashboard") { popUpTo("connect") { inclusive = true } } },
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
                        composable("settings") {
                            SettingsScreen(
                                onDisconnect = { navController.navigate("connect") { popUpTo("dashboard") { inclusive = true } } },
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
}
