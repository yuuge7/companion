package io.github.yuuge7.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/**
 * Handles the widget's buttons. Not exported: only PendingIntents created
 * by this app can reach it.
 */
class WidgetActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (context.getSharedPreferences("device", Context.MODE_PRIVATE).getBoolean("private", false)) return
        val id = intent.getStringExtra(EXTRA_ENTRY_ID) ?: return
        val action = intent.action ?: return
        val app = context.applicationContext
        // A large shelf takes a moment to parse, so work off the main thread,
        // one tap at a time so two quick taps cannot overwrite each other.
        val pending = goAsync()
        worker.execute {
            var changed = false
            try {
                changed = when (action) {
                    ACTION_BUMP -> MangaShelfStore.bump(app, id)
                    ACTION_MARK_READ -> MangaShelfStore.markRead(app, id)
                    else -> false
                }
            } finally {
                Handler(Looper.getMainLooper()).post {
                    try {
                        MangaReadingWidget.refreshAll(app)
                        if (changed) MangaShelfStore.onChanged?.invoke()
                    } finally {
                        pending.finish()
                    }
                }
            }
        }
    }

    companion object {
        const val ACTION_BUMP = "dev.ionel.manga_companion.widget.BUMP"
        const val ACTION_MARK_READ = "dev.ionel.manga_companion.widget.MARK_READ"
        const val EXTRA_ENTRY_ID = "entryId"

        private val worker = Executors.newSingleThreadExecutor()
    }
}
