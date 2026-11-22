package com.asbestboi.meitian.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.Token

/** Word ids of the tokens the learner hasn't learned yet (decided by the core). */
val List<Token>.newIds: List<String> get() = filter { it.isNew }.mapNotNull { it.wordId }

/** Running text: lime behind the characters and a dotted gold underline mark a new word. */
@Composable
fun Modifier.newWordMark(): Modifier {
    val lime = Street.c.lime.copy(alpha = 0.3f)
    val gold = Street.c.gold
    return this.clip(RoundedCornerShape(5.dp)).background(lime).drawBehind {
        val y = size.height - 1.5.dp.toPx()
        drawLine(gold, Offset(2.dp.toPx(), y), Offset(size.width - 2.dp.toPx(), y), 2.dp.toPx(), StrokeCap.Round,
            PathEffect.dashPathEffect(floatArrayOf(0.1f, 4.dp.toPx())))
    }
}

/** The same mark inside one line of text (reply choices, narration). */
@Composable
fun markedText(tokens: List<Token>): AnnotatedString {
    val lime = Street.c.lime.copy(alpha = 0.3f)
    return buildAnnotatedString {
        tokens.forEach { t ->
            if (t.isNew) withStyle(SpanStyle(background = lime, textDecoration = TextDecoration.Underline)) { append(t.text) }
            else append(t.text)
        }
    }
}

/** What TalkBack reads for a line: "new word" before every new word. */
fun List<Token>.spoken(): String = joinToString("") { if (it.isNew) " new word ${it.text} " else it.text }

/** "NEW" pill for a word's first appearance on a flashcard or quiz card. */
@Composable
fun NewBadge(modifier: Modifier = Modifier) {
    val twinkle = if (reduceMotion()) 1f else rememberInfiniteTransition(label = "new")
        .animateFloat(0.6f, 1.15f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "sparkle").value
    Row(
        modifier.clip(RoundedCornerShape(50)).background(Color(0xFFC6FF3D)).padding(horizontal = 10.dp, vertical = 5.dp)
            .clearAndSetSemantics { contentDescription = "new word" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text("✦", fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.Black, modifier = Modifier.scale(twinkle).rotate(twinkle * 20))
        Text("NEW", fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.Black)
    }
}

/** After a story: its new words with pinyin, meaning and audio. */
@Composable
fun NewWordsRecap(words: List<CoreWord>) {
    Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("new words in this story", style = street(17.sp), color = Street.c.text, modifier = Modifier.weight(1f))
            NewBadge()
        }
        words.forEach { w ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(w.hanzi, fontSize = 28.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text, modifier = Modifier.newWordMark().padding(horizontal = 4.dp))
                HSpacer(12.dp)
                Column(Modifier.weight(1f)) {
                    PinyinText(w.pinyin, 15.sp)
                    Text(w.meaning, fontSize = 14.sp, color = Street.c.secondary, maxLines = 2)
                }
                SpeakButton(w.hanzi, 38.dp, Street.c.sky)
            }
        }
    }
}
