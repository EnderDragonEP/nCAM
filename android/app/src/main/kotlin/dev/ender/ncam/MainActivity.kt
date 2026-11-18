package dev.ender.ncam

import android.content.res.Configuration
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: CameraBridge? = null
    private var downloads: DownloadBridge? = null
    private var pip: PipBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DiagLog.init(this)
        DiagLog.add("app: started")
        bridge = CameraBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        downloads = DownloadBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        pip = PipBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.dispose()
        bridge = null
        downloads?.dispose()
        downloads = null
        pip?.dispose()
        pip = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onResume() {
        super.onResume()
        CameraLink.onAppResumed()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        pip?.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Leaving the window while the activity is no longer started means the user
        // dismissed it; otherwise they expanded it back to full screen.
        val closed = !isInPictureInPictureMode &&
            !lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        pip?.onModeChanged(isInPictureInPictureMode, closed)
    }
}
