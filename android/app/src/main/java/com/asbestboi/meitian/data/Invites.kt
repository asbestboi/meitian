package com.asbestboi.meitian.data

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.asbestboi.meitian.MainActivity
import com.asbestboi.meitian.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.OnlineChallenge
import uniffi.meitian_core.SoundId
import uniffi.meitian_core.inviteText
import uniffi.meitian_core.newInvites

/**
 * Somebody invites the learner to a battle or a party: a banner while the app is open, a notification otherwise.
 * The inbox is polled (there's no push service): every few seconds while the app is open, for a while after it goes
 * to the background, and then about every 15 minutes by a job.
 */
object Invites {
    /** Shown at the top of the app until it's answered or dismissed. */
    var banner by mutableStateOf<OnlineChallenge?>(null)
    /** Tapped in a notification: the room to join once the app is up. */
    var opened by mutableStateOf<String?>(null)
    /** In a battle: no banners. */
    var busy = false

    private const val CHANNEL = "invites"
    private const val JOB = 77
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var afterwards: Job? = null

    private fun prefs(c: Context) = c.getSharedPreferences("invites", Context.MODE_PRIVATE)
    private fun told(c: Context): List<String> = prefs(c).getString("told", "")!!.split(",").filter { it.isNotEmpty() }

    /** Looks for invitations nobody has told the learner about yet. */
    suspend fun poll(c: Context, foreground: Boolean) {
        Online.init(c)
        if (!Online.signedIn) return
        Online.refreshInbox()
        val inbox = Online.inbox ?: return
        // an invitation that's gone (answered, expired, taken back) takes its banner and notification along
        val open = inbox.challenges.map { it.room }
        if (banner != null && banner?.room !in open) banner = null
        if (foreground && busy) return
        val told = told(c)
        val fresh = newInvites(inbox, told)
        val nm = c.getSystemService(NotificationManager::class.java)
        told.filter { it !in open }.forEach { nm.cancel(it, JOB) }
        prefs(c).edit().putString("told", (told.filter { it in open } + fresh.map { it.room }).takeLast(50).joinToString(",")).apply()
        val newest = fresh.firstOrNull() ?: return
        if (foreground) { banner = newest; Sfx.play(SoundId.GO) }
        else if (prefs(c).getBoolean("on", true)) fresh.forEach { notify(c, it) }
    }

    private fun notify(c: Context, invite: OnlineChallenge) {
        if (!Reminders.canNotify(c)) return
        val nm = c.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Battle invitations", NotificationManager.IMPORTANCE_HIGH))
        val text = inviteText(invite)
        val open = PendingIntent.getActivity(c, invite.room.hashCode(),
            Intent(c, MainActivity::class.java).putExtra("invite", invite.room).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        nm.notify(invite.room, JOB, Notification.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_notify)
            .setContentTitle(text.title).setContentText(text.body).setContentIntent(open).setAutoCancel(true)
            .setCategory(Notification.CATEGORY_SOCIAL).build())
    }

    /** The app went to the background: keep an eye on the inbox for ten minutes, then leave it to the job. */
    fun background(c: Context, on: Boolean) {
        val app = c.applicationContext
        prefs(app).edit().putBoolean("on", on).apply()
        afterwards?.cancel()
        if (!on || !Online.signedIn) { app.getSystemService(JobScheduler::class.java).cancel(JOB); return }
        schedule(app)
        afterwards = scope.launch { repeat(30) { delay(20_000); poll(app, foreground = false) } }
    }

    fun foreground() { afterwards?.cancel(); afterwards = null }

    private fun schedule(c: Context) {
        val js = c.getSystemService(JobScheduler::class.java)
        if (js.getPendingJob(JOB) != null) return
        js.schedule(JobInfo.Builder(JOB, ComponentName(c, InviteJob::class.java)).setPeriodic(15 * 60_000L)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).build())
    }
}

/** The 15-minute check. */
class InviteJob : JobService() {
    private var work: Job? = null
    override fun onStartJob(params: JobParameters): Boolean {
        work = CoroutineScope(Dispatchers.Main).launch {
            runCatching { Invites.poll(applicationContext, foreground = false) }
            jobFinished(params, false)
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { work?.cancel(); return false }
}
