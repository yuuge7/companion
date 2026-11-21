package io.github.yuuge7.companion

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Generates real .companion archives, even when there is no Activity/Flutter UI. */
object CompleteBackups {
    const val CHANNEL = "io.github.yuuge7.companion/backups"
    const val JOB_ID = 7342
    private const val MAX_BYTES = 150L * 1024 * 1024
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    var foreground: MethodChannel? = null
    private fun prefs(context: Context) = context.getSharedPreferences("companion-backups", Context.MODE_PRIVATE)
    fun usesFolder(context: Context, uri: String) = prefs(context).getString("folder", null) == uri
    fun status(context: Context): Map<String, Any> {
        val p = prefs(context)
        val scheduled = context.getSystemService(JobScheduler::class.java).getPendingJob(JOB_ID) != null
        return mapOf("enabled" to p.contains("folder"), "scheduled" to scheduled,
            "folder" to p.getString("folderName", "Chosen folder").orEmpty(),
            "hours" to p.getInt("hours", 168), "lastBackup" to p.getLong("lastBackup", 0L),
            "error" to p.getString("error", "").orEmpty(), "running" to running.get())
    }
    fun configure(context: Context, uri: Uri) {
        check(!running.get()) { "A complete backup is running" }
        val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
        val name = context.contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else "Chosen folder" } ?: "Chosen folder"
        val old = prefs(context).getString("folder", null)
        prefs(context).edit().putString("folder", uri.toString()).putString("folderName", name)
            .remove("lastBackup").remove("error").commit()
        ensureScheduled(context)
        if (old != null && old != uri.toString()) release(context, old)
    }
    private fun release(context: Context, uri: String) {
        // Android grants belong to the app, so keep a grant used by film backups.
        if (context.getSharedPreferences("screen-device", Context.MODE_PRIVATE).getString("folder", null) == uri) return
        try { context.contentResolver.releasePersistableUriPermission(Uri.parse(uri),
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } catch (_: Exception) { }
    }
    fun setFrequency(context: Context, hours: Int) {
        check(!running.get()) { "A complete backup is running" }
        require(hours == 24 || hours == 168)
        prefs(context).edit().putInt("hours", hours).commit()
        context.getSystemService(JobScheduler::class.java).cancel(JOB_ID)
        ensureScheduled(context)
    }
    fun ensureScheduled(context: Context) {
        if (!prefs(context).contains("folder")) return
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (scheduler.getPendingJob(JOB_ID) != null) return
        try {
            val interval = prefs(context).getInt("hours", 168) * 60L * 60 * 1000
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, CompleteBackupJobService::class.java))
                .setPeriodic(interval, 60L * 60 * 1000).setPersisted(true).build()
            check(scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS)
            prefs(context).edit().remove("error").commit()
        } catch (e: Exception) {
            NativeDiagnostics.record(context, e, "complete backup schedule")
            prefs(context).edit().putString("error", "Scheduling failed. Choose the backup folder again.").commit()
        }
    }
    fun disable(context: Context) {
        check(!running.get()) { "A complete backup is running" }
        context.getSystemService(JobScheduler::class.java).cancel(JOB_ID)
        val old = prefs(context).getString("folder", null)
        prefs(context).edit().clear().commit()
        if (old != null) release(context, old)
    }

    /** Called on the main thread. The returned cancellation callback is used by JobScheduler. */
    fun run(context: Context, completion: (String?) -> Unit): () -> Unit {
        val app = context.applicationContext
        if (!prefs(app).contains("folder")) { completion("Choose a backup folder first."); return {} }
        if (!running.compareAndSet(false, true)) { completion("A complete backup is already running."); return {} }
        val cancelled = AtomicBoolean(false)
        var engine: FlutterEngine? = null
        var finished = false
        val staged = File(app.filesDir, "companion-auto/${UUID.randomUUID()}.companion")
        var timeout: Runnable? = null
        fun finish(error: String?) {
            staged.delete()
            File("${staged.path}.tmp").delete()
            if (finished) return
            finished = true
            timeout?.let { handler.removeCallbacks(it) }
            engine?.destroy()
            engine = null
            if (error != null) prefs(app).edit().putString("error", error).commit()
            running.set(false)
            completion(error)
        }
        timeout = Runnable {
            cancelled.set(true)
            finish("Backup timed out. Open Companion and try Back up now.")
        }
        handler.postDelayed(timeout!!, 180000)
        fun request(channel: MethodChannel) {
            channel.invokeMethod("prepare", staged.absolutePath, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (finished) { staged.delete(); return }
                    if (cancelled.get()) { staged.delete(); finish("Backup interrupted. Android will retry."); return }
                    if (result != true) { finish("Could not prepare a complete backup."); return }
                    executor.execute {
                        val error = try { write(app, staged, cancelled); null } catch (e: Exception) {
                            NativeDiagnostics.record(app, e, "complete backup write")
                            "Backup failed. Reconnect the folder or free some space. Older backups were kept."
                        }
                        handler.post { finish(error) }
                    }
                }
                override fun error(code: String, message: String?, details: Any?) {
                    finish("Could not prepare the complete backup. Resolve any library recovery or save errors, then try again.")
                }
                override fun notImplemented() { finish("Open Companion and try Back up now.") }
            })
        }
        try {
            val active = foreground
            if (active != null) request(active) else {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(app)
                loader.ensureInitializationComplete(app, null)
                val background = FlutterEngine(app)
                engine = background
                val channel = MethodChannel(background.dartExecutor.binaryMessenger, CHANNEL)
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "ready") {
                        result.success(null)
                        if (!finished) request(channel)
                    } else result.notImplemented()
                }
                background.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(), "package:companion/main.dart", "companionBackupMain"))
            }
        } catch (e: Exception) {
            NativeDiagnostics.record(app, e, "complete backup prepare")
            finish("Could not start a complete backup. Open Companion and try again.")
        }
        return {
            cancelled.set(true)
            // Keep serialization ownership until preparation/copy acknowledges
            // cancellation (or times out); a retry must not reuse the same file.
        }
    }

    private fun write(context: Context, staged: File, cancelled: AtomicBoolean) {
        check(staged.isFile && staged.length() in 1..MAX_BYTES)
        val p = prefs(context)
        val tree = Uri.parse(requireNotNull(p.getString("folder", null)))
        val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val name = "companion-auto-${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}.companion"
        var created: Uri? = null
        try {
            check(!cancelled.get())
            created = requireNotNull(DocumentsContract.createDocument(context.contentResolver, root, "application/octet-stream", "$name.pending"))
            val expected = MessageDigest.getInstance("SHA-256")
            context.contentResolver.openOutputStream(created, "wt").use { output ->
                requireNotNull(output)
                staged.inputStream().use { input ->
                    val buffer = ByteArray(65536)
                    var count = input.read(buffer)
                    while (count >= 0) {
                        check(!cancelled.get())
                        expected.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                        count = input.read(buffer)
                    }
                }
            }
            val actual = MessageDigest.getInstance("SHA-256")
            var size = 0L
            context.contentResolver.openInputStream(created).use { input ->
                requireNotNull(input)
                val buffer = ByteArray(65536)
                var count = input.read(buffer)
                while (count >= 0) {
                    check(!cancelled.get())
                    size += count
                    check(size <= MAX_BYTES)
                    actual.update(buffer, 0, count)
                    count = input.read(buffer)
                }
            }
            check(!cancelled.get() && size == staged.length() && expected.digest().contentEquals(actual.digest()))
            // An interrupted write can leave a partial document if its grant is
            // revoked. Only verified, finalized archives participate in retention.
            created = requireNotNull(DocumentsContract.renameDocument(context.contentResolver, created, name))
        } catch (e: Exception) {
            created?.let { try { DocumentsContract.deleteDocument(context.contentResolver, it) } catch (_: Exception) { } }
            throw e
        }
        p.edit().putLong("lastBackup", System.currentTimeMillis()).remove("error").commit()
        // Retention happens only after a successful read-back. A pruning failure
        // must never delete the newly verified archive or misreport a failed save.
        try {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val owned = mutableListOf<Pair<String, String>>()
            context.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val n = cursor.getString(1)
                    if (Regex("companion-auto-[0-9]{13}-[0-9a-f]{8}\\.companion").matches(n))
                        owned.add(n to cursor.getString(0))
                    else if (Regex("companion-auto-[0-9]{13}-[0-9a-f]{8}\\.companion\\.pending").matches(n)) {
                        DocumentsContract.deleteDocument(context.contentResolver,
                            DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0)))
                    }
                }
            }
            // Keep the archive just verified even if the device clock moved back.
            for ((_, id) in owned.filter { it.first != name }.sortedByDescending { it.first }.drop(2)) {
                check(DocumentsContract.deleteDocument(context.contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, id)))
            }
        } catch (e: Exception) {
            NativeDiagnostics.record(context, e, "complete backup retention")
            p.edit().putString("error", "Backup saved. Some older automatic backups could not be removed.").commit()
        } finally { staged.delete() }
    }
}

class CompleteBackupJobService : JobService() {
    private var cancel: (() -> Unit)? = null
    override fun onStartJob(params: JobParameters): Boolean {
        cancel = CompleteBackups.run(this) { error ->
            cancel = null
            jobFinished(params, error != null)
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { cancel?.invoke(); cancel = null; return true }
}
