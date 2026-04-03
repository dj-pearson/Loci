package com.pearsonmedia.loci.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.pearsonmedia.loci.ui.screen.auth.SignInScreen
import com.pearsonmedia.loci.ui.screen.detail.LocusDetailScreen
import com.pearsonmedia.loci.ui.screen.map.MapScreen
import com.pearsonmedia.loci.ui.screen.map.ListScreen
import com.pearsonmedia.loci.ui.screen.onboarding.OnboardingScreen
import com.pearsonmedia.loci.ui.screen.record.RecordingScreen
import com.pearsonmedia.loci.ui.screen.search.SearchScreen
import com.pearsonmedia.loci.ui.screen.settings.SettingsScreen

sealed class Screen(val route: String) {
    data object Onboarding : Screen("onboarding")
    data object SignIn : Screen("sign_in")
    data object Map : Screen("map")
    data object LocusList : Screen("list")
    data object Settings : Screen("settings")
    data object Recording : Screen("recording")
    data object Detail : Screen("detail/{locusId}") {
        fun createRoute(locusId: String) = "detail/$locusId"
    }
    data object Search : Screen("search")
}

data class BottomNavItem(
    val screen: Screen,
    val label: String,
    val icon: ImageVector
)

val bottomNavItems = listOf(
    BottomNavItem(Screen.Map, "Map", Icons.Default.Map),
    BottomNavItem(Screen.LocusList, "List", Icons.Default.List),
    BottomNavItem(Screen.Settings, "Settings", Icons.Default.Settings)
)

@Composable
fun LociNavHost(
    navController: NavHostController = rememberNavController()
) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    val showBottomBar = currentDestination?.route in listOf(
        Screen.Map.route, Screen.LocusList.route, Screen.Settings.route
    )

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    bottomNavItems.forEach { item ->
                        NavigationBarItem(
                            icon = { Icon(item.icon, contentDescription = item.label) },
                            label = { Text(item.label) },
                            selected = currentDestination?.hierarchy?.any {
                                it.route == item.screen.route
                            } == true,
                            onClick = {
                                navController.navigate(item.screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Map.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Onboarding.route) {
                OnboardingScreen(
                    onComplete = {
                        navController.navigate(Screen.Map.route) {
                            popUpTo(Screen.Onboarding.route) { inclusive = true }
                        }
                    }
                )
            }

            composable(Screen.SignIn.route) {
                SignInScreen(
                    onSignInSuccess = {
                        navController.navigate(Screen.Map.route) {
                            popUpTo(Screen.SignIn.route) { inclusive = true }
                        }
                    }
                )
            }

            composable(Screen.Map.route) {
                MapScreen(
                    onRecordClick = { navController.navigate(Screen.Recording.route) },
                    onLocusClick = { id -> navController.navigate(Screen.Detail.createRoute(id)) },
                    onSearchClick = { navController.navigate(Screen.Search.route) }
                )
            }

            composable(Screen.LocusList.route) {
                ListScreen(
                    onLocusClick = { id -> navController.navigate(Screen.Detail.createRoute(id)) },
                    onSearchClick = { navController.navigate(Screen.Search.route) }
                )
            }

            composable(Screen.Settings.route) {
                SettingsScreen(
                    onSignInClick = { navController.navigate(Screen.SignIn.route) }
                )
            }

            composable(Screen.Recording.route) {
                RecordingScreen(
                    onDismiss = { navController.popBackStack() },
                    onSaved = { navController.popBackStack() }
                )
            }

            composable(
                route = Screen.Detail.route,
                arguments = listOf(navArgument("locusId") { type = NavType.StringType })
            ) { backStackEntry ->
                val locusId = backStackEntry.arguments?.getString("locusId") ?: return@composable
                LocusDetailScreen(
                    locusId = locusId,
                    onBack = { navController.popBackStack() }
                )
            }

            composable(Screen.Search.route) {
                SearchScreen(
                    onLocusClick = { id -> navController.navigate(Screen.Detail.createRoute(id)) },
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}
