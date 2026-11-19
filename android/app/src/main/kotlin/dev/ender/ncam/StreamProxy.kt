package dev.ender.ncam

import java.io.BufferedInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.Executors

/**
 * Lets the video player stream a clip straight from the camera, without downloading it
 * first.
 *
 * The player can only fetch from the phone's default network, and the camera is on the
 * app's private link ([CameraLink.network]). So the player is pointed at this small
 * server on the phone itself (127.0.0.1 only), which passes each request, including the
 * byte ranges the player asks for when it seeks, on to the camera over the private link.
 * A random token in every address keeps other apps on the phone from using it.
 */
object StreamProxy {
    private const val CAMERA = "http://192.168.1.254"

    private val token: String = ByteArray(12).also { SecureRandom().nextBytes(it) }
        .joinToString("") { "%02x".format(it) }
    private val pool = Executors.newCachedThreadPool()
    private var server: ServerSocket? = null

    /** The address the player should use for the camera file at [path]. */
    @Synchronized
    fun url(path: String): String {
        val s = server ?: start()
        return "http://127.0.0.1:${s.localPort}/$token$path"
    }

    private fun start(): ServerSocket {
        val s = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        server = s
        Thread({
            while (!s.isClosed) {
                try {
                    val client = s.accept()
                    pool.execute { serve(client) }
                } catch (_: IOException) {
                    // Closed, or one bad connection: keep serving the others.
                }
            }
        }, "ncam-stream").apply { isDaemon = true }.start()
        DiagLog.add("stream: ready on port ${s.localPort}")
        return s
    }

    private fun serve(client: Socket) {
        client.use { socket ->
            socket.soTimeout = 30_000
            val input = BufferedInputStream(socket.getInputStream())
            val out = socket.getOutputStream()
            val request = readLine(input) ?: return
            val headers = HashMap<String, String>()
            while (true) {
                val line = readLine(input) ?: return
                if (line.isEmpty()) break
                val colon = line.indexOf(':')
                if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
            }
            val parts = request.split(' ')
            val method = parts.getOrNull(0) ?: ""
            val target = parts.getOrNull(1) ?: ""
            val prefix = "/$token/"
            // Only the camera's files, only for whoever got the address from this app.
            if ((method != "GET" && method != "HEAD") || !target.startsWith(prefix + "Novatek/")) {
                respond(out, 404, "Not Found")
                return
            }
            val path = target.substring(prefix.length - 1)
            val network = CameraLink.network
            if (network == null) {
                respond(out, 503, "Service Unavailable")
                return
            }
            val conn = network.openConnection(URL(CAMERA + path)) as HttpURLConnection
            try {
                conn.connectTimeout = 10_000
                conn.readTimeout = 20_000
                conn.useCaches = false
                conn.requestMethod = method
                conn.setRequestProperty("Connection", "close")
                conn.setRequestProperty("Accept-Encoding", "identity")
                headers["range"]?.let { conn.setRequestProperty("Range", it) }
                val code = conn.responseCode
                val type = conn.contentType.orEmpty()
                // The camera answers missing files with a "Page Not found" page.
                if (type.startsWith("text/")) {
                    respond(out, 404, "Not Found")
                    return
                }
                DiagLog.add("stream: ${DiagLog.describe(CAMERA + path)} ${headers["range"] ?: ""} -> $code")
                val head = StringBuilder("HTTP/1.1 $code ${conn.responseMessage ?: ""}\r\n")
                head.append("Content-Type: ").append(type.ifEmpty { "video/mp2t" }).append("\r\n")
                conn.getHeaderField("Content-Length")?.let { head.append("Content-Length: $it\r\n") }
                conn.getHeaderField("Content-Range")?.let { head.append("Content-Range: $it\r\n") }
                head.append("Accept-Ranges: bytes\r\nConnection: close\r\n\r\n")
                out.write(head.toString().toByteArray(Charsets.ISO_8859_1))
                if (method == "GET") {
                    val body = if (code >= 400) conn.errorStream else conn.inputStream
                    body?.use { copy(it, out) }
                }
                out.flush()
            } catch (_: IOException) {
                // The player let go (it does on every seek) or the link dropped.
            } finally {
                conn.disconnect()
            }
        }
    }

    private fun copy(from: InputStream, to: OutputStream) {
        val buf = ByteArray(64 * 1024)
        while (true) {
            val n = from.read(buf)
            if (n < 0) return
            to.write(buf, 0, n)
        }
    }

    private fun respond(out: OutputStream, code: Int, text: String) {
        try {
            out.write("HTTP/1.1 $code $text\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
            out.flush()
        } catch (_: IOException) {
        }
    }

    /** One header line, without the line break; null at the end of the stream. */
    private fun readLine(input: InputStream): String? {
        val line = StringBuilder()
        while (true) {
            val b = input.read()
            if (b < 0) return if (line.isEmpty()) null else line.toString()
            if (b == '\n'.code) return line.toString().trimEnd('\r')
            if (line.length > 8192) throw IOException("header too long")
            line.append(b.toChar())
        }
    }
}
