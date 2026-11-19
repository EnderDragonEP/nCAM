package dev.ender.ncam

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.IOException
import java.net.URLEncoder
import java.security.KeyStore
import java.time.Duration
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The background clock sync: while it is on, nCAM joins the camera whenever its Wi-Fi
 * appears (the car starts) and sets its clock, because the camera forgets the time each
 * time it loses power and then names its clips with the wrong date.
 *
 * Settings live here (the service also starts after a reboot, without Flutter). The
 * camera's password is kept encrypted with a key from the Android keystore.
 */
object CameraWatch {
    private const val PREFS = "camera_watch"
    private const val KEY_ALIAS = "ncam_camera_watch"

    class Config(val ssid: String, val password: String, val newClip: Boolean)

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context) = prefs(context).getBoolean("enabled", false)

    fun config(context: Context): Config? {
        val p = prefs(context)
        if (!p.getBoolean("enabled", false)) return null
        val ssid = p.getString("ssid", null) ?: return null
        val password = try {
            p.getString("password", null)?.let { decrypt(it) } ?: ""
        } catch (e: Exception) {
            DiagLog.add("clock sync: could not read the saved password (${e.message})")
            return null
        }
        return Config(ssid, password, p.getBoolean("newClip", true))
    }

    /** Turns it on (or updates the camera's details) and starts the service. */
    fun start(context: Context, ssid: String, password: String, newClip: Boolean) {
        prefs(context).edit()
            .putBoolean("enabled", true)
            .putString("ssid", ssid)
            .putString("password", encrypt(password))
            .putBoolean("newClip", newClip)
            .apply()
        val app = context.applicationContext
        app.startForegroundService(Intent(app, CameraWatchService::class.java))
    }

    fun stop(context: Context) {
        prefs(context).edit().clear().apply()
        val app = context.applicationContext
        app.stopService(Intent(app, CameraWatchService::class.java))
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun encrypt(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String {
        val sealed = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, 12))
        return String(cipher.doFinal(sealed, 12, sealed.size - 12), Charsets.UTF_8)
    }
}

/**
 * Keeps the camera link wanted and sets the clock each time it comes up. Runs as a
 * foreground service (Android requires its notification), with the quietest channel.
 */
