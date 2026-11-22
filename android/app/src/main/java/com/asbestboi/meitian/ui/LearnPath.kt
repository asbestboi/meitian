package com.asbestboi.meitian.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.LocalNav
import kotlinx.coroutines.delay
import uniffi.meitian_core.PathNode
import uniffi.meitian_core.PathNodeKind
import uniffi.meitian_core.PathNodeState
import uniffi.meitian_core.PathUnit
import uniffi.meitian_core.pathSentencesXp
import uniffi.meitian_core.pathSwing

/** Learn tab: one winding path through the current HSK level (Duolingo-style map). Lessons, sentences, a story
 *  checkpoint after every unit, the level-up test at the end. One big button always says what's next. */
@Composable
fun LearnScreen(goToPractice: () -> Unit) {
    val app = LocalApp.current
    val nav = LocalNav.current
    val ctx = LocalContext.current
    val units = app.learnPath
    val next = units.flatMap { it.nodes }.firstOrNull { it.next }
    var hint by remember { mutableStateOf<String?>(null) }
    var hintTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(hintTick) { if (hintTick > 0) { delay(2200); hint = null } }
    fun show(text: String) { hint = text; hintTick++ }

    fun start(words: List<uniffi.meitian_core.CoreWord>) {
        if (words.isEmpty()) return
        nav.show { LearnSession(words) { nav.close() } }
    }

    fun openStory(unit: Int, done: Boolean) {
        val chat = unit % 2 == 0
        val s = StoryProgress.next(ctx, chat, app, unit)
            ?: StoryProgress.next(ctx, !chat, app, unit)
        when {
            s != null -> {
                prefetchStory(ctx, s)
                nav.show {
                    StoryPlayer(s, onFinished = { translations -> if (!done) app.finishPathStory(unit, translations) }) { nav.close() }
                }
            }
            !done -> { app.finishPathStory(unit); show("🎁 chest opened · +20 XP") }
            else -> show("learn more words to unlock the next story")
        }
    }

    fun tap(node: PathNode) {
        if (node.state == PathNodeState.LOCKED) {
            show(when (node.kind) {
                PathNodeKind.LESSON -> "finish the lessons before this one first"
                PathNodeKind.SENTENCES -> "finish lesson ${node.number} to open these sentences"
                PathNodeKind.STORY -> "finish unit ${node.unit}'s sentences to open its story"
                PathNodeKind.TEST -> "learn every lesson to unlock the test"
            })
            return
        }
        when (node.kind) {
            PathNodeKind.LESSON -> start(if (node.state == PathNodeState.DONE) app.lessonWords(node.number.toInt()) else app.nextUpWords())
            PathNodeKind.SENTENCES -> nav.show { SentenceSession(node) { nav.close() } }
            PathNodeKind.STORY -> openStory(node.unit.toInt(), node.state == PathNodeState.DONE)
            PathNodeKind.TEST -> if (app.canLevelUp) {
                val level = app.currentLevel
                nav.show { LevelTest(level, onPracticeWeak = goToPractice) { nav.close() } }
            } else show("you've reached the highest level 🐉")
        }
    }

    // flat list: unit headers and nodes, so the list can jump to "next up"
    val rows = remember(units) {
        units.flatMap { u -> listOf<Any>(u) + u.nodes.mapIndexed { i, n -> n to i } }
    }
    val listState = rememberLazyListState()
    // finishing a node opens the next one
    var lastNext by remember(com.asbestboi.meitian.data.ContentSync.generation) { mutableStateOf<Pair<PathNodeKind, UInt>?>(null) }
    LaunchedEffect(next?.kind, next?.number, nav.content == null) {
        if (nav.content != null || next == null) return@LaunchedEffect
        val now = next.kind to next.number
        if (lastNext != null && lastNext != now) com.asbestboi.meitian.data.Sfx.play(uniffi.meitian_core.SoundId.NODE_UNLOCK)
        lastNext = now
    }
    LaunchedEffect(app.currentLevel) { app.checkArena() }
    LaunchedEffect(Unit) {
        val i = rows.indexOfFirst { (it as? Pair<*, *>)?.first == next }
        if (i > 2) listState.scrollToItem(i - 2)
    }

    Column(Modifier.fillMaxSize()) {
        TopBar { nav.show { GoalsScreen { nav.close() } } }
        SlotCard()
        Box(Modifier.weight(1f)) {
            ArenaBackground(app.arenaTheme, strength = 0.42f, scroll = { listState.firstVisibleItemIndex * 120f + listState.firstVisibleItemScrollOffset })
            LazyColumn(state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp)) {
                app.freezeNotice?.let { saved ->
                    item {
                        Row(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(16.dp)).background(Street.c.sky.copy(alpha = 0.15f)).padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text("🧊", fontSize = 22.sp); HSpacer(10.dp)
                            Text("A streak freeze saved your $saved-day streak!", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f))
                            Text("✕", color = Street.c.secondary, modifier = Modifier.clickable { app.freezeNotice = null }.padding(8.dp))
                        }
                    }
                }
                rows.forEach { row ->
                    item {
                        if (row is PathUnit) UnitHeader(row, app.currentLevel)
                        else {
                            val pair = row as Pair<*, *>
                            val node = pair.first as PathNode
                            val i = pair.second as Int
                            PathNodeButton(node, app.currentLevel, pathSwing(i.toUInt()).toFloat()) { tap(node) }
                        }
                    }
                }
                item {
                    Text("HSK ${app.currentLevel + 1} unlocks after the test ✦", fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                        color = Street.c.secondary, modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }
        }
        // the one primary action, in the thumb zone
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            AnimatedVisibility(hint != null) {
                Text(hint ?: "", fontWeight = FontWeight.Bold, color = Street.c.paper,
                    modifier = Modifier.padding(bottom = 8.dp).clip(RoundedCornerShape(50)).background(Street.c.ink).padding(horizontal = 16.dp, vertical = 8.dp))
            }
            next?.let { n ->
                val (title, sub) = when (n.kind) {
                    PathNodeKind.TEST -> "take the HSK ${app.currentLevel} test" to "pass with 80% to unlock HSK ${app.currentLevel + 1}"
                    PathNodeKind.SENTENCES -> "build sentences" to "+${pathSentencesXp()} XP · only words you know"
                    PathNodeKind.STORY -> "read the unit ${n.unit} story" to "+20 XP"
                    PathNodeKind.LESSON -> (if (app.today.learnedDone) "start lesson ${n.number}" else "learn today's words") to
                        "unit ${n.unit} · lesson ${n.number} · ${app.profile.dailyGoal} new words"
                }
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(50)).background(Street.lime()).clickable { tap(n) }
                    .padding(horizontal = 24.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp, color = Color.Black)
                        Text(sub, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, color = Color.Black.copy(alpha = 0.7f))
                    }
                    Text("→", fontWeight = FontWeight.ExtraBold, fontSize = 20.sp, color = Color.Black)
                }
            }
        }
    }
}

