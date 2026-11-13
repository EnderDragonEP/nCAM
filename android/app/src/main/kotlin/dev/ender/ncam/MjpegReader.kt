package dev.ender.ncam

import android.os.SystemClock
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Reads the camera's live view: an endless HTTP response carrying one JPEG after another
 * (MJPEG), sent over the camera link.
 *
 * Frames are found by their JPEG start marker, and their length is taken from the part's
 * Content-Length header when there is one, so the exact multipart layout does not matter.
 */
class MjpegReader(
    private val url: String,
    private val onFrame: (ByteArray) -> Unit,
    private val onEnd: (String?) -> Unit,
) {
    @Volatile private var stopped = false
    @Volatile private var conn: HttpURLConnection? = null
    private var thread: Thread? = null

    fun start() {
        thread = Thread({ run() }, "ncam-live").also { it.start() }
    }

    fun stop() {
        stopped = true
        // Closing from another thread unblocks a read that is waiting on the camera.
        Thread { try { conn?.disconnect() } catch (_: Exception) {} }.start()
    }

    private fun run() {
        var error: String? = null
        var frames = 0L
        val started = SystemClock.elapsedRealtime()
        DiagLog.add("live: opening $url")
        try {
            val network = CameraLink.network ?: throw IOException("not connected to the camera")
            val c = network.openConnection(URL(url)) as HttpURLConnection
            conn = c
            c.connectTimeout = 5_000
            c.readTimeout = 5_000
            c.useCaches = false
            val code = c.responseCode
            if (code != 200) throw IOException("HTTP $code")
            val type = c.contentType.orEmpty()
            if (type.startsWith("text/")) throw IOException("the camera did not send video ($type)")
            BufferedInputStream(c.inputStream, 64 * 1024).use { input ->
                while (!stopped) {
                    val frame = readFrame(input)
                    if (frames == 0L) {
                        val ms = SystemClock.elapsedRealtime() - started
                        DiagLog.add("live: first picture after $ms ms")
                    }
                    frames++
                    onFrame(frame)
                }
            }
        } catch (e: Exception) {
            if (!stopped) error = "${e.javaClass.simpleName}: ${e.message}"
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
            conn = null
        }
        val secs = (SystemClock.elapsedRealtime() - started) / 1000
        val how = if (stopped) "closed by the app" else "ended: ${error ?: "camera closed the stream"}"
        DiagLog.add("live: $how after $secs s, $frames pictures, link ${CameraLink.state}")
        if (!stopped) onEnd(error ?: "the camera closed the stream")
    }

    private fun readFrame(input: InputStream): ByteArray {
        // Skip to the JPEG start marker (FF D8), remembering the text before it: that is
        // where a multipart header with the frame's length would be.
        val preamble = ByteArrayOutputStream(512)
        var prev = -1
        while (true) {
            val b = input.read()
            if (b < 0) throw EOFException("stream ended")
            if (prev == 0xFF && b == 0xD8) break
            if (preamble.size() > 4096) preamble.reset()
            preamble.write(b)
            prev = b
        }
        val length = CONTENT_LENGTH.findAll(preamble.toString(Charsets.ISO_8859_1.name()))
            .lastOrNull()?.groupValues?.get(1)?.toIntOrNull()

        if (length != null && length in 4..MAX_FRAME) {
            val frame = ByteArray(length)
            frame[0] = 0xFF.toByte()
            frame[1] = 0xD8.toByte()
            var off = 2
            while (off < length) {
                val n = input.read(frame, off, length - off)
                if (n < 0) throw EOFException("stream ended mid-frame")
                off += n
            }
            return frame
        }

        // No length given: read up to the JPEG end marker (FF D9).
        val out = ByteArrayOutputStream(64 * 1024)
        out.write(0xFF)
        out.write(0xD8)
        prev = -1
        while (true) {
            val b = input.read()
            if (b < 0) throw EOFException("stream ended mid-frame")
            out.write(b)
            if (prev == 0xFF && b == 0xD9) return out.toByteArray()
            if (out.size() > MAX_FRAME) throw IOException("frame too large")
            prev = b
        }
    }

    private companion object {
        const val MAX_FRAME = 8 * 1024 * 1024
        val CONTENT_LENGTH = Regex("(?i)content-length:\\s*(\\d+)")
    }
}