class CameraWatchService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var lastState: String? = null
    private var text = ""
    private val linkListener: (String) -> Unit = { s -> main.post { onLink(s) } }
    private var screenReceiver: BroadcastReceiver? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
        DiagLog.init(this)
        createChannels(this)
        text = getString(R.string.watch_waiting, "…")
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                CameraLink.nudge("screen on")
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_ON), RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_ON))
        }
        screenReceiver = receiver
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            NOTIFICATION_ID,
            notification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        val config = CameraWatch.config(this)
        if (config == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        DiagLog.add("clock sync: watching for ${config.ssid}")
        CameraLink.keepWaiting = true
        CameraLink.addListener(linkListener)
        CameraLink.waitFor(this, config.ssid, config.password)
        onLink(CameraLink.state)
        return START_STICKY
    }

    override fun onDestroy() {
        if (running === this) running = null
        CameraLink.removeListener(linkListener)
        CameraLink.keepWaiting = false
        cancelNudge(this)
        screenReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        worker.shutdown()
        DiagLog.add("clock sync: stopped")
        super.onDestroy()
    }

    private fun onLink(state: String) {
        val config = CameraWatch.config(this) ?: return
        val was = lastState
        lastState = state
        when (state) {
            CameraLink.STATE_CONNECTED -> {
                cancelNudge(this)
                standingBy = false
                if (was != CameraLink.STATE_CONNECTED) {
                    update(getString(R.string.watch_setting_clock, config.ssid))
                    worker.execute { syncClock(config) }
                }
            }
            CameraLink.STATE_LOST, CameraLink.STATE_CONNECTING -> {
                if (was == CameraLink.STATE_CONNECTED || was == null) {
                    lostSince = SystemClock.elapsedRealtime()
                }
                update(getString(R.string.watch_waiting, config.ssid))
                scheduleNudge(this)
            }
            CameraLink.STATE_DISCONNECTED -> {
                // Disconnect or Cancel in the app: leave the camera alone for now, but not
                // for good. Once its Wi-Fi has gone (the car is off), wait for it again.
                if (!CameraLink.isWanted && !standingBy) {
                    standingBy = true
                    lastSeen = SystemClock.elapsedRealtime()
                    standbySince = lastSeen
                    lostSince = lastSeen // look often at first
                    DiagLog.add("clock sync: standing by until ${config.ssid} goes away")
                    update(getString(R.string.watch_standby, config.ssid))
                    scheduleNudge(this)
                }
            }
        }
    }

    /** Standing by after Disconnect: has the camera gone away yet? */
    private fun checkStandby() {
        if (!standingBy || CameraLink.isWanted) return
        val now = SystemClock.elapsedRealtime()
        val seen = CameraLink.lookForCamera()
        if (seen == true) lastSeen = now
        val gone = when (seen) {
            null -> now - standbySince >= NO_SCANS_STANDBY_MS
            else -> now - lastSeen >= GONE_MS
        }
        if (!gone) {
            scheduleNudge(this)
            return
        }
        val config = CameraWatch.config(this) ?: return
        standingBy = false
        DiagLog.add("clock sync: ${config.ssid} is gone; waiting for it to start again")
        lostSince = now
        CameraLink.waitFor(this, config.ssid, config.password)
    }

    /** Runs on [worker]. */
    private fun syncClock(config: CameraWatch.Config) {
        val summary = try {
            val result = CameraClock.run(config.newClip)
            val time = LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
            when (result) {
                CameraClock.Result.SYNCED -> getString(R.string.watch_synced, time)
                CameraClock.Result.NEW_CLIP -> getString(R.string.watch_synced_new_clip, time)
                CameraClock.Result.NOT_RECORDING -> {
                    alertNotRecording(this)
                    getString(R.string.watch_synced, time)
                }
            }
        } catch (e: Exception) {
            DiagLog.add("clock sync: failed: ${e.message}")
            getString(R.string.watch_failed, e.message ?: e.javaClass.simpleName)
        }
        main.post { if (lastState == CameraLink.STATE_CONNECTED) update(summary) }
    }

    private fun update(newText: String) {
        if (newText == text) return
        text = newText
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification())
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_WATCH)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(getString(R.string.watch_title))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .build()
    }

    /** Disconnected in the app; waiting for the camera to go away before waiting again. */
    private var standingBy = false
    private var standbySince = 0L
    private var lastSeen = 0L

    companion object {
        /** When the camera went missing, for spacing out the timer. */
        @Volatile
        var lostSince = SystemClock.elapsedRealtime()

        /** Not in the scans for this long: the camera is off (the car has stopped). */
        private const val GONE_MS = 90_000L

        /** Without scans to tell, stand by this long instead. */
        private const val NO_SCANS_STANDBY_MS = 10 * 60_000L

        @Volatile
        private var running: CameraWatchService? = null

        const val CHANNEL_WATCH = "camera_watch"
        const val CHANNEL_ALERTS = "camera_alerts"
        private const val NOTIFICATION_ID = 2
        private const val ALERT_ID = 3
        const val ACTION_NUDGE = "dev.ender.ncam.WATCH_NUDGE"
        const val ACTION_START_RECORDING = "dev.ender.ncam.START_RECORDING"

        fun createChannels(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java)
            // The quietest kind: no sound, no status-bar icon, folded away in the shade.
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_WATCH,
                    context.getString(R.string.channel_watch),
                    NotificationManager.IMPORTANCE_MIN,
                ).apply { setShowBadge(false) }
            )
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ALERTS,
                    context.getString(R.string.channel_alerts),
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }

        /**
         * Looks for the camera again after a while, even with the phone asleep: often at
         * first (a stop on the way), then less and less, so a camera left far behind
         * costs next to nothing.
         */
        fun scheduleNudge(context: Context) {
            val lostFor = SystemClock.elapsedRealtime() - lostSince
            val every = when {
                lostFor < 10 * 60_000L -> 30_000L
                lostFor < 60 * 60_000L -> 2 * 60_000L
                else -> 10 * 60_000L
            }
            val alarms = context.getSystemService(AlarmManager::class.java)
            alarms.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + every,
                nudgeIntent(context),
            )
        }

        fun cancelNudge(context: Context) {
            context.getSystemService(AlarmManager::class.java).cancel(nudgeIntent(context))
        }

        private fun nudgeIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 1,
            Intent(context, CameraWatchActions::class.java).setAction(ACTION_NUDGE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        fun alertNotRecording(context: Context) {
            val start = PendingIntent.getBroadcast(
                context, 2,
                Intent(context, CameraWatchActions::class.java).setAction(ACTION_START_RECORDING),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val n = Notification.Builder(context, CHANNEL_ALERTS)
                .setSmallIcon(android.R.drawable.stat_notify_error)
                .setContentTitle(context.getString(R.string.alert_not_recording))
                .setContentText(context.getString(R.string.alert_not_recording_text))
                .setAutoCancel(true)
                .addAction(
                    Notification.Action.Builder(
                        null as Icon?,
                        context.getString(R.string.alert_start_recording),
                        start,
                    ).build()
                )
                .build()
            context.getSystemService(NotificationManager::class.java).notify(ALERT_ID, n)
        }

        fun clearAlert(context: Context) {
            context.getSystemService(NotificationManager::class.java).cancel(ALERT_ID)
        }

        internal fun onNudgeAlarm(context: Context) {
            // Stay awake long enough for a scan and, if the camera is there, the join.
            val lock = context.getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ncam:camera-watch")
            lock.acquire(15_000)
            val service = running
            if (service != null && service.standingBy) {
                service.checkStandby()
                return
            }
            CameraLink.nudge("timer", quiet = true)
            if (CameraWatch.isEnabled(context) && CameraLink.state != CameraLink.STATE_CONNECTED) {
                scheduleNudge(context)
            }
        }
    }
}

