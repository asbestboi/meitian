package com.asbestboi.meitian.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import uniffi.meitian_core.titleColors

/** The colours of a title cosmetic (decided by the core), left to right. */
@Composable
fun titleBrush(id: String): Brush = remember(id) {
    val c = titleColors(id).map(::hexColor)
    if (c.size == 1) SolidColor(c[0]) else Brush.horizontalGradient(c)
}

/** A name (or a title) in its title's colours. */
@Composable
fun TitledText(text: String, titleId: String, size: TextUnit, modifier: Modifier = Modifier, weight: FontWeight = FontWeight.ExtraBold) {
    Text(text, modifier, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TextStyle(brush = titleBrush(titleId), fontSize = size, fontWeight = weight))
}

/** The dark plate names sit on, so every title's colours can be read on every frame. */
@Composable
fun Modifier.namePlate(): Modifier = clip(RoundedCornerShape(12.dp)).background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 10.dp, vertical = 5.dp)
