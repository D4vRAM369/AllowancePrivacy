package dev.d4vram.allowanceenhanced

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var backupBridge: BackupBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupBridge = BackupBridge(this, flutterEngine.dartExecutor.binaryMessenger, this)
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