/** The timer and the notification's Start recording button. Not reachable from other apps. */
class CameraWatchActions : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            CameraWatchService.ACTION_NUDGE -> CameraWatchService.onNudgeAlarm(context)
            CameraWatchService.ACTION_START_RECORDING -> {
                val pending = goAsync()
                Thread {
                    try {
                        val ok = CameraClock.startRecording()
                        if (ok) CameraWatchService.clearAlert(context)
                    } catch (e: Exception) {
                        DiagLog.add("clock sync: start recording failed: ${e.message}")
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }
}

/** Starts the background clock sync again after a reboot or an app update. */
class CameraWatchBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!CameraWatch.isEnabled(context)) return
        try {
            context.startForegroundService(Intent(context, CameraWatchService::class.java))
        } catch (e: Exception) {
            DiagLog.init(context)
            DiagLog.add("clock sync: could not start after ${intent.action}: ${e.message}")
        }
    }
}

/** The camera commands the clock sync needs. Blocking: call from a worker thread. */
object CameraClock {
    private const val BASE = "http://192.168.1.254"
    private val NAME = Regex("""(\d{4})_(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_(\d+)[A-Za-z]\.TS""")

    enum class Result { SYNCED, NEW_CLIP, NOT_RECORDING }

    private fun command(query: String): Pair<Int, Long> {
        val body = String(CameraLink.get("$BASE/?custom=1&$query", emptyMap(), 10_000, 64 * 1024).body)
        fun tag(name: String) =
            Regex("<$name>\\s*(-?\\d+)\\s*</$name>").find(body)?.groupValues?.get(1)?.toLongOrNull()
        val status = tag("Status") ?: throw IOException("unexpected reply to $query")
        return status.toInt() to (tag("Value") ?: 0)
    }

    private fun recordingSeconds() = command("cmd=2016").second

    private fun pause(ms: Long) = Thread.sleep(ms)

    /**
     * Sets the camera's clock to the phone's. With [newClip], a clip the camera started
     * with the wrong time is cut short (recording stops and starts again, about two
     * seconds), so the rest of the drive is named correctly.
     */
    fun run(newClip: Boolean): Result {
        // The link is up a moment before the camera's web server answers.
        var tries = 0
        while (true) {
            try {
                recordingSeconds()
                break
            } catch (e: IOException) {
                if (++tries >= 6) throw e
                pause(1_000)
            }
        }
        val now = LocalDateTime.now()
        val date = now.format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
        val time = URLEncoder.encode(now.format(DateTimeFormatter.ofPattern("HH:mm:ss")), "UTF-8")
        val (dateStatus, _) = command("cmd=3005&str=$date")
        val (timeStatus, _) = command("cmd=3006&str=$time")
        if (dateStatus != 0 || timeStatus != 0) {
            throw IOException("the camera refused the time (status $dateStatus/$timeStatus)")
        }
        DiagLog.add("clock sync: camera clock set to $date ${now.toLocalTime().withNano(0)}")
        if (!newClip || FastMode.phase != FastMode.IDLE) return Result.SYNCED

        val seconds = recordingSeconds()
        if (seconds <= 0) return Result.SYNCED
        val misnamedBy = misnamedBy(now, seconds) ?: return Result.SYNCED
        if (misnamedBy.abs() <= Duration.ofSeconds(90)) return Result.SYNCED
        DiagLog.add("clock sync: the clip being recorded is named ${misnamedBy.toMinutes()} min off; starting a new one")
        command("cmd=2001&par=0")
        for (i in 0 until 10) {
            if (recordingSeconds() == 0L) break
            pause(500)
        }
        return if (startRecording()) Result.NEW_CLIP else Result.NOT_RECORDING
    }

    /** How far the name of the clip being recorded is from when it really started. */
    private fun misnamedBy(now: LocalDateTime, seconds: Long): Duration? {
        val page = String(CameraLink.get("$BASE/Novatek/Movie/", emptyMap(), 10_000, 4 * 1024 * 1024).body)
        // The newest clip has the highest number.
        val newest = NAME.findAll(page).maxByOrNull { it.groupValues[7].toInt() } ?: return null
        val g = newest.groupValues
        val named = try {
            LocalDateTime.of(g[1].toInt(), g[2].toInt(), g[3].toInt(), g[4].toInt(), g[5].toInt(), g[6].toInt())
        } catch (_: Exception) {
            return null
        }
        return Duration.between(now.minusSeconds(seconds), named)
    }

    /** Starts recording and checks that it runs, trying twice. */
    fun startRecording(): Boolean {
        repeat(2) {
            command("cmd=2001&par=1")
            repeat(12) {
                pause(500)
                if (recordingSeconds() > 0) {
                    DiagLog.add("clock sync: recording again")
                    return true
                }
            }
        }
        DiagLog.add("clock sync: recording did NOT restart")
        return false
    }
}
