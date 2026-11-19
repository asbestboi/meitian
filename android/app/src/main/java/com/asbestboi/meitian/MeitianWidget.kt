package com.asbestboi.meitian

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.asbestboi.meitian.data.Snapshot
import java.time.LocalDate

/** Home-screen widget: streak, today's XP toward the next milestone, and what to do next. */
class MeitianWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, views(context)) }
    }

    companion object {
        /** Redraw every placed widget from the latest snapshot. */
        fun update(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, MeitianWidget::class.java))
            if (ids.isEmpty()) return
            val v = views(context)
            ids.forEach { manager.updateAppWidget(it, v) }
        }

        private fun views(c: Context): RemoteViews {
            val v = RemoteViews(c.packageName, R.layout.widget)
            val s = Snapshot.read(c)
            val today = LocalDate.now().toString()
            // the snapshot is from the last time the app saved; a new day starts at 0 XP
            val fresh = s != null && s.day == today
            val xp = if (fresh) s!!.xpToday else 0
            val streak = s?.streak ?: 0
            v.setTextViewText(R.id.widget_streak, "🔥 $streak")
            v.setTextViewText(R.id.widget_xp, "$xp XP today")
            if (fresh && s != null) {
                v.setTextViewText(R.id.widget_milestone, "next: ${s.nextEmoji} ${s.nextTitle} at ${s.nextXp} XP")
                v.setProgressBar(R.id.widget_bar, 100, (xp * 100 / s.nextXp.coerceAtLeast(1)).coerceIn(0, 100), false)
                v.setTextViewText(R.id.widget_todo, s.todo)
            } else {
                v.setTextViewText(R.id.widget_milestone, "next: 🔥 warmed up at 30 XP")
                v.setProgressBar(R.id.widget_bar, 100, 0, false)
                v.setTextViewText(R.id.widget_todo, if (streak > 0) "keep your streak alive ✦ today's words are waiting" else "today's words are waiting ✦")
            }
            val open = PendingIntent.getActivity(c, 2, Intent(c, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
            v.setOnClickPendingIntent(R.id.widget_root, open)
            return v
        }
    }
}