@Composable
private fun TopBar(openGoals: () -> Unit) {
    val app = LocalApp.current
    val quests = app.quests
    val claimable = quests.count { it.done && !app.isClaimed(it.quest) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val lc = Street.levelColor(app.currentLevel)
        Text("HSK ${app.currentLevel}", fontWeight = FontWeight.ExtraBold, color = lc,
            modifier = Modifier.clip(RoundedCornerShape(50)).background(lc.copy(alpha = 0.16f)).padding(horizontal = 12.dp, vertical = 8.dp))
        Spacer(Modifier.weight(1f))
        Chip("🔥 ${app.streak}") {}
        Chip("⚡ ${app.today.xp.coerceAtLeast(0)}", onClick = openGoals)
        Box {
            Chip("🎯 ${quests.count { it.done }}/${quests.size}", onClick = openGoals)
            if (claimable > 0) Box(Modifier.align(Alignment.TopEnd).size(10.dp).clip(CircleShape).background(Street.c.red))
        }
    }
}

@Composable
private fun Chip(text: String, onClick: () -> Unit) {
    Text(text, fontWeight = FontWeight.ExtraBold, color = Street.c.text,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.c.card).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp))
}

@Composable
private fun UnitHeader(unit: PathUnit, level: Int) {
    val done = unit.nodes.all { it.state == PathNodeState.DONE || it.kind == PathNodeKind.TEST }
    Row(Modifier.fillMaxWidth().padding(top = if (unit.number == 1u) 8.dp else 32.dp, bottom = 16.dp)
        .clip(RoundedCornerShape(20.dp)).background(Street.level(level)).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("unit ${unit.number}", style = street(20.sp), color = Color.White)
            Text("HSK $level · lessons ${unit.firstLesson}–${unit.lastLesson}", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.85f))
        }
        if (done) Text("✓", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
    }
}

