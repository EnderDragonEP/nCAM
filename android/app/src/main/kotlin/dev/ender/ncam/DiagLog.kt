package dev.ender.ncam

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A small rolling log of everything the app says to the camera and what it answers, kept
 * on the phone so a problem seen on the road can be diagnosed afterwards.
 *
 * It answers one question above all: "did this app send the camera a command at the
 * moment something went wrong?"
 */
object DiagLog {
    private const val MAX_BYTES = 400_000L
    private var file: File? = null
    private val stamp = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)

    @Synchronized
    fun init(context: Context) {
        if (file == null) file = File(context.applicationContext.filesDir, "diagnostic.log")
    }

    @Synchronized
    fun add(line: String) {
        val f = file ?: return
        try {
            if (f.length() > MAX_BYTES) {
                // Keep the newer half.
                val text = f.readText()
                f.writeText(text.substring(text.indexOf('\n', text.length / 2) + 1))
            }
            f.appendText("${stamp.format(Date())}  $line\n")
        } catch (_: Exception) {
            // Logging must never break the app.
        }
    }

    @Synchronized
    fun read(): String = try {
        file?.takeIf { it.exists() }?.readText().orEmpty()
    } catch (_: Exception) {
        ""
    }

    @Synchronized
    fun clear() {
        try {
            file?.writeText("")
        } catch (_: Exception) {
        }
    }

    /** `http://192.168.1.254/?custom=1&cmd=3004&str=secret` -> `/?custom=1&cmd=3004&str=***` */
    fun describe(url: String): String {
        var short = url.removePrefix("http://192.168.1.254")
        if (short.contains("cmd=3004")) short = short.replace(Regex("str=[^&]*"), "str=***")
        return short
    }
}
