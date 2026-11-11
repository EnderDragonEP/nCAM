package dev.ender.ncam

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import java.io.File

/**
 * Small preview pictures for clips on the camera, cached on the phone.
 *
 * The camera has a thumbnail command (4001), but it answers with an error while recording.
 * So when that fails, the first megabyte or so of the clip is fetched with a Range request
 * and its first video frame is decoded here.
 */
object Thumbnails {
    private const val WIDTH = 320
    private const val HEIGHT = 180
    private val HEAD_SIZES = intArrayOf(1_500_000, 4_000_000)

    /**
     * Returns the path of a cached JPEG for the clip at [url], creating it if needed, or
     * null if no picture could be made from the clip. Blocking. Throws on network errors,
     * so the caller can tell "try again later" from "this clip has no picture".
     */
    fun get(context: Context, url: String, key: String): String? {
        val dir = File(context.cacheDir, "thumbs").apply { mkdirs() }
        val safe = key.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val out = File(dir, "$safe.jpg")
        if (out.length() > 0) return out.path

        // 1. The camera's own thumbnail: tiny and instant when it works.
        val own = CameraLink.get("$url?custom=1&cmd=4001", emptyMap(), 8_000, 2 * 1024 * 1024)
        if (isJpeg(own.body)) {
            out.writeBytes(own.body)
            return out.path
        }

        // 2. Decode the first frame from the start of the clip.
        val lower = url.lowercase()
        if (!(lower.endsWith(".ts") || lower.endsWith(".mp4") || lower.endsWith(".mov"))) return null
        for (size in HEAD_SIZES) {
            val head = CameraLink.get(url, mapOf("Range" to "bytes=0-${size - 1}"), 20_000, size)
            if (head.headers["content-type"].orEmpty().startsWith("text/")) return null
            val tmp = File(dir, "$safe.head" + lower.substring(lower.lastIndexOf('.')))
            try {
                tmp.writeBytes(head.body)
                val frame = firstFrame(tmp)
                if (frame != null) {
                    out.outputStream().use { frame.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                    frame.recycle()
                    return out.path
                }
            } finally {
                tmp.delete()
            }
            if (head.body.size < size) break // that was the whole file
        }
        return null
    }

    private fun isJpeg(b: ByteArray) =
        b.size > 3 && b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte()

    private fun firstFrame(file: File): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.path)
            retriever.getScaledFrameAtTime(
                0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, WIDTH, HEIGHT,
            )
        } catch (_: Exception) {
            null
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }
}