/** One stop on the path: a chunky round button with a darker base. */
@Composable
private fun PathNodeButton(node: PathNode, level: Int, swing: Float, onClick: () -> Unit) {
    val lesson = node.kind == PathNodeKind.LESSON
    val size = if (lesson) 72.dp else 84.dp
    val locked = node.state == PathNodeState.LOCKED
    val color = when {
        locked -> Street.c.secondary.copy(alpha = 0.22f)
        node.kind == PathNodeKind.TEST -> Street.c.gold
        node.kind == PathNodeKind.STORY -> Street.c.pink
        node.kind == PathNodeKind.SENTENCES -> Street.c.sky
        else -> Street.levelColor(level)
    }
    val icon = when (node.kind) {
        PathNodeKind.LESSON -> if (node.state == PathNodeState.DONE) "✓" else if (locked) "🔒" else "★"
        PathNodeKind.SENTENCES -> "💬"
        PathNodeKind.STORY -> "📖"
        PathNodeKind.TEST -> "🏆"
    }
    val pulse = if (node.next) {
        val t = rememberInfiniteTransition(label = "pulse")
        t.animateFloat(0.96f, 1.08f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "p").value
    } else 1f
    Box(Modifier.fillMaxWidth().padding(vertical = if (lesson) 10.dp else 22.dp), contentAlignment = Alignment.Center) {
        Column(Modifier.offset(x = (swing * 72).dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (node.next) {
                Text(if (node.kind == PathNodeKind.TEST) "TEST" else "START", fontWeight = FontWeight.ExtraBold, fontSize = 12.sp, color = color,
                    modifier = Modifier.offset(y = ((1 - pulse) * 40).dp).clip(RoundedCornerShape(50)).background(Street.c.card)
                        .padding(horizontal = 12.dp, vertical = 6.dp))
                Spacer(Modifier.size(8.dp))
            }
            Box(Modifier.size(size + 18.dp), contentAlignment = Alignment.Center) {
                if (node.next) Box(Modifier.size(size + 18.dp).scale(pulse).border(6.dp, color.copy(alpha = 0.35f), CircleShape))
                // darker base for depth
                Box(Modifier.size(size).offset(y = 6.dp).clip(CircleShape).background(lerp(color, Color.Black, 0.25f)))
                Box(Modifier.size(size).clip(CircleShape).background(color).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
                    Text(icon, fontSize = (if (lesson) 28 else 32).sp, fontWeight = FontWeight.ExtraBold,
                        color = if (locked) Street.c.secondary else Color.White)
                }
            }
            if (!lesson) Text(when (node.kind) {
                PathNodeKind.TEST -> "level-up test"
                PathNodeKind.SENTENCES -> "sentences · +${pathSentencesXp()} XP"
                else -> "story"
            }, fontSize = 12.sp,
                fontWeight = FontWeight.Bold, color = Street.c.secondary, modifier = Modifier.padding(top = 4.dp))
        }
    }
}

/** Today's milestones and quests (from the top bar). */
@Composable
fun GoalsScreen(close: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CloseButton(close); HSpacer(12.dp)
            Text("today's goals", style = street(24.sp), color = Street.c.text)
        }
        MilestoneCard()
        QuestCard()
    }
}
