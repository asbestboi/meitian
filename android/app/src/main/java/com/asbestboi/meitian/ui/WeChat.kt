package com.asbestboi.meitian.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import uniffi.meitian_core.textParts
import uniffi.meitian_core.wechatEmoji
import uniffi.meitian_core.wechatImage

/** WeChat's own emoji pictures, for codes like "[捂脸]". */
object WeChat {
    private val cache = HashMap<String, ImageBitmap?>()

    fun image(code: String): ImageBitmap? {
        if (!code.startsWith("[")) return null
        return cache.getOrPut(code) { wechatImage(code)?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    }

    /** Pictures for every code in [text], sized to [size] text. */
    fun inline(text: String, size: TextUnit): Map<String, InlineTextContent> =
        textParts(text).filter { it.emoji }.map { it.text }.distinct().associateWith { code ->
            InlineTextContent(Placeholder(size * 1.3f, size * 1.3f, PlaceholderVerticalAlign.TextCenter)) { Picture(code, Modifier.fillMaxSize()) }
        }

    @Composable
    fun Picture(code: String, modifier: Modifier) {
        val img = remember(code) { image(code) } ?: return
        Image(img, contentDescription = wechatEmoji(code) ?: code, modifier = modifier, filterQuality = FilterQuality.High)
    }
}

/** A chat message's plain text with WeChat's pictures in it. */
@Composable
fun ChatText(text: String, fontSize: TextUnit, color: Color, fontWeight: FontWeight? = null) {
    val parts = remember(text) { textParts(text) }
    val shown: AnnotatedString = remember(text) { buildAnnotatedString { parts.forEach { if (it.emoji) appendInlineContent(it.text, wechatEmoji(it.text) ?: it.text) else append(it.text) } } }
    val inline = remember(text, fontSize) { WeChat.inline(text, fontSize) }
    Text(shown, fontSize = fontSize, color = color, fontWeight = fontWeight, inlineContent = inline)
}
