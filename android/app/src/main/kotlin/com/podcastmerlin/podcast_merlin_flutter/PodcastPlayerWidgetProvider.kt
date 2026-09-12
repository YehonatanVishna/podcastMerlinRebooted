package com.podcastmerlin.podcast_merlin_flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class PodcastPlayerWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_podcast_player).apply {
                // Open App on widget click
                val openAppIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, openAppIntent)
                setOnClickPendingIntent(R.id.widget_info_container, openAppIntent)
                setOnClickPendingIntent(R.id.widget_artwork, openAppIntent)

                // Track title & podcast subtitle
                val title = widgetData.getString("widget_title", null) ?: "Podcast Merlin"
                val subtitle = widgetData.getString("widget_podcast", null) ?: "Tap to open player"
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_subtitle, subtitle)

                // Playback status (isPlaying)
                val isPlaying = widgetData.getBoolean("widget_is_playing", false)
                setImageViewResource(
                    R.id.widget_btn_play_pause,
                    if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
                )

                // Progress (0 to 100)
                val progress = widgetData.getInt("widget_progress", 0)
                setProgressBar(R.id.widget_progress_bar, 100, progress.coerceIn(0, 100), false)

                // Artwork
                val artworkPath = widgetData.getString("widget_artwork_path", null)
                var loadedBitmap: Bitmap? = null
                if (!artworkPath.isNullOrEmpty()) {
                    val file = File(artworkPath)
                    if (file.exists()) {
                        loadedBitmap = loadScaledBitmap(file.absolutePath, 256)
                    }
                }

                if (loadedBitmap != null) {
                    val rounded = getRoundedCornerBitmap(loadedBitmap, 18f)
                    setImageViewBitmap(R.id.widget_artwork, rounded)
                } else {
                    setImageViewResource(R.id.widget_artwork, R.drawable.ic_widget_placeholder)
                }

                // Action buttons: MediaButton PendingIntents to AudioService MediaButtonReceiver
                setOnClickPendingIntent(
                    R.id.widget_btn_play_pause,
                    createMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 201)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_rewind,
                    createMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_REWIND, 202)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_fast_forward,
                    createMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, 203)
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun loadScaledBitmap(path: String, maxDimension: Int): Bitmap? {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(path, options)
            var sampleSize = 1
            while (options.outWidth / (sampleSize * 2) >= maxDimension &&
                options.outHeight / (sampleSize * 2) >= maxDimension
            ) {
                sampleSize *= 2
            }
            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
            }
            BitmapFactory.decodeFile(path, decodeOptions)
        } catch (e: Exception) {
            null
        }
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadiusPx: Float): Bitmap {
        return try {
            val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = Rect(0, 0, bitmap.width, bitmap.height)
            val rectF = RectF(rect)
            canvas.drawRoundRect(rectF, cornerRadiusPx, cornerRadiusPx, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(bitmap, rect, rect, paint)
            output
        } catch (e: Exception) {
            bitmap
        }
    }

    private fun createMediaButtonIntent(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }
}
