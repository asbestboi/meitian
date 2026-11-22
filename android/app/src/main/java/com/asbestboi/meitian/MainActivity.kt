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
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import uniffi.meitian_core.SoundId
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
    fun show(c: @Composable () -> Unit) {
        if (content == null) Sfx.play(SoundId.SHEET_OPEN)
        content = c
    }
    fun close() {
        if (content != null) Sfx.play(SoundId.SHEET_CLOSE)
        content = null
    }
}

/** Haptics switched off in settings. */
private object NoHaptics : HapticFeedback {
    override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {}
}

val LocalNav = staticCompositionLocalOf { Overlay() }

@Composable
fun Root() {
    val app = LocalApp.current
    Sfx.enabled = app.settings.sounds
    Sfx.volume = app.settings.volume
    val overlay = remember { Overlay() }
    val context = androidx.compose.ui.platform.LocalContext.current
    // Downloaded lessons: load the cache, refresh daily, and again when the placement level changes.
    androidx.compose.runtime.LaunchedEffect(app.profile.confirmedLevel) {
        ContentSync.start(context.applicationContext, app.profile.confirmedLevel + 1)
    }
    Box(Modifier.fillMaxSize().background(Street.c.paper)) {
        val haptics = LocalHapticFeedback.current
        CompositionLocalProvider(LocalNav provides overlay, LocalHapticFeedback provides if (app.settings.haptics) haptics else NoHaptics) {
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
            val arena = app.arenaReveal
            if (app.profile.onboarded && overlay.content == null && arena != null) {
                BackHandler { app.arenaReveal = null }
                com.asbestboi.meitian.ui.ArenaReveal(arena) { app.arenaReveal = null }
            }
            app.toast?.let { text ->
                androidx.compose.runtime.LaunchedEffect(text) { Sfx.play(SoundId.COIN); kotlinx.coroutines.delay(4_500); app.toast = null }
                Text(text, color = Street.c.paper, fontWeight = FontWeight.Bold,
                    modifier = Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing).padding(top = 12.dp)
                        .background(Street.c.ink, androidx.compose.foundation.shape.RoundedCornerShape(50)).padding(horizontal = 18.dp, vertical = 10.dp))
            }
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
                    Modifier.weight(1f).clickable { if (tab != i) Sfx.play(SoundId.TAB_SWITCH); tab = i }.padding(vertical = 4.dp),
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
