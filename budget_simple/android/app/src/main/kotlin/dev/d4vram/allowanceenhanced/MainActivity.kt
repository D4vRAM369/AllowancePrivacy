package dev.d4vram.allowanceenhanced

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by local_auth's BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    private var backupBridge: BackupBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before Flutter draws anything, so not even the first frame leaks.
        applyScreenProtection()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupBridge = BackupBridge(this, flutterEngine.dartExecutor.binaryMessenger, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "allowance_privacy/screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "apply") {
                    applyScreenProtection()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    /** Reads the toggles Dart saved (shared_preferences stores them with a "flutter." prefix). */
    private fun applyScreenProtection() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (prefs.getBoolean("flutter.secureScreen", false)) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            setRecentsScreenshotEnabled(!prefs.getBoolean("flutter.hideInRecents", true))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupBridge?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backupBridge?.detach()
        backupBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
