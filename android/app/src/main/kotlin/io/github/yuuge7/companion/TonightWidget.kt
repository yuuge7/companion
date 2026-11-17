package io.github.yuuge7.companion

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

class TonightWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        Thread { try { update(context) } finally { pending.finish() } }.start()
    }
    companion object {
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TonightWidget::class.java))
            if (ids.isNotEmpty()) context.sendBroadcast(Intent(context, TonightWidget::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
        }
        private fun update(context: Context) {
            val views = RemoteViews(context.packageName, R.layout.tonight_widget)
            var shortest: JSONObject? = null
            try {
                val entries = Backups.entries(context)
                for (i in 0 until entries.length()) {
                    val e = entries.getJSONObject(i)
                    val runtime = e.optInt("runtime", 0)
                    val complete = e.optString("kind") == "series" && e.optInt("episodes", 0) > 0 && e.optInt("watched", 0) >= e.optInt("episodes")
                    if (e.optString("status", "watchlist") == "watchlist" && runtime > 0 && !complete &&
                        (shortest == null || runtime < shortest.optInt("runtime"))) shortest = e
                }
                views.setTextViewText(R.id.widget_title, shortest?.optString("title") ?: "Nothing measured in your queue")
            } catch (_: Exception) { views.setTextViewText(R.id.widget_title, "Open your shelf to recover it") }
            if (context.getSharedPreferences("device", Context.MODE_PRIVATE).getBoolean("private", false)) {
                shortest = null
                views.setTextViewText(R.id.widget_title, "Library locked. Tap to unlock.")
            }
            val e = shortest
            views.setTextViewText(R.id.widget_runtime, if (e == null) "" else "${e.optInt("runtime")}")
            views.setTextViewText(R.id.widget_unit, if (e == null) "" else if (e.optString("kind") == "series") "min/ep" else "min")
            views.setTextViewText(R.id.widget_detail, if (e?.optString("kind") == "series") nextEpisode(e) else "Shortest sitting on your watchlist")
            val intent = Intent(context, MainActivity::class.java).setAction("io.github.yuuge7.companion.open.film").putExtra("companionMode", "film").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 4100, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            AppWidgetManager.getInstance(context).updateAppWidget(ComponentName(context, TonightWidget::class.java), views)
        }
        private fun nextEpisode(e: JSONObject): String {
            var left = e.optInt("watched", 0)
            val seasons = e.optJSONArray("seasons")
            if (seasons != null) for (i in 0 until seasons.length()) {
                val count = seasons.optInt(i)
                if (left < count) return "Next up · S${i + 1} E${left + 1}"
                left -= count
            }
            return "Next up · Episode ${e.optInt("watched", 0) + 1}"
        }
    }
}
