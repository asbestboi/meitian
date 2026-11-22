package com.asbestboi.meitian.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.asbestboi.meitian.MainActivity
import com.asbestboi.meitian.R
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/** A small copy of today's state that the reminder and the home-screen widget read without loading the app. */
object Snapshot {
    private fun prefs(c: Context) = c.getSharedPreferences("snapshot", Context.MODE_PRIVATE)

    data class Data(
        val day: String, val name: String, val streak: Int, val xpToday: Int, val active: Boolean,
        val nextEmoji: String, val nextTitle: String, val nextXp: Int, val todo: String,
        val reminderOn: Boolean, val hour: Int, val minute: Int,
    )

    fun write(c: Context, d: Data) {
        prefs(c).edit().apply {
            putString("day", d.day); putString("name", d.name); putInt("streak", d.streak); putInt("xp", d.xpToday)
            putBoolean("active", d.active); putString("nextEmoji", d.nextEmoji); putString("nextTitle", d.nextTitle)
            putInt("nextXp", d.nextXp); putString("todo", d.todo)
            putBoolean("rem", d.reminderOn); putInt("remH", d.hour); putInt("remM", d.minute)
        }.apply()
    }

    fun read(c: Context): Data? {
        val p = prefs(c)
        val day = p.getString("day", null) ?: return null
        return Data(day, p.getString("name", "")!!, p.getInt("streak", 0), p.getInt("xp", 0), p.getBoolean("active", false),
            p.getString("nextEmoji", "🔥")!!, p.getString("nextTitle", "")!!, p.getInt("nextXp", 30), p.getString("todo", "")!!,
            p.getBoolean("rem", false), p.getInt("remH", 19), p.getInt("remM", 0))
    }

    fun clear(c: Context) = prefs(c).edit().clear().apply()
}

/** Daily reminder: an inexact repeating alarm that posts a notification unless today's practice is done. */
object Reminders {
    private const val CHANNEL = "daily"

    private fun intent(c: Context) = PendingIntent.getBroadcast(
        c, 0, Intent(c, ReminderReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun schedule(c: Context, hour: Int, minute: Int) {
        val now = LocalDateTime.now()
        var at = now.toLocalDate().atTime(hour, minute)
        if (!at.isAfter(now)) at = at.plusDays(1)
        val millis = at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val am = c.getSystemService(AlarmManager::class.java)
        am.setInexactRepeating(AlarmManager.RTC_WAKEUP, millis, AlarmManager.INTERVAL_DAY, intent(c))
    }

    fun cancel(c: Context) {
        c.getSystemService(AlarmManager::class.java).cancel(intent(c))
    }

    fun canNotify(c: Context) = Build.VERSION.SDK_INT < 33 ||
        c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun notify(c: Context) {
        val snap = Snapshot.read(c)
        // already practiced today: nothing to nag about
        if (snap != null && snap.day == LocalDate.now().toString() && snap.active) return
        if (!canNotify(c)) return
        val nm = c.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Daily reminder", NotificationManager.IMPORTANCE_DEFAULT))
        val name = snap?.name.orEmpty()
        val lines = listOf(
            "你好${if (name.isEmpty()) "" else "，$name"}! 👋" to "Your new words are waiting. Five minutes, let's go!",
            "今天的挑战 🎯" to "Today's quests are ready. Grab some coins!",
            "加油！🔥" to if ((snap?.streak ?: 0) > 0) "Keep your ${snap?.streak}-day streak alive. Your words miss you." else "Start a new streak today. Your words miss you.",
        )
        val (title, body) = lines[LocalDate.now().dayOfWeek.value % lines.size]
        val open = PendingIntent.getActivity(c, 1, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE)
        val n = android.app.Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_notify).setContentTitle(title).setContentText(body)
            .setContentIntent(open).setAutoCancel(true).build()
        nm.notify(1, n)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = Reminders.notify(context)
}

/** Alarms don't survive a reboot: set the reminder again. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val s = Snapshot.read(context) ?: return
        if (s.reminderOn) Reminders.schedule(context, s.hour, s.minute)
    }
}
