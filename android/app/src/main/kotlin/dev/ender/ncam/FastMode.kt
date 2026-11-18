package dev.ender.ncam

import android.content.Context
import java.io.IOException
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Opt-in "fast download": puts the camera in playback mode, which stops recording and
 * roughly doubles the transfer speed (measured 3.1 vs 1.4 MB/s), then puts it back.
 *
 * The camera does NOT resume recording by itself after playback mode, so this object owns
 * the restart. "We paused it" is written to disk before the camera is touched; if the app
 * dies in between, the next connection finds the note and restarts recording.
 */
object FastMode {
    const val IDLE = "idle"
    const val PAUSING = "pausing"
    const val PAUSED = "paused"
    const val RESUMING = "resuming"
    const val FAILED = "failed"

    private const val PREFS = "ncam_fast_mode"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_PAUSED = "paused_by_app"
    private const val BASE = "http://192.168.1.254/?custom=1"

    private const val CMD_RECORD = 2001
    private const val CMD_RECORDING_TIME = 2016
    private const val CMD_MODE = 3001
    private const val MODE_MOVIE = 1
    private const val MODE_PLAYBACK = 2

    @Volatile var phase: String = IDLE
        private set
    /** Technical reason for [FAILED]; the app builds the sentence around it. */
    @Volatile var message: String? = null
        private set

    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    fun addListener(l: () -> Unit) = listeners.add(l)
    fun removeListener(l: () -> Unit) = listeners.remove(l)

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context) = prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        listeners.forEach { it() }
    }

    /** True while recording is off because this app turned it off. */
    fun pausedByApp(context: Context) = prefs(context).getBoolean(KEY_PAUSED, false)

    private fun setPausedByApp(context: Context, paused: Boolean) {
        // commit(): must be on disk before the camera is told to stop.
        prefs(context).edit().putBoolean(KEY_PAUSED, paused).commit()
    }

    fun snapshot(context: Context): Map<String, Any?> = mapOf(
        "enabled" to isEnabled(context),
        "phase" to if (phase == IDLE && pausedByApp(context)) PAUSED else phase,
        "message" to message,
    )

    private fun setPhase(p: String, msg: String? = null) {
        if (p != phase) DiagLog.add("fast download: $p" + (msg?.let { " ($it)" } ?: ""))
        phase = p
        message = msg
        listeners.forEach { it() }
    }

    private class Reply(val status: Int, val value: Long)

    private fun command(cmd: Int, par: Int? = null, timeoutMs: Int = 10_000): Reply {
        val url = BASE + "&cmd=$cmd" + (if (par != null) "&par=$par" else "")
        val body = String(CameraLink.get(url, emptyMap(), timeoutMs, 64 * 1024).body)
        fun tag(name: String) =
            Regex("<$name>\\s*(-?\\d+)\\s*</$name>").find(body)?.groupValues?.get(1)?.toLongOrNull()
        val status = tag("Status") ?: throw IOException("unexpected reply to command $cmd")
        return Reply(status.toInt(), tag("Value") ?: 0)
    }

    private fun recordingSeconds(): Long = command(CMD_RECORDING_TIME).value

    /**
     * Stops recording if the camera is recording. Blocking. Never throws: when anything
     * goes wrong the download simply carries on at normal speed.
     */
    @Synchronized
    fun pause(context: Context) {
        if (pausedByApp(context)) {
            setPhase(PAUSED)
            return
        }
        try {
            if (recordingSeconds() <= 0) return // nothing to pause, nothing to restore
            setPhase(PAUSING)
            setPausedByApp(context, true)
            val reply = command(CMD_MODE, MODE_PLAYBACK, 15_000)
            if (reply.status != 0) {
                // Refused: make sure recording really is still on, then forget the note.
                resume(context)
                return
            }
            Thread.sleep(1500)
            setPhase(PAUSED)
        } catch (e: Exception) {
            // Unknown whether the camera stopped. Keep the note so resume() checks later.
            setPhase(if (pausedByApp(context)) PAUSED else IDLE)
        }
    }

    /**
     * Puts the camera back in movie mode and makes sure it records again. Blocking; keeps
     * trying for about two minutes. Returns true once recording is confirmed.
     */
    @Synchronized
    fun resume(context: Context): Boolean {
        if (!pausedByApp(context)) {
            if (phase != IDLE) setPhase(IDLE)
            return true
        }
        setPhase(RESUMING)
        var lastError = "the camera did not answer"
        for (delay in RESUME_DELAYS_MS) {
            try {
                if (restoreOnce()) {
                    setPausedByApp(context, false)
                    setPhase(IDLE)
                    return true
                }
                lastError = "the camera did not start recording"
            } catch (e: Exception) {
                lastError = e.message ?: e.javaClass.simpleName
            }
            try {
                Thread.sleep(delay)
            } catch (_: InterruptedException) {
            }
        }
        // Only the technical reason: the app writes the sentence around it in the
        // user's language.
        setPhase(FAILED, lastError)
        return false
    }

    private fun restoreOnce(): Boolean {
        if (recordingSeconds() > 0) return true
        // Slow command: it took 5 s to answer on the real camera.
        command(CMD_MODE, MODE_MOVIE, 20_000)
        // It did not restart by itself in testing, but give firmware that does a moment.
        Thread.sleep(2000)
        if (recordingSeconds() > 0) return true
        command(CMD_RECORD, 1)
        for (i in 0 until 3) {
            Thread.sleep(1500)
            if (recordingSeconds() > 0) return true
        }
        return false
    }

    private val RESUME_DELAYS_MS = longArrayOf(2_000, 4_000, 8_000, 15_000, 20_000, 30_000, 30_000)
}
