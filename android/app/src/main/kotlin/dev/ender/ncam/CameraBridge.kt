package dev.ender.ncam

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.view.accessibility.AccessibilityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Platform-channel front end for [CameraLink]. Channel names are mirrored in Dart. */
class CameraBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(4)

    // One thumbnail at a time, so previews never crowd out a download on the slow link.
    private val thumbs = Executors.newSingleThreadExecutor()
    private val methods = MethodChannel(messenger, "ncam/camera")
    private val events = EventChannel(messenger, "ncam/camera/state")
    private var sink: EventChannel.EventSink? = null
    private val listener: (String) -> Unit = { s -> main.post { sink?.success(s) } }
    private var pendingScan: MethodChannel.Result? = null

    // Live view: one reader at a time, started when Dart listens and stopped on cancel.
    private val live = EventChannel(messenger, "ncam/camera/live")
    private var liveReader: MjpegReader? = null
    private val framePending = AtomicBoolean(false)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        live.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                stopLive()
                val url = (arguments as? Map<*, *>)?.get("url") as? String
                if (url == null) {
                    sink.error("bad_args", "url is missing", null)
                    return
                }
                framePending.set(false)
                lateinit var reader: MjpegReader
                reader = MjpegReader(
                    url,
                    onFrame = { frame ->
                        // Drop frames the UI has not caught up with instead of queueing them.
                        if (framePending.compareAndSet(false, true)) {
                            main.post {
                                framePending.set(false)
                                if (liveReader === reader) sink.success(frame)
                            }
                        }
                    },
                    onEnd = { error ->
                        main.post {
                            if (liveReader === reader) {
                                liveReader = null
                                sink.error("stream_ended", error, null)
                            }
                        }
                    },
                )
                liveReader = reader
                reader.start()
            }

            override fun onCancel(arguments: Any?) = stopLive()
        })
    }

    // Keeps the phone's Wi-Fi out of power saving while the live view or player is on
    // screen, which otherwise adds stalls to a continuous stream.
    private var wifiLock: WifiManager.WifiLock? = null

    private fun setLowLatency(on: Boolean) {
        try {
            if (on) {
                if (wifiLock == null) {
                    val wm = activity.applicationContext.getSystemService(WifiManager::class.java)
                    wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "ncam:live")
                        .apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                }
            } else {
                wifiLock?.release()
                wifiLock = null
            }
        } catch (_: Exception) {
            // Optional; the stream works without it.
        }
    }

    private fun stopLive() {
        liveReader?.stop()
        liveReader = null
    }

    fun dispose() {
        stopLive()
        setLowLatency(false)
        live.setStreamHandler(null)
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        CameraLink.removeListener(listener)
        io.shutdown()
        thumbs.shutdown()
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        CameraLink.addListener(listener)
        eventSink.success(CameraLink.state)
    }

    override fun onCancel(arguments: Any?) {
        CameraLink.removeListener(listener)
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(CameraLink.state)

            "connect" -> {
                val ssid = call.argument<String>("ssid").orEmpty()
                val password = call.argument<String>("password").orEmpty()
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 60_000
                if (ssid.isEmpty()) {
                    result.error("bad_args", "ssid is empty", null)
                    return
                }
                CameraLink.connect(activity, ssid, password, timeoutMs) { error ->
                    if (error == null) result.success(null)
                    else result.error("connect_failed", error, null)
                }
            }

            "disconnect" -> {
                CameraLink.disconnect(activity)
                result.success(null)
            }

            "get" -> {
                val url = call.argument<String>("url").orEmpty()
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10_000
                val maxBytes = call.argument<Int>("maxBytes") ?: (4 * 1024 * 1024)
                io.execute {
                    try {
                        val r = CameraLink.get(url, headers, timeoutMs, maxBytes)
                        val map = mapOf("status" to r.status, "headers" to r.headers, "body" to r.body)
                        main.post { result.success(map) }
                    } catch (e: Exception) {
                        val msg = "${e.javaClass.simpleName}: ${e.message}"
                        main.post { result.error("io", msg, null) }
                    }
                }
            }

            "scan" -> scan(result)

            // Where the video player can stream a camera file from (see StreamProxy).
            "streamUrl" -> {
                val path = call.argument<String>("path").orEmpty()
                io.execute {
                    try {
                        val url = StreamProxy.url(path)
                        main.post { result.success(url) }
                    } catch (e: Exception) {
                        main.post { result.error("io", e.message, null) }
                    }
                }
            }

            // The camera link's signal strength in dBm, or null.
            "signal" -> {
                val cm = activity.getSystemService(ConnectivityManager::class.java)
                val info = CameraLink.network?.let { cm.getNetworkCapabilities(it) }?.transportInfo
                val rssi = (info as? WifiInfo)?.rssi
                result.success(if (rssi == null || rssi <= -127) null else rssi)
            }

            // How long on-screen controls may stay before hiding by themselves: the
            // user's "time to take action" accessibility setting when it is longer.
            "controlsTimeout" -> {
                val ms = call.argument<Int>("ms") ?: 3_000
                val am = activity.getSystemService(AccessibilityManager::class.java)
                result.success(
                    am.getRecommendedTimeoutMillis(
                        ms,
                        AccessibilityManager.FLAG_CONTENT_CONTROLS or AccessibilityManager.FLAG_CONTENT_ICONS,
                    )
                )
            }

            // The wallpaper's accent colour (Material You), Android 12 and later.
            "wallpaperColor" -> result.success(
                if (Build.VERSION.SDK_INT >= 31) {
                    activity.getColor(android.R.color.system_accent1_500)
                } else {
                    null
                }
            )

            "thumbnail" -> {
                val url = call.argument<String>("url").orEmpty()
                val key = call.argument<String>("key").orEmpty()
                val app = activity.applicationContext
                thumbs.execute {
                    try {
                        val path = Thumbnails.get(app, url, key)
                        main.post { result.success(path) }
                    } catch (e: Exception) {
                        val msg = "${e.javaClass.simpleName}: ${e.message}"
                        main.post { result.error("io", msg, null) }
                    }
                }
            }

            "saveDiagnosticLog" -> io.execute {
                try {
                    val name = DiagLog.saveToDownloads(activity.applicationContext)
                    main.post { result.success(name) }
                } catch (e: Exception) {
                    main.post { result.error("io", e.message, null) }
                }
            }

            "diagnosticLog" -> io.execute {
                val text = DiagLog.read()
                main.post { result.success(text) }
            }

            "clearDiagnosticLog" -> {
                DiagLog.clear()
                result.success(null)
            }

            "keepScreenOn" -> {
                val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                val on = call.argument<Boolean>("on") == true
                if (on) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
                setLowLatency(on)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ---- Wi-Fi scan (only used to offer a list of names when picking the camera) ----

    private fun scanPermission(): String =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES
        else Manifest.permission.ACCESS_FINE_LOCATION

    private fun scan(result: MethodChannel.Result) {
        val granted = activity.checkSelfPermission(scanPermission()) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            runScan(result)
            return
        }
        if (pendingScan != null) {
            result.error("busy", "a scan is already waiting for permission", null)
            return
        }
        pendingScan = result
        activity.requestPermissions(arrayOf(scanPermission()), REQUEST_SCAN)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_SCAN) return
        val result = pendingScan ?: return
        pendingScan = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            runScan(result)
        } else {
            result.error("permission_denied", "Wi-Fi scan permission was not granted", null)
        }
    }

    private fun runScan(result: MethodChannel.Result) {
        val wifi = activity.applicationContext.getSystemService(WifiManager::class.java)
        try {
            @Suppress("DEPRECATION")
            wifi.startScan() // Throttled by Android; cached results are still returned below.
        } catch (_: Exception) {
        }
        main.postDelayed({
            try {
                val best = HashMap<String, Int>()
                for (r in wifi.scanResults) {
                    @Suppress("DEPRECATION")
                    val name = r.SSID ?: continue
                    if (name.isEmpty()) continue
                    val prev = best[name]
                    if (prev == null || r.level > prev) best[name] = r.level
                }
                val list = best.entries.sortedByDescending { it.value }
                    .map { mapOf("ssid" to it.key, "level" to it.value) }
                result.success(list)
            } catch (e: SecurityException) {
                result.error("permission_denied", e.message, null)
            } catch (e: Exception) {
                result.error("scan_failed", e.message, null)
            }
        }, 3000)
    }

    private companion object {
        const val REQUEST_SCAN = 4101
    }
}
