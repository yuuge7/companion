package io.github.yuuge7.companion

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var bookChannel: MethodChannel? = null
    private var modeChannel: MethodChannel? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        if (getSharedPreferences("device", MODE_PRIVATE).getBoolean("secure", false))
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        modeChannel?.invokeMethod("openMode", intent.getStringExtra("companionMode"))
        bookChannel?.invokeMethod("openBook", intent.getStringExtra("bookId"))
        intent.removeExtra("companionMode")
        intent.removeExtra("bookId")
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MangaShelfStore.onChanged = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    private var pendingResult: MethodChannel.Result? = null
    private var pendingContent: String? = null
    private var folderResult: MethodChannel.Result? = null
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bookChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "book_companion/device")
        bookChannel!!.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("device", MODE_PRIVATE)
            when (call.method) {
                "pinWidget" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    result.success(Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported &&
                        manager.requestPinAppWidget(ComponentName(this, BookReadingWidget::class.java), null, null))
                }
                "appLockEnabled" -> result.success(prefs.getBoolean("private", false))
                "securePreviewEnabled" -> result.success((window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
                "securePreview" -> {
                    val secure = call.arguments == true
                    prefs.edit().putBoolean("secure", secure).apply()
                    if (secure) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "widgetPrivacy" -> {
                    prefs.edit().putBoolean("private", call.arguments == true).apply()
                    BookReadingWidget.refresh(this)
                    MangaReadingWidget.refreshAll(this)
                    TonightWidget.refresh(this)
                    result.success(null)
                }
                "updateWidget" -> {
                    val editor = prefs.edit()
                    for (key in listOf("id", "title", "progress")) {
                        editor.putString(key, call.argument<String>(key) ?: "")
                    }
                    editor.putInt("percent", call.argument<Int>("percent") ?: 0).apply()
                    BookReadingWidget.refresh(this)
                    MangaReadingWidget.refreshAll(this)
                    TonightWidget.refresh(this)
                    result.success(null)
                }
                "initialBook" -> {
                    result.success(intent.getStringExtra("bookId"))
                    intent.removeExtra("bookId")
                }
                else -> result.notImplemented()
            }
        }
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "io.github.yuuge7.companion/isbn").setMethodCallHandler { call, result ->
            if (call.method != "scan") {
                result.notImplemented()
            } else {
                val options = com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions.Builder()
                    .setBarcodeFormats(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_13)
                    .enableAutoZoom()
                    .build()
                com.google.mlkit.vision.codescanner.GmsBarcodeScanning.getClient(this, options)
                    .startScan()
                    .addOnSuccessListener { barcode -> result.success(barcode.rawValue) }
                    .addOnCanceledListener { result.success(null) }
                    .addOnFailureListener { result.error("scanner_unavailable", "Enter the ISBN manually.", null) }
            }
        }
        modeChannel = MethodChannel(messenger, "io.github.yuuge7.companion/navigation")
        modeChannel!!.setMethodCallHandler { call, result ->
            if (call.method == "initialMode") {
                result.success(intent.getStringExtra("companionMode"))
                intent.removeExtra("companionMode")
            } else result.notImplemented()
        }
        val mangaWidget = MethodChannel(messenger, "dev.ionel.manga_companion/widget")
        mangaWidget.setMethodCallHandler { call, result ->
            if (call.method == "refresh") { MangaReadingWidget.refreshAll(this); result.success(null) }
            else result.notImplemented()
        }
        MangaShelfStore.onChanged = { mangaWidget.invokeMethod("shelfChanged", null) }

        Backups.ensureScheduled(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> onMethodCall(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.ionel.movie_companion/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "backupStatus" -> result.success(Backups.status(this))
                    "chooseBackupFolder" -> {
                        if (folderResult != null) {
                            result.error("busy", "A folder picker is already open", null)
                        } else {
                            folderResult = result
                            try {
                                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                                    putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                                }, 0x4A54)
                            } catch (e: Exception) {
                                folderResult = null
                                result.error("no_picker", "No folder picker available", null)
                            }
                        }
                    }
                    "disableBackup" -> {
                        Backups.disable(this)
                        result.success(null)
                    }
                    "backupNow" -> io.execute {
                        try {
                            Backups.write(this)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("backup_failed", "Folder unavailable or out of space", null) }
                        }
                    }
                    "refreshWidget" -> {
                        TonightWidget.refresh(this)
                        result.success(null)
                    }
                    "pinWidget" -> {
                        val manager = AppWidgetManager.getInstance(this)
                        if (Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported) {
                            manager.requestPinAppWidget(ComponentName(this, TonightWidget::class.java), null, null)
                            result.success(null)
                        } else result.error("unsupported", "Add the widget from your home screen's widget picker", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveFile") {
            result.notImplemented()
            return
        }
        if (pendingResult != null) {
            result.error("busy", "A save dialog is already open", null)
            return
        }
        val fileName = call.argument<String>("fileName")
        val content = call.argument<String>("content")
        if (fileName == null || content == null) {
            result.error("bad_args", "fileName and content are required", null)
            return
        }

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mimeType") ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, fileName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, downloadsUri())
            }
        }

        pendingResult = result
        pendingContent = content
        try {
            startActivityForResult(intent, CREATE_DOCUMENT_REQUEST)
        } catch (e: Exception) {
            pendingResult = null
            pendingContent = null
            result.error("no_picker", "This device has no file picker available", null)
        }
    }

    /** Makes the picker open on Downloads rather than wherever it was left last. */
    private fun downloadsUri(): Uri = DocumentsContract.buildDocumentUri(
        EXTERNAL_STORAGE_AUTHORITY,
        "primary:${Environment.DIRECTORY_DOWNLOADS}",
    )

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == 0x4A54) {
            val result = folderResult ?: return
            folderResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result.success(false); return }
            try {
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(uri, flags)
                Backups.configure(this, uri)
                result.success(true)
            } catch (e: Exception) { result.error("permission", "Could not keep access to this folder", null) }
            return
        }
        if (requestCode != CREATE_DOCUMENT_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult ?: return
        val content = pendingContent.orEmpty()
        pendingResult = null
        pendingContent = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // picker dismissed, nothing to report
            return
        }
        io.execute { try {
            // "wt" truncates, so picking an existing file overwrites it cleanly.
            contentResolver.openOutputStream(uri, "wt").use { stream ->
                requireNotNull(stream) { "Could not open the chosen file for writing" }
                stream.write(content.toByteArray(Charsets.UTF_8))
            }
            val name = displayName(uri) ?: uri.lastPathSegment
            runOnUiThread { result.success(name) }
        } catch (e: Exception) {
            NativeDiagnostics.record(this, e, "export write")
            runOnUiThread { result.error("write_failed", "Could not write the file", null) }
        } }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
            }

    companion object {
        private const val CHANNEL = "io.github.yuuge7.companion/export"
        private const val CREATE_DOCUMENT_REQUEST = 0x4A53
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    }
}
