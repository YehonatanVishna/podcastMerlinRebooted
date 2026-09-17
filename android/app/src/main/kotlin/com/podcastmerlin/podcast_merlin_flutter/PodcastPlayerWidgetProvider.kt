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
import android.view.View
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
                val podcastSubtitle = widgetData.getString("widget_podcast", null) ?: "Tap to open player"
                val isBuffering = widgetData.getBoolean("widget_is_buffering", false)
                val subtitle = if (isBuffering) "Buffering..." else podcastSubtitle
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_subtitle, subtitle)

                // Playback status (isPlaying & isBuffering)
                val isPlaying = widgetData.getBoolean("widget_is_playing", false)
                if (isBuffering) {
                    setViewVisibility(R.id.widget_buffering_spinner, View.VISIBLE)
                    setImageViewResource(R.id.widget_btn_play_pause, 0)
                } else {
                    setViewVisibility(R.id.widget_buffering_spinner, View.GONE)
                    setImageViewResource(
                        R.id.widget_btn_play_pause,
                        if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
                    )
                }

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
                    // Match 10dp corner radius on 54dp container proportionally
                    val cornerRadius = loadedBitmap.width * (10f / 54f)
                    val rounded = getRoundedCornerBitmap(loadedBitmap, cornerRadius)
                    if (rounded != loadedBitmap) {
                        loadedBitmap.recycle()
                    }
                    setImageViewBitmap(R.id.widget_artwork, rounded)
                } else {
                    setImageViewResource(R.id.widget_artwork, R.drawable.ic_widget_placeholder)
                }

                // Action buttons: MediaButton PendingIntents to AudioService MediaButtonReceiver
                val playPauseIntent = createMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 201)
                setOnClickPendingIntent(R.id.widget_btn_play_pause, playPauseIntent)
                setOnClickPendingIntent(R.id.widget_buffering_spinner, playPauseIntent)
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
            if (options.outWidth <= 0 || options.outHeight <= 0) return null

            var sampleSize = 1
            while (options.outWidth / sampleSize > maxDimension ||
                options.outHeight / sampleSize > maxDimension
            ) {
                sampleSize *= 2
            }
            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
            }
            val decoded = BitmapFactory.decodeFile(path, decodeOptions) ?: return null

            // Center-crop to square and scale down to maxDimension for uniform RemoteViews rendering
            val minEdge = Math.min(decoded.width, decoded.height)
            val xOffset = (decoded.width - minEdge) / 2
            val yOffset = (decoded.height - minEdge) / 2
            val cropped = Bitmap.createBitmap(decoded, xOffset, yOffset, minEdge, minEdge)
            if (cropped != decoded) {
                decoded.recycle()
            }
            val targetSize = Math.min(minEdge, maxDimension)
            val scaled = if (cropped.width != targetSize) {
                val s = Bitmap.createScaledBitmap(cropped, targetSize, targetSize, true)
                if (s != cropped) {
                    cropped.recycle()
                }
                s
            } else {
                cropped
            }
            scaled
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
