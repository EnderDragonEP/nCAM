package dev.ender.ncam

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Platform-channel front end for [CameraLink]. Channel names are mirrored in Dart. */
class CameraBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(4)
    private val methods = MethodChannel(messenger, "ncam/camera")
    private val events = EventChannel(messenger, "ncam/camera/state")
    private var sink: EventChannel.EventSink? = null
    private val listener: (String) -> Unit = { s -> main.post { sink?.success(s) } }
    private var pendingScan: MethodChannel.Result? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        CameraLink.removeListener(listener)
        io.shutdown()
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
