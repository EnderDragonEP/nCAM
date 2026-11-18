package dev.ender.ncam

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Picture-in-picture for the live view and the clip player.
 *
 * Flutter tells this bridge, through "configure", whether the page on screen can go
 * into a floating window, its shape, whether it should go there by itself when the
 * user leaves the app, and which buttons the window should offer. The bridge reports
 * back when the window opens, returns to full screen or is closed, and when one of
 * its buttons is pressed.
 */
class PipBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "ncam/pip")

    private var available = false
    private var autoEnter = false
    private var aspect = Rational(16, 9)
    private var actions: List<String> = emptyList()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val name = intent.getStringExtra(EXTRA_NAME) ?: return
            channel.invokeMethod("action", name)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        val filter = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(receiver, filter)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        try {
            activity.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
    }

    private val supported: Boolean
        get() = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supported" -> result.success(supported)

            "configure" -> {
                available = call.argument<Boolean>("available") == true
                autoEnter = call.argument<Boolean>("autoEnter") == true
                val w = call.argument<Int>("aspectWidth") ?: 16
                val h = call.argument<Int>("aspectHeight") ?: 9
                aspect = clampAspect(w, h)
                actions = call.argument<List<String>>("actions") ?: emptyList()
                applyParams()
                result.success(null)
            }

            "enter" -> result.success(enter())

            else -> result.notImplemented()
        }
    }

    /** Android only accepts shapes between 1:2.39 and 2.39:1. */
    private fun clampAspect(w: Int, h: Int): Rational {
        if (w <= 0 || h <= 0) return Rational(16, 9)
        val ratio = w.toDouble() / h
        return when {
            ratio > 2.39 -> Rational(239, 100)
            ratio < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(aspect)
            .setActions(actions.mapIndexedNotNull { i, name -> remoteAction(i, name) })
        if (Build.VERSION.SDK_INT >= 31) {
            // Android 12+: go into the window by itself on swipe home, like YouTube.
            builder.setAutoEnterEnabled(available && autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun applyParams() {
        if (!supported) return
        try {
            activity.setPictureInPictureParams(params())
        } catch (e: Exception) {
            DiagLog.add("pip: could not set parameters: ${e.message}")
        }
    }

    fun enter(): Boolean {
        if (!supported || !available) return false
        return try {
            activity.enterPictureInPictureMode(params())
        } catch (e: Exception) {
            // Thrown when the user has turned picture-in-picture off for the app.
            DiagLog.add("pip: could not enter: ${e.message}")
            false
        }
    }

    /** Android 10 and 11 have no auto-enter; leaving the app is noticed here instead. */
    fun onUserLeaveHint() {
        if (Build.VERSION.SDK_INT < 31 && available && autoEnter) enter()
    }

    /**
     * The window opened or went away. [closed] is true when the user dismissed it,
     * as opposed to expanding it back to full screen.
     */
    fun onModeChanged(inPip: Boolean, closed: Boolean) {
        DiagLog.add("pip: " + if (inPip) "entered" else if (closed) "closed" else "expanded")
        channel.invokeMethod("changed", mapOf("inPip" to inPip, "closed" to closed))
    }

    private fun remoteAction(index: Int, name: String): RemoteAction? {
        val (icon, title) = when (name) {
            "play" -> android.R.drawable.ic_media_play to R.string.pip_play
            "pause" -> android.R.drawable.ic_media_pause to R.string.pip_pause
            "rewind" -> android.R.drawable.ic_media_rew to R.string.pip_back
            "forward" -> android.R.drawable.ic_media_ff to R.string.pip_forward
            else -> return null
        }.let { (icon, text) -> icon to activity.getString(text) }
        val intent = Intent(ACTION).setPackage(activity.packageName).putExtra(EXTRA_NAME, name)
        val pending = PendingIntent.getBroadcast(
            activity, index, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return RemoteAction(Icon.createWithResource(activity, icon), title, title, pending)
    }

    private companion object {
        const val ACTION = "dev.ender.ncam.PIP_ACTION"
        const val EXTRA_NAME = "name"
    }
}
