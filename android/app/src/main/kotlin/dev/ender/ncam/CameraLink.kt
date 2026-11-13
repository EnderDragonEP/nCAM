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

    // What the user asked for, kept so a lost link can be rejoined without them.
    private var appContext: Context? = null
    private var password: String = ""
    private var wanted = false
    private var rejoinAttempt = 0
    private val rejoin = Runnable { rejoinNow() }

    private val REJOIN_DELAYS_MS = longArrayOf(3_000, 5_000, 10_000, 20_000, 30_000)
    private const val REJOIN_TIMEOUT_MS = 20_000

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
     *
     * Once joined, the link is kept: if Android reports it lost, it is requested again
     * until it comes back or [disconnect] is called.
     */
    fun connect(
        context: Context,
        ssid: String,
        password: String,
        timeoutMs: Int,
        onResult: (String?) -> Unit,
    ) {
        main.removeCallbacks(rejoin)
        appContext = context.applicationContext
        this.ssid = ssid
        this.password = password
        wanted = true
        rejoinAttempt = 0
        setState(STATE_CONNECTING)
        request(timeoutMs, rejoining = false, onResult)
    }

    private fun request(timeoutMs: Int, rejoining: Boolean, onResult: (String?) -> Unit) {
        val context = appContext ?: return
        val ssid = ssid ?: return
        val cm = context.getSystemService(ConnectivityManager::class.java)
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
                main.removeCallbacks(rejoin)
                rejoinAttempt = 0
                network = n
                setState(STATE_CONNECTED)
                report(null)
            }

            override fun onLosing(n: Network, maxMsToLive: Int) {
                if (callback === this) DiagLog.add("link: Android says it is losing the link")
            }

            override fun onLost(n: Network) {
                if (callback !== this) return
                network = null
                setState(STATE_LOST)
                // Android does not reliably bring a lost camera link back by itself (seen on
                // the real phone: nothing for over a minute), so ask for it again.
                scheduleRejoin()
            }

            override fun onUnavailable() {
                if (callback !== this) return
                callback = null
                network = null
                if (rejoining && wanted) {
                    // Camera still out of reach: keep trying.
                    scheduleRejoin()
                } else {
                    setState(STATE_DISCONNECTED)
                    report("unavailable")
                }
            }
        }

        callback = cb
        try {
            cm.requestNetwork(request, cb, main, timeoutMs)
        } catch (e: Exception) {
            callback = null
            DiagLog.add("link: request failed: ${e.message}")
            if (rejoining && wanted) {
                scheduleRejoin()
            } else {
                setState(STATE_DISCONNECTED)
                report("error:${e.message}")
            }
        }
    }

    private fun scheduleRejoin() {
        if (!wanted) return
        main.removeCallbacks(rejoin)
        val delay = REJOIN_DELAYS_MS[minOf(rejoinAttempt, REJOIN_DELAYS_MS.size - 1)]
        rejoinAttempt++
        DiagLog.add("link: rejoining in ${delay / 1000} s (attempt $rejoinAttempt)")
        main.postDelayed(rejoin, delay)
    }

    private fun rejoinNow() {
        if (!wanted || state == STATE_CONNECTED) return
        // Stays "lost" for the app while this runs: it is not a new connection.
        request(REJOIN_TIMEOUT_MS, rejoining = true) {}
    }

    fun disconnect(context: Context) {
        wanted = false
        main.removeCallbacks(rejoin)
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
