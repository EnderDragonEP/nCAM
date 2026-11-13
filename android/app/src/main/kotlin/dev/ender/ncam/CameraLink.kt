package dev.ender.ncam

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Owns the app's private Wi-Fi link to the camera.
 *
 * The link is requested with a [WifiNetworkSpecifier], so Android gives this app its own
 * [Network] for the camera and does NOT make it the phone's default route: other apps, and
 * everything in this app that is not sent through [network], keep using mobile data.
 *
 * Process-wide singleton so the link survives activity recreation.
 */
object CameraLink {
    const val STATE_DISCONNECTED = "disconnected"
    const val STATE_CONNECTING = "connecting"
    const val STATE_CONNECTED = "connected"
    const val STATE_LOST = "lost"

    @Volatile
    var network: Network? = null
        private set

    @Volatile
    var state: String = STATE_DISCONNECTED
        private set

    @Volatile
    var ssid: String? = null
        private set

    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<(String) -> Unit>()
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun addListener(l: (String) -> Unit) = listeners.add(l)
    fun removeListener(l: (String) -> Unit) = listeners.remove(l)

    private fun setState(s: String) {
        if (s != state) DiagLog.add("link: $s")
        state = s
        listeners.forEach { it(s) }
    }

    /**
     * Asks Android to join [ssid]. [onResult] is called once on the main thread with null on
     * success or a short error code: "unavailable" (not found, wrong password, or the user
     * dismissed the system dialog) or "error:<message>".
     */
    fun connect(
        context: Context,
        ssid: String,
        password: String,
        timeoutMs: Int,
        onResult: (String?) -> Unit,
    ) {
        val cm = context.applicationContext.getSystemService(ConnectivityManager::class.java)
        release(cm)

        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (password.isNotEmpty()) setWpa2Passphrase(password)
        }.build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            // The camera has no internet; saying so stops Android from rejecting the network.
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()

        var reported = false
        fun report(error: String?) {
            if (!reported) {
                reported = true
                onResult(error)
            }
        }

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                if (callback !== this) return
                network = n
                setState(STATE_CONNECTED)
                report(null)
            }

            override fun onLost(n: Network) {
                if (callback !== this) return
                // The request stays registered, so Android rejoins by itself when the camera
                // comes back in range and onAvailable fires again.
                network = null
                setState(STATE_LOST)
            }

            override fun onUnavailable() {
                if (callback !== this) return
                callback = null
                network = null
                setState(STATE_DISCONNECTED)
                report("unavailable")
            }
        }

        this.ssid = ssid
        callback = cb
        setState(STATE_CONNECTING)
        try {
            cm.requestNetwork(request, cb, main, timeoutMs)
        } catch (e: Exception) {
            callback = null
            setState(STATE_DISCONNECTED)
            report("error:${e.message}")
        }
    }

    fun disconnect(context: Context) {
        val cm = context.applicationContext.getSystemService(ConnectivityManager::class.java)
        release(cm)
        setState(STATE_DISCONNECTED)
    }

    private fun release(cm: ConnectivityManager) {
        callback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {
                // Already released by the system.
            }
        }
        callback = null
        network = null
    }

    class HttpReply(val status: Int, val headers: Map<String, String>, val body: ByteArray)

    /**
     * Plain GET sent over the camera network only. Blocking: call from a worker thread.
     * Reads at most [maxBytes] of the body.
     */
    @Throws(IOException::class)
    fun get(url: String, headers: Map<String, String>, timeoutMs: Int, maxBytes: Int): HttpReply {
        val what = DiagLog.describe(url) + (headers["Range"]?.let { " [$it]" } ?: "")
        try {
            val reply = getUnlogged(url, headers, timeoutMs, maxBytes)
            val type = reply.headers["content-type"].orEmpty()
            val text = reply.body.size < 4096 &&
                (type.startsWith("text/") || reply.body.firstOrNull() == '<'.code.toByte())
            val detail =
                if (text) String(reply.body).replace(Regex("\\s+"), " ").take(300)
                else "${reply.body.size} bytes $type"
            DiagLog.add("GET $what -> ${reply.status} $detail")
            return reply
        } catch (e: Exception) {
            DiagLog.add("GET $what -> FAILED ${e.javaClass.simpleName}: ${e.message}")
            throw e
        }
    }

    @Throws(IOException::class)
    private fun getUnlogged(
        url: String,
        headers: Map<String, String>,
        timeoutMs: Int,
        maxBytes: Int,
    ): HttpReply {
        val n = network ?: throw IOException("not connected to the camera")
        val conn = n.openConnection(URL(url)) as HttpURLConnection
        try {
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.useCaches = false
            conn.instanceFollowRedirects = false
            // The camera's server closes every connection anyway; don't try to reuse them.
            conn.setRequestProperty("Connection", "close")
            headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }

            val status = conn.responseCode
            val stream = (if (status >= 400) conn.errorStream else conn.inputStream)
            val out = ByteArrayOutputStream()
            stream?.use { input ->
                val buf = ByteArray(64 * 1024)
                while (out.size() < maxBytes) {
                    val read = input.read(buf, 0, minOf(buf.size, maxBytes - out.size()))
                    if (read < 0) break
                    out.write(buf, 0, read)
                }
            }
            val replyHeaders = HashMap<String, String>()
            conn.headerFields.forEach { (k, v) ->
                if (k != null && v.isNotEmpty()) replyHeaders[k.lowercase()] = v.last()
            }
            return HttpReply(status, replyHeaders, out.toByteArray())
        } finally {
            conn.disconnect()
        }
    }
}
