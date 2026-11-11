package dev.ender.ncam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Environment
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloads queued files over the camera link, one at a time, and keeps going with the
 * screen off or the app in the background.
 *
 * Each file is first written to a private ".part" file so an interrupted download resumes
 * with an HTTP Range request, then moved into the phone's gallery (Movies/nCAM).
 */
class DownloadService : Service() {
    private var worker: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    @Volatile private var currentConn: HttpURLConnection? = null
    @Volatile private var currentJob: Downloads.Job? = null
    private var lastNotify = 0L

    /** Not worth retrying: the camera answered, and the answer was "no". */
    private class FatalException(message: String) : IOException(message)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW)
        )
        Downloads.onCancel = { job ->
            if (job === currentJob) {
                worker?.interrupt()
                // Closing the connection unblocks a read that is waiting on the camera.
                Thread { try { currentConn?.disconnect() } catch (_: Exception) {} }.start()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            NOTIFICATION_ID, buildNotification(null),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
        synchronized(this) {
            if (worker == null) {
                acquireLocks()
                worker = Thread({ runQueue() }, "ncam-download").also { it.start() }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Downloads.onCancel = null
        releaseLocks()
        super.onDestroy()
    }

    private fun acquireLocks() {
        if (wakeLock != null) return
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ncam:download").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
        val wm = applicationContext.getSystemService(WifiManager::class.java)
        @Suppress("DEPRECATION")
        wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ncam:download").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseLocks() {
        try { wakeLock?.release() } catch (_: Exception) {}
        try { wifiLock?.release() } catch (_: Exception) {}
        wakeLock = null
        wifiLock = null
    }

    private fun runQueue() {
        try {
            var resumeTried = false
            while (true) {
                var job = Downloads.nextQueued()
                if (job == null) {
                    if (!resumeTried && FastMode.pausedByApp(this)) {
                        // Queue finished (or cancelled): recording goes back on before the
                        // service is allowed to stop.
                        resumeTried = true
                        showText("Restarting recording…")
                        FastMode.resume(this)
                        continue
                    }
                    job = synchronized(this) {
                        Downloads.nextQueued() ?: run {
                            // Decided under the lock: an enqueue arriving after this point
                            // sees no worker and starts a new one.
                            worker = null
                            releaseLocks()
                            stopForeground(STOP_FOREGROUND_REMOVE)
                            stopSelf()
                            null
                        }
                    } ?: break
                }
                resumeTried = false
                if (FastMode.isEnabled(this)) {
                    FastMode.pause(this)
                } else if (FastMode.pausedByApp(this)) {
                    // Fast download was switched off while the queue was running.
                    FastMode.resume(this)
                }
                currentJob = job
                Downloads.changed()
                try {
                    runJob(job)
                } catch (e: Exception) {
                    job.error = e.message ?: e.javaClass.simpleName
                    job.state = Downloads.FAILED
                }
                Thread.interrupted() // clear a late cancel signal before the next job
                currentJob = null
                job.bytesPerSecond = 0
                Downloads.changed()
            }
        } catch (e: Throwable) {
            synchronized(this) {
                worker = null
                releaseLocks()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            throw e
        }
    }

    private fun partialFile(job: Downloads.Job): File {
        val dir = File(getExternalFilesDir(null) ?: filesDir, "partial").apply { mkdirs() }
        return File(dir, job.name + ".part")
    }

    private fun runJob(job: Downloads.Job) {
        val partial = partialFile(job)
        var failures = 0
        while (true) {
            if (job.cancelRequested) {
                partial.delete()
                job.state = Downloads.CANCELLED
                return
            }
            val before = partial.length()
            try {
                job.state = Downloads.RUNNING
                job.received = before
                notifyProgress(job, force = true)
                fetch(job, partial)
                break
            } catch (e: FatalException) {
                partial.delete()
                job.error = e.message
                job.state = Downloads.FAILED
                return
            } catch (e: Exception) {
                if (job.cancelRequested) continue
                // Any progress means the link works; start counting failures afresh.
                if (partial.length() > before) failures = 0
                failures++
                job.error = e.message ?: e.javaClass.simpleName
                job.bytesPerSecond = 0
                if (failures > RETRY_DELAYS_MS.size) {
                    // The partial file is kept, so a manual retry resumes from here.
                    job.state = Downloads.FAILED
                    return
                }
                job.state = Downloads.WAITING
                Downloads.changed()
                try {
                    Thread.sleep(RETRY_DELAYS_MS[failures - 1])
                } catch (_: InterruptedException) {
                }
            }
        }
        job.error = null
        job.bytesPerSecond = 0
        publish(job, partial)
        job.state = Downloads.DONE
    }

    /** One attempt. Appends to [partial] from wherever it ends. */
    private fun fetch(job: Downloads.Job, partial: File) {
        var offset = partial.length()
        if (job.total in 1..offset) {
            if (offset == job.total) return
            partial.delete() // longer than the file on the camera: start over
            offset = 0
        }
        val network = CameraLink.network ?: throw IOException("not connected to the camera")
        val conn = network.openConnection(URL(job.url)) as HttpURLConnection
        currentConn = conn
        try {
            conn.connectTimeout = 10_000
            conn.readTimeout = 20_000
            conn.useCaches = false
            conn.setRequestProperty("Connection", "close")
            conn.setRequestProperty("Accept-Encoding", "identity")
            if (offset > 0) conn.setRequestProperty("Range", "bytes=$offset-")

            val code = conn.responseCode
            val type = conn.contentType.orEmpty()
            // The camera serves its "Page Not found" page with status 200.
            if (type.startsWith("text/")) throw FatalException("the camera no longer has this file")
            if (code == 416) throw FatalException("the file on the camera is shorter than expected")
            if (code != 200 && code != 206) throw IOException("HTTP $code")
            if (offset > 0 && code == 200) {
                // Range was ignored; the body starts from byte 0 again.
                offset = 0
            }
            val length = conn.contentLengthLong
            if (length >= 0) job.total = offset + length

            FileOutputStream(partial, offset > 0).use { out ->
                conn.inputStream.use { input ->
                    val buf = ByteArray(256 * 1024)
                    var windowStart = SystemClock.elapsedRealtime()
                    var windowBytes = 0L
                    var received = offset
                    while (true) {
                        if (job.cancelRequested) throw IOException("cancelled")
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        received += n
                        windowBytes += n
                        job.received = received
                        val now = SystemClock.elapsedRealtime()
                        if (now - windowStart >= 1000) {
                            job.bytesPerSecond = windowBytes * 1000 / (now - windowStart)
                            windowStart = now
                            windowBytes = 0
                        }
                        notifyProgress(job, force = false)
                    }
                }
            }
            if (job.total > 0 && partial.length() < job.total) {
                throw IOException("connection closed early")
            }
        } finally {
            currentConn = null
            conn.disconnect()
        }
    }

    /** Moves the finished file into the gallery: Movies/nCAM for video, Download/nCAM otherwise. */
    private fun publish(job: Downloads.Job, partial: File) {
        val lower = job.name.lowercase()
        val isVideo = lower.endsWith(".ts") || lower.endsWith(".mp4") || lower.endsWith(".mov")
        val collection =
            if (isVideo) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val folder =
            (if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_DOWNLOADS) + "/nCAM"
        val mime = when {
            lower.endsWith(".ts") -> "video/mp2t"
            lower.endsWith(".mp4") -> "video/mp4"
            lower.endsWith(".mov") -> "video/quicktime"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            else -> "application/octet-stream"
        }
        val resolver = contentResolver
        // Replace an earlier copy of the same file instead of creating "name (1)".
        try {
            resolver.delete(
                collection,
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                arrayOf(job.name, "$folder/"),
            )
        } catch (_: Exception) {
            // A copy this app does not own (e.g. from before a reinstall) stays; Android
            // then stores the new one under a numbered name.
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, job.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("could not create the gallery entry")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                partial.inputStream().use { it.copyTo(out, 1024 * 1024) }
            } ?: throw IOException("could not open the gallery entry")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw IOException("could not save to the gallery: ${e.message}")
        }
        partial.delete()
    }

    private fun notifyProgress(job: Downloads.Job, force: Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastNotify < 400) return
        lastNotify = now
        Downloads.changed()
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(job))
    }

    private fun showText(text: String) {
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentTitle(text)
            .setProgress(0, 0, true)
            .build()
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, n)
    }

    private fun buildNotification(job: Downloads.Job?): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (job == null) {
            builder.setContentTitle("Preparing download").setProgress(0, 0, true)
        } else {
            val position = Downloads.doneCount() + 1
            builder.setContentTitle("Downloading $position of ${Downloads.totalCount()}")
                .setContentText(
                    if (FastMode.phase == FastMode.PAUSED) "${job.name} · recording paused"
                    else job.name
                )
            if (job.total > 0) {
                builder.setProgress(1000, (job.received * 1000 / job.total).toInt(), false)
            } else {
                builder.setProgress(0, 0, true)
            }
        }
        return builder.build()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION_ID = 1
        private val RETRY_DELAYS_MS = longArrayOf(2_000, 4_000, 8_000, 15_000, 30_000, 30_000)

        /** Names and sizes of files this app has saved to the gallery. */
        fun localFiles(context: Context): Map<String, Long> {
            val result = HashMap<String, Long>()
            val collections = listOf(
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) to
                    Environment.DIRECTORY_MOVIES + "/nCAM/",
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) to
                    Environment.DIRECTORY_DOWNLOADS + "/nCAM/",
            )
            for ((collection, folder) in collections) {
                context.contentResolver.query(
                    collection,
                    arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE),
                    "${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                    arrayOf(folder),
                    null,
                )?.use { c ->
                    while (c.moveToNext()) {
                        val name = c.getString(0) ?: continue
                        result[name] = c.getLong(1)
                    }
                }
            }
            return result
        }
    }
}
