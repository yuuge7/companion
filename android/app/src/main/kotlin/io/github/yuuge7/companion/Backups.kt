package io.github.yuuge7.companion

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.job.JobService
import android.app.job.JobParameters
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

object Backups {
    const val JOB_ID = 7341
    private fun prefs(context: Context) = context.getSharedPreferences("screen-device", Context.MODE_PRIVATE)
    fun status(context: Context): Map<String, Any> {
        val p = prefs(context)
        return mapOf("enabled" to p.contains("folder"), "folder" to p.getString("folderName", "Chosen folder").orEmpty(),
            "lastBackup" to p.getLong("lastBackup", 0L), "error" to p.getString("error", "").orEmpty())
    }
    fun configure(context: Context, uri: Uri) {
        val old = prefs(context).getString("folder", null)
        val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
        val name = context.contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else "Chosen folder" } ?: "Chosen folder"
        prefs(context).edit().putString("folder", uri.toString()).putString("folderName", name)
            .remove("error").remove("lastBackup").commit()
        ensureScheduled(context)
        if (old != null && old != uri.toString()) release(context, old)
    }
    fun ensureScheduled(context: Context) {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (!prefs(context).contains("folder") || scheduler.getPendingJob(JOB_ID) != null) return
        try {
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, BackupJobService::class.java))
                .setPeriodic(7L * 24 * 60 * 60 * 1000, 6L * 60 * 60 * 1000).setPersisted(true).build()
            check(scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS)
        } catch (e: Exception) {
            NativeDiagnostics.record(context, e, "backup schedule")
            prefs(context).edit().putString("error", "Weekly scheduling failed. Choose the backup folder again.").commit()
        }
    }
    private fun release(context: Context, uri: String) {
        try { context.contentResolver.releasePersistableUriPermission(Uri.parse(uri),
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } catch (_: Exception) { }
    }
    fun disable(context: Context) {
        context.getSystemService(JobScheduler::class.java).cancel(JOB_ID)
        prefs(context).getString("folder", null)?.let { release(context, it) }
        prefs(context).edit().clear().commit()
    }
    fun entries(context: Context): JSONArray {
        val file = File(context.filesDir, "film/shelf-v2.json")
        if (file.exists()) {
            val root = JSONObject(file.readText())
            require(root.getInt("schemaVersion") == 2)
            val entries = root.getJSONArray("entries")
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                require(e.get("title") is String && e.getString("title").isNotBlank())
                require(e.get("id") is String && e.getString("id").isNotBlank())
            }
            return entries
        }
        return JSONArray(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.film-entries-v1", "[]"))
    }
    @Synchronized fun write(context: Context) {
        var created: Uri? = null
        try {
            val p = prefs(context)
            val tree = Uri.parse(requireNotNull(p.getString("folder", null)))
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val entries = entries(context)
            @Suppress("DEPRECATION") val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName
            val content = JSONObject().put("app", "Screen Companion").put("schemaVersion", 2)
                .put("exportedAt", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }.format(java.util.Date())).put("appVersion", version)
                .put("count", entries.length()).put("entries", entries).toString(2)
            val name = "screen-companion-auto-${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}.json"
            created = requireNotNull(DocumentsContract.createDocument(context.contentResolver, root, "application/json", name))
            context.contentResolver.openOutputStream(created, "wt").use { stream ->
                requireNotNull(stream).write(content.toByteArray(Charsets.UTF_8))
            }
            // Do not prune until the new backup can be read back intact.
            val verified = context.contentResolver.openInputStream(created).use { requireNotNull(it).bufferedReader().readText() }
            check(verified == content)
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val owned = mutableListOf<Pair<String, String>>()
            context.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val n = cursor.getString(1)
                    if (Regex("screen-companion-auto-[0-9]{13}-[0-9a-f]{8}\\.json").matches(n))
                        owned.add(n to cursor.getString(0))
                }
            }
            for ((_, id) in owned.sortedByDescending { it.first }.drop(3)) {
                check(DocumentsContract.deleteDocument(context.contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, id)))
            }
            p.edit().putLong("lastBackup", System.currentTimeMillis()).remove("error").commit()
        } catch (e: Exception) {
            NativeDiagnostics.record(context, e, "backup write")
            // Failed writes never count as a backup and never displace an older one.
            created?.let { try { DocumentsContract.deleteDocument(context.contentResolver, it) } catch (_: Exception) { } }
            prefs(context).edit().putString("error", "Backup failed. Reconnect the folder or free some space.").commit()
            throw e
        }
    }
}

object NativeDiagnostics {
    @Synchronized fun record(context: Context, error: Exception, source: String) {
        try {
            val file = File(context.filesDir, "native-diagnostics.txt")
            val old = if (file.exists()) file.readText().takeLast(8000) else ""
            file.writeText((old + "${System.currentTimeMillis()} $source: ${error.javaClass.simpleName}\n").takeLast(8000))
        } catch (_: Exception) { }
    }
}

class BackupJobService : JobService() {
    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
    override fun onStartJob(params: JobParameters): Boolean {
        executor.execute {
            var retry = false
            try { Backups.write(this) } catch (_: Exception) { retry = true }
            jobFinished(params, retry)
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean = true
    override fun onDestroy() { executor.shutdown(); super.onDestroy() }
}
