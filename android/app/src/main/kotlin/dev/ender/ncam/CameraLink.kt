package dev.ender.ncam

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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

    /** Whether a link is wanted: false after [disconnect] (the user's Disconnect). */
    val isWanted: Boolean get() = wanted

    /**
     * Set while the background clock sync is on: a first join that finds no camera
     * goes on waiting for it, instead of giving up.
     */
    @Volatile
    var keepWaiting = false

    // Answers the app's pending connect call; disconnect() uses it to say "cancelled".
    private var pendingReport: ((String?) -> Unit)? = null

    // ---- Rejoining a lost link ----------------------------------------------------
    //
    // Seen on the real phone when the camera power-cycles: while the camera's Wi-Fi is
    // gone, Android refuses join requests on the spot, and a request it does accept can
    // then sit unanswered forever. What works is asking once the camera is visible
    // again (the user's Cancel + Connect). So while the link is lost, the camera's name
    // is looked for in Wi-Fi scans, and the join is requested only once it shows up.

    private const val WATCH_MS = 4_000L // how often the lost link is looked after
    private const val REJOIN_TIMEOUT_MS = 25_000 // one join request
    private const val STUCK_MS = REJOIN_TIMEOUT_MS + 5_000L // no answer at all: give up on it
    private const val REFUSED_COOLDOWN_MS = 5_000L // after Android refused a request
    private const val SCAN_EVERY_MS = 30_000L // Android allows 4 scans per 2 min
    private const val FRESH_RESULT_MS = 30_000L // a scan result this old still counts
    private const val BLIND_RETRY_MS = 20_000L // without scan permission

    private var requestSince = 0L // when the current rejoin request was made; 0 = none
    private var cooldownUntil = 0L
    private var lastScanAt = 0L
    private var lastBlindAt = 0L
    private var announcedWaiting = false
    private var scanReceiver: BroadcastReceiver? = null
    private val watch = Runnable { watchTick() }

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
     * Once joined, the link is kept: if Android reports it lost, it is rejoined as soon
     * as the camera is back, until [disconnect] is called.
     */
    fun connect(
        context: Context,
        ssid: String,
        password: String,
        timeoutMs: Int,
        onResult: (String?) -> Unit,
    ) {
        // Already joined with these details (the background clock sync did it): keep
        // the link instead of dropping and asking again.
        if (state == STATE_CONNECTED && network != null && this.ssid == ssid &&
            this.password == password
        ) {
            wanted = true
            onResult(null)
            return
        }
        stopWatching()
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
                pendingReport = null
                onResult(error)
            }
        }
        if (!rejoining) pendingReport = { error -> report(error) }

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                if (callback !== this) return
                stopWatching()
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
                // Android does not bring a lost camera link back by itself.
                startWatching()
            }

            override fun onUnavailable() {
                if (callback !== this) return
                callback = null
                network = null
                if (rejoining && wanted) {
                    rejoinFailed("no answer from the camera")
                } else if (keepWaiting && wanted) {
                    // Not here yet: wait for it, as for a lost link.
                    report("unavailable")
                    setState(STATE_LOST)
                    startWatching()
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
                rejoinFailed("request failed")
            } else if (keepWaiting && wanted) {
                report("error:${e.message}")
                setState(STATE_LOST)
                startWatching()
            } else {
                setState(STATE_DISCONNECTED)
                report("error:${e.message}")
            }
        }
    }

    // ---- Looking after a lost link ----------------------------------------------------

    private fun startWatching() {
        if (!wanted) return
        announcedWaiting = false
        cooldownUntil = 0
        registerScanReceiver()
        main.removeCallbacks(watch)
        main.postDelayed(watch, 1_000)
    }

    private fun stopWatching() {
        main.removeCallbacks(watch)
        unregisterScanReceiver()
        requestSince = 0
    }

    private fun watchTick() {
        main.removeCallbacks(watch)
        if (!wanted || state == STATE_CONNECTED) {
            stopWatching()
            return
        }
        val now = SystemClock.elapsedRealtime()
        val pending = requestSince != 0L
        if (pending && now - requestSince > STUCK_MS) {
            // Android neither joined nor gave up: drop the request and start again.
            DiagLog.add("link: join request got no answer, starting again")
            appContext?.let { release(it.getSystemService(ConnectivityManager::class.java)) }
            requestSince = 0
        } else if (!pending && now >= cooldownUntil) {
            when (cameraVisible(now)) {
                true -> rejoinNow("camera seen")
                false -> {
                    if (!announcedWaiting) {
                        announcedWaiting = true
                        DiagLog.add("link: waiting for $ssid to appear")
                    }
                    startScan(now, force = false)
                }
                // Scan results not readable: fall back to plain retries.
                null -> if (now - lastBlindAt >= BLIND_RETRY_MS) {
                    lastBlindAt = now
                    rejoinNow("no scan permission, trying blind")
                }
            }
        }
        main.postDelayed(watch, WATCH_MS)
    }

    private fun rejoinNow(why: String) {
        if (!wanted || state == STATE_CONNECTED) return
        rejoinAttempt++
        DiagLog.add("link: rejoining, attempt $rejoinAttempt ($why)")
        announcedWaiting = false
        requestSince = SystemClock.elapsedRealtime()
        // Stays "lost" for the app while this runs: it is not a new connection.
        request(REJOIN_TIMEOUT_MS, rejoining = true) {}
    }

    private fun rejoinFailed(reason: String) {
        val took = if (requestSince == 0L) 0 else SystemClock.elapsedRealtime() - requestSince
        requestSince = 0
        if (took < 3_000) {
            DiagLog.add("link: Android refused the join at once ($reason)")
            cooldownUntil = SystemClock.elapsedRealtime() + REFUSED_COOLDOWN_MS
        } else {
            DiagLog.add("link: join attempt ended after ${took / 1000} s ($reason)")
        }
        main.removeCallbacks(watch)
        main.postDelayed(watch, WATCH_MS)
    }

    /** True if the camera's Wi-Fi was in a recent scan; null if scans cannot be read. */
    private fun cameraVisible(now: Long): Boolean? {
        val context = appContext ?: return null
        val name = ssid ?: return null
        if (!canReadScans(context)) return null
        return try {
            val wifi = context.getSystemService(WifiManager::class.java)
            val nowMicros = now * 1000
            @Suppress("DEPRECATION")
            wifi.scanResults.any {
                it.SSID == name && nowMicros - it.timestamp < FRESH_RESULT_MS * 1000
            }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            false
        }
    }

    private fun canReadScans(context: Context): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun startScan(now: Long, force: Boolean) {
        val context = appContext ?: return
        if (!force && now - lastScanAt < SCAN_EVERY_MS) return
        lastScanAt = now
        try {
            @Suppress("DEPRECATION")
            context.getSystemService(WifiManager::class.java).startScan()
        } catch (_: Exception) {
            // Throttled or not allowed; scans Android runs anyway still arrive.
        }
    }

    private fun registerScanReceiver() {
        val context = appContext ?: return
        if (scanReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                // Fresh results: look for the camera now rather than at the next tick.
                if (requestSince == 0L) main.post(watch)
            }
        }
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }
            scanReceiver = receiver
        } catch (_: Exception) {
        }
    }

    private fun unregisterScanReceiver() {
        val receiver = scanReceiver ?: return
        scanReceiver = null
        try {
            appContext?.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
    }

    /**
     * Waits for the camera without asking to join yet: joins as soon as its Wi-Fi shows
     * up, as for a lost link. For the background clock sync.
     */
    fun waitFor(context: Context, ssid: String, password: String) {
        if (state == STATE_CONNECTED && this.ssid == ssid) {
            wanted = true
            return
        }
        // The app is joining right now; if that finds no camera, [keepWaiting] turns
        // it into waiting. Starting over here would cut the app's request off.
        if (state == STATE_CONNECTING) {
            wanted = true
            return
        }
        if (wanted && state == STATE_LOST && this.ssid == ssid) return
        appContext = context.applicationContext
        this.ssid = ssid
        this.password = password
        wanted = true
        rejoinAttempt = 0
        setState(STATE_LOST)
        startWatching()
    }

    /**
     * The app came back on screen. A lost link gets a fresh start: Android is more willing
     * to join for an app in front of the user, and an old request may be stuck.
     */
    fun onAppResumed() = nudge("app back on screen")

    /**
     * Looks for the camera now. [why] is logged; a quiet nudge (a timer that wakes the
     * phone now and then) leaves a join in progress alone and logs nothing.
     */
    fun nudge(why: String, quiet: Boolean = false) {
        if (!wanted || state != STATE_LOST) return
        val now = SystemClock.elapsedRealtime()
        if (quiet) {
            if (requestSince != 0L) return
        } else {
            if (requestSince != 0L && now - requestSince > 8_000) {
                appContext?.let {
                    release(it.getSystemService(ConnectivityManager::class.java))
                }
                requestSince = 0
            }
            DiagLog.add("link: $why, looking for the camera now")
        }
        cooldownUntil = 0
        registerScanReceiver()
        startScan(now, force = true)
        main.removeCallbacks(watch)
        main.post(watch)
    }

    fun disconnect(context: Context) {
        wanted = false
        stopWatching()
        val cm = context.applicationContext.getSystemService(ConnectivityManager::class.java)
        release(cm)
        setState(STATE_DISCONNECTED)
        // A join still waiting for Android was cancelled by the user: say so, or the
        // app's connect call would wait forever.
        pendingReport?.invoke("cancelled")
        pendingReport = null
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
