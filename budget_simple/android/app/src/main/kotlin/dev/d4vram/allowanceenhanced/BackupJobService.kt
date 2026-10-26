package dev.d4vram.allowanceenhanced

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** Runs a Dart-only entrypoint, never the financial UI or its notification startup. */
class BackupJobService : JobService() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var bridge: BackupBridge? = null
    private var parameters: JobParameters? = null
    private var timeout: Runnable? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (!getSharedPreferences("privacy_backup_native", MODE_PRIVATE).getBoolean("enabled", false)) return false
        if (engine != null) return false
        parameters = params
        return try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val worker = FlutterEngine(applicationContext)
            engine = worker
            bridge = BackupBridge(applicationContext, worker.dartExecutor.binaryMessenger, finished = { success -> complete(!success) })
            timeout = Runnable { complete(true) }.also { main.postDelayed(it, 120_000) }
            worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backupBackgroundMain"))
            true
        } catch (e: Exception) {
            // Errors carry no database contents or provider paths.
            getSharedPreferences("privacy_backup_native", MODE_PRIVATE).edit()
                .putString("lastError", "No se pudo iniciar la copia automática. Abre la app para revisar la configuración.").apply()
            cleanup()
            parameters = null
            false
        }
    }

    private fun complete(retry: Boolean) {
        val params = parameters ?: return
        parameters = null
        if (retry) getSharedPreferences("privacy_backup_native", MODE_PRIVATE).edit()
            .putString("lastError", "La copia automática no se completó. Android volverá a intentarlo.").apply()
        cleanup()
        jobFinished(params, retry)
    }

    private fun cleanup() {
        timeout?.let { main.removeCallbacks(it) }
        timeout = null
        bridge?.detach()
        bridge = null
        engine?.destroy()
        engine = null
    }

    override fun onStopJob(params: JobParameters): Boolean {
        parameters = null
        cleanup()
        return true
    }

    override fun onDestroy() {
        parameters = null
        cleanup()
        super.onDestroy()
    }
}
