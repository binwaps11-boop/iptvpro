package com.binwaps.cardmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Style
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.navigation.NavType
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.ui.screens.HomeScreen
import com.binwaps.cardmanager.ui.screens.PrintScreen
import com.binwaps.cardmanager.ui.screens.SettingsScreen
import com.binwaps.cardmanager.ui.screens.TemplateEditorScreen
import com.binwaps.cardmanager.ui.screens.TemplatesScreen
import com.binwaps.cardmanager.ui.screens.UsersScreen
import com.binwaps.cardmanager.ui.theme.CardManagerTheme

data class Tab(val route: String, val labelAr: String, val icon: ImageVector)

val tabs = listOf(
    Tab("home", "الرئيسية", Icons.Filled.Home),
    Tab("users", "المستخدمون", Icons.Filled.People),
    Tab("templates", "القوالب", Icons.Filled.Style),
    Tab("print", "الطباعة", Icons.Filled.Print),
    Tab("settings", "الإعدادات", Icons.Filled.Settings),
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Store.init(this)
        setContent {
            CardManagerTheme {
                val navController = rememberNavController()
                val backStack by navController.currentBackStackEntryAsState()
                val currentRoute = backStack?.destination?.route

                Scaffold(
                    bottomBar = {
                        if (currentRoute?.startsWith("editor") != true) {
                            NavigationBar {
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
                                        label = { Text(tab.labelAr) },
                                    )
                                }
                            }
                        }
                    }
                ) { padding ->
                    NavHost(
                        navController = navController,
                        startDestination = "home",
                        modifier = Modifier.padding(padding),
                    ) {
                        composable("home") { HomeScreen(navController) }
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
                        composable("print") { PrintScreen() }
                        composable("settings") { SettingsScreen() }
                    }
                }
            }
        }
    }
}
