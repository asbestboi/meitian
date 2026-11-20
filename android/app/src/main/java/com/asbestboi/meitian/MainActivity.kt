package com.asbestboi.meitian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.data.AppState
import com.asbestboi.meitian.data.ContentSync
import com.asbestboi.meitian.data.Online
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.Speaker
import com.asbestboi.meitian.ui.ArenaScreen
import com.asbestboi.meitian.ui.Grain
import com.asbestboi.meitian.ui.MeitianTheme
import com.asbestboi.meitian.ui.OnboardingScreen
import com.asbestboi.meitian.ui.PracticeScreen
import com.asbestboi.meitian.ui.ProgressScreen
import com.asbestboi.meitian.ui.Street
import com.asbestboi.meitian.ui.LearnScreen

val LocalApp = staticCompositionLocalOf<AppState> { error("no app state") }

class MainActivity : ComponentActivity() {
    private lateinit var app: AppState

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        app = AppState(this)
        Speaker.init(this)
        setContent {
            MeitianTheme {
                CompositionLocalProvider(LocalApp provides app) { Root() }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (::app.isInitialized) {
            app.refreshDay()
            val level = app.profile.confirmedLevel + 1
            lifecycleScope.launch { ContentSync.refreshIfStale(applicationContext, level) }
            lifecycleScope.launch { Online.init(applicationContext); Online.sync(app); Online.refreshInbox() }
        }
    }

    override fun onPause() {
        super.onPause()
        if (::app.isInitialized) app.save()
    }
}

/** A screen pushed over the tabs (learning session, games, shop…). */
class Overlay {
    var content by mutableStateOf<(@Composable () -> Unit)?>(null)
    fun show(c: @Composable () -> Unit) { content = c }
    fun close() { content = null }
}

val LocalNav = staticCompositionLocalOf { Overlay() }

@Composable
fun Root() {
    val app = LocalApp.current
    Sfx.enabled = app.settings.sounds
    val overlay = remember { Overlay() }
    val context = androidx.compose.ui.platform.LocalContext.current
    // Downloaded lessons: load the cache, refresh daily, and again when the placement level changes.
    androidx.compose.runtime.LaunchedEffect(app.profile.confirmedLevel) {
        ContentSync.start(context.applicationContext, app.profile.confirmedLevel + 1)
    }
    Box(Modifier.fillMaxSize().background(Street.c.paper)) {
        CompositionLocalProvider(LocalNav provides overlay) {
            if (!app.profile.onboarded) {
                Box(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) { OnboardingScreen() }
            } else {
                Tabs()
            }
            overlay.content?.let { c ->
                BackHandler { overlay.close() }
                Box(Modifier.fillMaxSize().background(Street.c.paper).windowInsetsPadding(WindowInsets.safeDrawing)) { c() }
            }
            // milestones reached during a lesson or game pop up once it's closed
            if (app.profile.onboarded && overlay.content == null) com.asbestboi.meitian.ui.MilestoneCelebration()
        }
    }
}

@Composable
fun Tabs() {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val tabs = listOf("🗺️" to "Learn", "🃏" to "Practice", "⚔️" to "Arena", "👤" to "Profile")
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
        Box(Modifier.weight(1f)) {
            when (tab) {
                0 -> LearnScreen(goToPractice = { tab = 1 })
                1 -> PracticeScreen()
                2 -> ArenaScreen()
                else -> ProgressScreen()
            }
        }
        Row(
            Modifier.fillMaxWidth().background(Street.c.card).navigationBarsPadding().padding(vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            tabs.forEachIndexed { i, (icon, label) ->
                Column(
                    Modifier.weight(1f).clickable { tab = i }.padding(vertical = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    val scale by androidx.compose.animation.core.animateFloatAsState(if (tab == i) 1.18f else 1f,
                        androidx.compose.animation.core.spring(dampingRatio = 0.5f), label = "tab")
                    Text(icon, fontSize = 21.sp, modifier = Modifier.graphicsLayer { scaleX = scale; scaleY = scale })
                    Text(label.lowercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold,
                        color = if (tab == i) Street.c.text else Street.c.secondary)
                }
            }
        }
    }
}
