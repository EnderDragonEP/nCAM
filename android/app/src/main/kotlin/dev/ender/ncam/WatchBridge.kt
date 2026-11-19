package dev.ender.ncam

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Platform-channel front end for the background clock sync ([CameraWatch]). */
class WatchBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "ncam/watch")

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() = channel.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val app = activity.applicationContext
        when (call.method) {
            "start" -> {
                val ssid = call.argument<String>("ssid").orEmpty()
                if (ssid.isEmpty()) {
                    result.error("bad_args", "ssid is empty", null)
                    return
                }
                try {
                    CameraWatch.start(
                        app,
                        ssid,
                        call.argument<String>("password").orEmpty(),
                        call.argument<Boolean>("newClip") ?: true,
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("start_failed", e.message, null)
                }
            }

            "stop" -> {
                CameraWatch.stop(app)
                result.success(null)
            }

            "batteryUnrestricted" -> result.success(
                app.getSystemService(PowerManager::class.java)
                    .isIgnoringBatteryOptimizations(app.packageName)
            )

            // Android's own "let this app always run in the background?" question.
            "askUnrestricted" -> {
                try {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:${app.packageName}"),
                        )
                    )
                } catch (_: Exception) {
                    activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
                result.success(null)
            }

            // Where the clock sync's notification can be switched off; the sync keeps
            // running without it.
            "openNotificationSettings" -> {
                CameraWatchService.createChannels(app)
                activity.startActivity(
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, CameraWatchService.CHANNEL_WATCH)
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
