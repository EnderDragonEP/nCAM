package dev.ender.ncam

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Platform-channel front end for the download queue ([Downloads]). */
class DownloadBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val methods = MethodChannel(messenger, "ncam/downloads")
    private val events = EventChannel(messenger, "ncam/downloads/jobs")
    private var sink: EventChannel.EventSink? = null
    private val fastEvents = EventChannel(messenger, "ncam/downloads/fast")
    private var fastSink: EventChannel.EventSink? = null
    private val fastListener: () -> Unit = {
        val snapshot = FastMode.snapshot(activity)
        main.post { fastSink?.success(snapshot) }
    }
    private val listener: () -> Unit = {
        val snapshot = Downloads.snapshot()
        main.post { sink?.success(snapshot) }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        fastEvents.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                fastSink = eventSink
                FastMode.addListener(fastListener)
                eventSink.success(FastMode.snapshot(activity))
            }

            override fun onCancel(arguments: Any?) {
                FastMode.removeListener(fastListener)
                fastSink = null
            }
        })
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        fastEvents.setStreamHandler(null)
        Downloads.removeListener(listener)
        FastMode.removeListener(fastListener)
        io.shutdown()
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        Downloads.addListener(listener)
        eventSink.success(Downloads.snapshot())
    }

    override fun onCancel(arguments: Any?) {
        Downloads.removeListener(listener)
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enqueue" -> {
                askForNotifications()
                val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                try {
                    Downloads.enqueue(activity, items)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("start_failed", e.message, null)
                }
            }

            "retry" -> {
                try {
                    Downloads.retry(activity, call.argument<String>("id").orEmpty())
                    result.success(null)
                } catch (e: Exception) {
                    result.error("start_failed", e.message, null)
                }
            }

            "cancel" -> {
                Downloads.cancel(call.argument<String>("id"))
                result.success(null)
            }

            "clearFinished" -> {
                Downloads.clearFinished()
                result.success(null)
            }

            "snapshot" -> result.success(Downloads.snapshot())

            "fastSnapshot" -> result.success(FastMode.snapshot(activity))

            "setFastMode" -> {
                FastMode.setEnabled(activity, call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }

            // Restarts recording if this app left it paused (app killed, or camera out of
            // range, before the queue finished). True when it had to act and succeeded.
            "recoverRecording" -> {
                val app = activity.applicationContext
                if (!FastMode.pausedByApp(app) || Downloads.activeCount() > 0) {
                    // Nothing to do, or the download service is in charge of it.
                    result.success(false)
                } else {
                    // Own thread: this can take two minutes when the camera is unreachable.
                    Thread {
                        val ok = FastMode.resume(app)
                        main.post {
                            if (ok) result.success(true)
                            else result.error("resume_failed", FastMode.message, null)
                        }
                    }.start()
                }
            }

            "localUri" -> io.execute {
                val name = call.argument<String>("name").orEmpty()
                try {
                    val uri = DownloadService.localUri(activity.applicationContext, name)
                    main.post { result.success(uri?.toString()) }
                } catch (e: Exception) {
                    main.post { result.error("io", e.message, null) }
                }
            }

            "deleteLocal" -> io.execute {
                val name = call.argument<String>("name").orEmpty()
                try {
                    val ok = DownloadService.deleteLocal(activity.applicationContext, name)
                    Downloads.forget(name)
                    main.post { result.success(ok) }
                } catch (e: Exception) {
                    main.post { result.error("io", e.message, null) }
                }
            }

            "localFiles" -> io.execute {
                try {
                    val files = DownloadService.localFiles(activity.applicationContext)
                    main.post { result.success(files) }
                } catch (e: Exception) {
                    main.post { result.error("io", e.message, null) }
                }
            }

            else -> result.notImplemented()
        }
    }

    /** The progress notification is optional; downloads run without it. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT < 33) return
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (activity.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(permission), 4102)
        }
    }
}
