package dev.d4vram.allowanceenhanced

import android.app.Activity
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.KeyStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only the app's engine can access this channel; document access is explicitly granted by SAF. */
class BackupBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    private val activity: Activity? = null,
    private val finished: ((Boolean) -> Unit)? = null
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "allowance_privacy/backup"
        const val JOB_ID = 47201
        const val MAX_BYTES = 20 * 1024 * 1024
        private const val REQUEST = 47202
        private const val ALIAS = "allowance_privacy_backup_material_v1"
        private const val PREFS = "privacy_backup_native"
        // A process-wide queue serializes foreground and headless operations and rotations.
        private val io = Executors.newSingleThreadExecutor()
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val prefs get() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var picker: PendingPicker? = null
    @Volatile private var detached = false
    private data class PendingPicker(val kind: String, val result: MethodChannel.Result, val bytes: ByteArray? = null)

    init { channel.setMethodCallHandler(this) }

    fun detach() {
        detached = true
        channel.setMethodCallHandler(null)
        picker?.result?.error("cancelled", "Operación interrumpida. Vuelve a intentarlo.", null)
        picker = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readDocument" -> showPicker("read", Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, result)
            "writeDocument" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime")
                if (bytes == null || bytes.size > MAX_BYTES || name.isNullOrBlank() || name.length > 200 || mime.isNullOrBlank()) {
                    result.error("invalid", "Archivo inválido o demasiado grande (máximo 20 MiB).", null)
                    return
                }
                showPicker("write", Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, name)
                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                }, result, bytes)
            }
            "pickBackupFolder" -> {
                if (Build.VERSION.SDK_INT < 21) {
                    result.error("unsupported", "Elegir carpeta requiere Android 5 o posterior.", null)
                    return
                }
                showPicker("folder", Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }, result)
            }
            "getAutoBackupStatus" -> work(result) {
                mapOf(
                    "enabled" to prefs.getBoolean("enabled", false),
                    "folderSelected" to (prefs.getString("folder", null) != null),
                    "intervalHours" to prefs.getInt("intervalHours", 24),
                    "retention" to prefs.getInt("retention", 7),
                    "lastSuccess" to if (prefs.contains("lastSuccess")) prefs.getLong("lastSuccess", 0) else null,
                    "lastError" to prefs.getString("lastError", null)
                )
            }
            "configureAutoBackup" -> work(result) { configure(call); true }
            "disableAutoBackup" -> work(result) {
                if (Build.VERSION.SDK_INT >= 21) scheduler().cancel(JOB_ID)
                check(prefs.edit().putBoolean("enabled", false).putString("generation", UUID.randomUUID().toString()).remove("material").remove("iv").remove("lastError").commit())
                true
            }
            "autoBackupMaterial" -> work(result) {
                if (!prefs.getBoolean("enabled", false)) null else unseal()
            }
            "writeAutoBackup" -> work(result) {
                val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                require(bytes.isNotEmpty() && bytes.size <= MAX_BYTES)
                check(prefs.getBoolean("enabled", false))
                try {
                    val generation = call.argument<String>("generation") ?: throw IllegalArgumentException()
                    writeAutomatic(bytes, generation)
                    true
                } catch (e: Exception) {
                    prefs.edit().putString("lastError", "No se pudo guardar la copia. Revisa carpeta, permisos y espacio.").commit()
                    throw e
                }
            }
            "backgroundFinished" -> {
                val ok = call.argument<Boolean>("success") ?: false
                result.success(true)
                if (!ok) io.execute {
                    prefs.edit().putString("lastError", "No se pudo completar la copia automática. Abre la app para revisar la configuración.").commit()
                }
                main.post { finished?.invoke(ok) }
            }
            else -> result.notImplemented()
        }
    }

    private fun showPicker(kind: String, intent: Intent, result: MethodChannel.Result, bytes: ByteArray? = null) {
        if (activity == null) {
            result.error("unavailable", "Esta operación necesita una pantalla abierta.", null)
            return
        }
        if (picker != null) {
            result.error("busy", "Termina la selección de archivo actual.", null)
            return
        }
        picker = PendingPicker(kind, result, bytes)
        try { activity.startActivityForResult(intent, REQUEST) }
        catch (e: Exception) {
            picker = null
            result.error("unavailable", "No se pudo abrir el selector de documentos.", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val pending = picker ?: return true
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.result.success(if (pending.kind == "read") null else false)
            return true
        }
        work(pending.result) {
            when (pending.kind) {
                "read" -> context.contentResolver.openInputStream(uri)?.use { readLimited(it) }
                    ?: throw IllegalStateException()
                "write" -> {
                    context.contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                        stream.write(pending.bytes!!)
                        stream.flush()
                    } ?: throw IllegalStateException()
                    true
                }
                else -> {
                    if (Build.VERSION.SDK_INT < 21) throw IllegalStateException()
                    val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    check(flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0 && flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
                    context.contentResolver.takePersistableUriPermission(uri, flags)
                    check(prefs.edit().putString("folder", uri.toString()).putString("generation", UUID.randomUUID().toString()).commit())
                    true
                }
            }
        }
        return true
    }

    private fun work(result: MethodChannel.Result, action: () -> Any?) {
        io.execute {
            try {
                checkActive()
                val value = action()
                main.post { if (!detached) result.success(value) }
            } catch (e: Exception) {
                // Never return file paths, passwords, keys or provider exception contents.
                val message = if (e is UnsupportedOperationException) "AutoBackup cifrado requiere Android 6 o posterior."
                    else "No se pudo completar la operación. Comprueba el archivo, permisos y espacio disponible."
                main.post { if (!detached) result.error("backup_failed", message, null) }
            }
        }
    }

    private fun checkActive() {
        check(!detached) { "Backup operation cancelled" }
    }

    private fun checkGeneration(generation: String) {
        checkActive()
        check(prefs.getBoolean("enabled", false) && prefs.getString("generation", null) == generation)
    }

    private fun scheduler(): JobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler

    private fun configure(call: MethodCall) {
        if (Build.VERSION.SDK_INT < 23) throw UnsupportedOperationException()
        val key = call.argument<ByteArray>("key") ?: throw IllegalArgumentException()
        val salt = call.argument<ByteArray>("salt") ?: throw IllegalArgumentException()
        val hours = call.argument<Int>("intervalHours") ?: 24
        val retention = call.argument<Int>("retention") ?: 7
        require(key.size == 32 && salt.size == 16 && hours in listOf(24, 168) && retention in listOf(3, 7, 14))
        check(prefs.getString("folder", null) != null)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey())
        val material = key + salt
        key.fill(0)
        val sealed = try { cipher.doFinal(material) } finally { material.fill(0) }
        val job = JobInfo.Builder(JOB_ID, ComponentName(context, BackupJobService::class.java))
            .setPeriodic(hours.toLong() * 60 * 60 * 1000)
            .setPersisted(true)
            .setRequiresCharging(false)
            .build()
        val configurationKeys = setOf("material", "iv", "intervalHours", "retention", "enabled", "generation", "lastError")
        val previous = prefs.all.filterKeys { it in configurationKeys }
        val previousJob = scheduler().allPendingJobs.firstOrNull { it.id == JOB_ID }
        try {
            checkActive()
            // Publish configuration first: a newly scheduled worker must never see stale keys.
            check(prefs.edit()
                .putString("material", Base64.encodeToString(sealed, Base64.NO_WRAP))
                .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .putInt("intervalHours", hours).putInt("retention", retention)
                .putString("generation", UUID.randomUUID().toString())
                .putBoolean("enabled", true).remove("lastError").commit())
            checkActive()
            check(scheduler().schedule(job) == JobScheduler.RESULT_SUCCESS)
        } catch (failure: Exception) {
            // Keep the previous usable configuration and schedule if either step failed.
            val rollback = prefs.edit()
            configurationKeys.forEach { rollback.remove(it) }
            previous.forEach { (key, value) ->
                when (value) {
                    is String -> rollback.putString(key, value)
                    is Int -> rollback.putInt(key, value)
                    is Boolean -> rollback.putBoolean(key, value)
                }
            }
            val restored = rollback.commit()
            val restoredJob = if (previousJob == null) {
                scheduler().cancel(JOB_ID)
                true
            } else scheduler().schedule(previousJob) == JobScheduler.RESULT_SUCCESS
            if (!restored || !restoredJob) {
                prefs.edit().putString("lastError", "No se pudo restaurar la programación anterior. Revisa AutoBackup antes de continuar.").commit()
            }
            throw failure
        }
    }

    private fun wrappingKey(): SecretKey {
        if (Build.VERSION.SDK_INT < 23) throw UnsupportedOperationException()
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                // Scheduled backups cannot depend on an interactive authentication prompt.
                .setUserAuthenticationRequired(false)
                .build())
        }.generateKey()
    }

    private fun unseal(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < 23) throw UnsupportedOperationException()
        val sealed = Base64.decode(prefs.getString("material", null) ?: throw IllegalStateException(), Base64.NO_WRAP)
        val iv = Base64.decode(prefs.getString("iv", null) ?: throw IllegalStateException(), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, wrappingKey(), GCMParameterSpec(128, iv))
        val material = cipher.doFinal(sealed)
        try {
            check(material.size == 48)
            return mapOf("key" to material.copyOfRange(0, 32), "salt" to material.copyOfRange(32, 48), "generation" to (prefs.getString("generation", null) ?: throw IllegalStateException()))
        } finally { material.fill(0) }
    }

    private fun readLimited(input: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val block = ByteArray(8192)
        while (true) {
            checkActive()
            val n = input.read(block)
            if (n < 0) break
            check(output.size() + n <= MAX_BYTES)
            output.write(block, 0, n)
        }
        return output.toByteArray()
    }

    private fun writeAutomatic(bytes: ByteArray, generation: String) {
        checkGeneration(generation)
        if (Build.VERSION.SDK_INT < 21) throw UnsupportedOperationException()
        val tree = Uri.parse(prefs.getString("folder", null) ?: throw IllegalStateException())
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val date = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
        var created: Uri? = null
        var verified = false
        try {
            checkGeneration(generation)
            created = DocumentsContract.createDocument(context.contentResolver, parent, "application/octet-stream", "allowance-$date-${UUID.randomUUID()}.apbackup") ?: throw IllegalStateException()
            checkGeneration(generation)
            context.contentResolver.openOutputStream(created, "wt")?.use { output ->
                var offset = 0
                while (offset < bytes.size) {
                    checkGeneration(generation)
                    val count = minOf(8192, bytes.size - offset)
                    output.write(bytes, offset, count)
                    offset += count
                }
                checkGeneration(generation)
                output.flush()
            } ?: throw IllegalStateException()
            checkGeneration(generation)
            val readBack = context.contentResolver.openInputStream(created)?.use { readLimited(it) } ?: throw IllegalStateException()
            check(readBack.contentEquals(bytes))
            checkGeneration(generation)
            verified = true
            val previous = JSONArray(prefs.getString("ownedCopies", "[]"))
            val tracked = mutableListOf<String>()
            for (index in 0 until previous.length()) tracked.add(previous.getString(index))
            tracked.add(created.toString())
            // Persist the new verified copy before attempting any deletion.
            check(prefs.edit().putString("ownedCopies", JSONArray(tracked).toString())
                .putLong("lastSuccess", System.currentTimeMillis()).remove("lastError").commit())
            val keep = prefs.getInt("retention", 7)
            while (tracked.size > keep) {
                checkGeneration(generation)
                val oldest = Uri.parse(tracked.first())
                // Delete only URIs this installation recorded when creating a backup.
                try {
                    checkGeneration(generation)
                    if (!DocumentsContract.deleteDocument(context.contentResolver, oldest)) break
                    tracked.removeAt(0)
                } catch (e: Exception) { break }
            }
            checkGeneration(generation)
            val updated = prefs.edit().putString("ownedCopies", JSONArray(tracked).toString())
            if (tracked.size > keep) updated.putString("lastError", "Copia guardada, pero no se pudieron retirar copias antiguas. Revisa los permisos de la carpeta.")
            updated.commit()
        } finally {
            // After cancellation do not start even cleanup deletes: retain an orphan rather than mutate storage.
            if (!verified && created != null && !detached) {
                try { DocumentsContract.deleteDocument(context.contentResolver, created) } catch (ignored: Exception) { }
            }
        }
    }
}
