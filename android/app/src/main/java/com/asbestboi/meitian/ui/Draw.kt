package com.asbestboi.meitian.ui

import android.graphics.Bitmap
import android.graphics.BlendMode
import android.graphics.BlendModeColorFilter
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Draws the core's draw commands (core/src/draw.rs): hit effects, auras and arena scenery. One per canvas. */
class OpsRenderer {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; isFakeBoldText = true }
    private val path = Path()
    private val box = RectF()

    private fun argb(b: ByteBuffer): Int {
        val r = b.float; val g = b.float; val bl = b.float; val a = b.float
        return android.graphics.Color.argb((a * 255).toInt().coerceIn(0, 255), (r * 255).toInt().coerceIn(0, 255), (g * 255).toInt().coerceIn(0, 255), (bl * 255).toInt().coerceIn(0, 255))
    }

    private fun Paint.add(on: Boolean): Paint = apply { xfermode = if (on) PLUS else null }

    /** [density]: pixels per point. */
    fun draw(canvas: Canvas, ops: ByteArray, density: Float) {
        if (ops.isEmpty()) return
        val b = ByteBuffer.wrap(ops).order(ByteOrder.LITTLE_ENDIAN)
        canvas.save()
        val w = canvas.width.toFloat(); val h = canvas.height.toFloat()
        canvas.scale(density, density)
        while (b.remaining() >= 4) when (b.float.toInt()) {
            1 -> {
                val x = b.float; val y = b.float; val r = b.float
                val c = argb(b); glow.add(b.float > 0f)
                glow.alpha = c ushr 24
                glow.colorFilter = tint(c or (0xFF shl 24))
                box.set(x - r, y - r, x + r, y + r)
                canvas.drawBitmap(soft, null, box, glow)
            }
            2 -> {
                val x = b.float; val y = b.float; val r = b.float
                fill.color = argb(b); fill.add(b.float > 0f)
                canvas.drawCircle(x, y, r, fill)
            }
            3 -> {
                val x = b.float; val y = b.float; val r = b.float
                line.strokeWidth = b.float; line.color = argb(b); line.add(b.float > 0f)
                canvas.drawCircle(x, y, r, line)
            }
            4 -> {
                val x1 = b.float; val y1 = b.float; val x2 = b.float; val y2 = b.float
                line.strokeWidth = b.float; line.color = argb(b); line.add(b.float > 0f)
                canvas.drawLine(x1, y1, x2, y2, line)
            }
            5 -> {
                val n = b.float.toInt()
                val top = argb(b); val bottom = argb(b)
                val y1 = b.float; val y2 = b.float
                fill.add(b.float > 0f)
                readPath(b, n, true)
                if (top == bottom) fill.color = top
                else { fill.color = android.graphics.Color.BLACK; fill.shader = LinearGradient(0f, y1, 0f, if (y2 > y1) y2 else y1 + 0.1f, top, bottom, Shader.TileMode.CLAMP) }
                canvas.drawPath(path, fill)
                fill.shader = null
            }
            6 -> {
                val ch = b.float.toInt(); val x = b.float; val y = b.float
                text.textSize = b.float
                val deg = b.float
                text.color = android.graphics.Color.argb((b.float * 255).toInt().coerceIn(0, 255), 0xFF, 0xD9, 0x6A)
                canvas.save(); canvas.rotate(deg, x, y)
                canvas.drawText(String(Character.toChars(ch)), x, y + text.textSize * 0.36f, text)
                canvas.restore()
            }
            7 -> { fill.color = argb(b); fill.add(false); canvas.drawRect(0f, 0f, w / density, h / density, fill) }
            8 -> {
                val n = b.float.toInt()
                line.strokeWidth = b.float; line.color = argb(b); line.add(b.float > 0f)
                readPath(b, n, false)
                canvas.drawPath(path, line)
            }
            else -> { canvas.restore(); return }   // a newer core: stop rather than draw garbage
        }
        canvas.restore()
    }

    private fun readPath(b: ByteBuffer, n: Int, close: Boolean) {
        path.rewind()
        for (i in 0 until n) { val x = b.float; val y = b.float; if (i == 0) path.moveTo(x, y) else path.lineTo(x, y) }
        if (close) path.close()
    }

    private val tints = HashMap<Int, android.graphics.ColorFilter>()
    private fun tint(c: Int): android.graphics.ColorFilter {
        if (tints.size > 256) tints.clear()
        return tints.getOrPut(c) {
            if (Build.VERSION.SDK_INT >= 29) BlendModeColorFilter(c, BlendMode.SRC_IN) else PorterDuffColorFilter(c, PorterDuff.Mode.SRC_IN)
        }
    }

    private companion object {
        val PLUS = PorterDuffXfermode(PorterDuff.Mode.ADD)

        /** A soft white dot, tinted for every glow (cheaper than a gradient per particle). */
        val soft: Bitmap by lazy {
            Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888).also {
                val p = Paint(Paint.ANTI_ALIAS_FLAG)
                p.shader = RadialGradient(48f, 48f, 48f, android.graphics.Color.WHITE, android.graphics.Color.TRANSPARENT, Shader.TileMode.CLAMP)
                Canvas(it).drawCircle(48f, 48f, 48f, p)
            }
        }
    }
}
