package com.medtroniclabs.uhis_next

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Keeps the app process in the foreground-service state for the duration of an
 * offline sync, so Android's cached-process freezer and Doze network
 * restrictions cannot suspend it mid-pull.
 *
 * Deliberately contains **no sync logic**. A full sync measures ~113 s
 * time-to-first-byte against production while the device screen timeout is
 * 30 s, so the work has to survive the screen going off — but the work itself
 * stays in Dart, in the same isolate, with the same database handle and HTTP
 * session. This class only holds the process up and renders a notification.
 *
 * All text arrives already localized from Dart (`app_strings.dart` is the
 * single localization seam); nothing here builds user-facing copy.
 */
class SyncForegroundService : Service() {

    companion object {
        private const val TAG = "SyncForegroundService"

        const val CHANNEL_ID = "uhis_sync_progress"
        const val NOTIFICATION_ID = 4711
        /** Separate id so a failure notice can outlive the foreground one. */
        const val FAILURE_NOTIFICATION_ID = 4712

        const val ACTION_START = "com.medtroniclabs.uhis_next.SYNC_START"
        const val ACTION_UPDATE = "com.medtroniclabs.uhis_next.SYNC_UPDATE"
        const val ACTION_STOP = "com.medtroniclabs.uhis_next.SYNC_STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_DONE = "done"
        const val EXTRA_TOTAL = "total"

        /** Channel name is localized copy passed down from Dart on first start. */
        const val EXTRA_CHANNEL_NAME = "channelName"
    }

    private var title: String = ""
    private var channelName: String = "Data sync"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
                intent.getStringExtra(EXTRA_CHANNEL_NAME)?.let { channelName = it }
                ensureChannel()
                startInForeground(
                    text = intent.getStringExtra(EXTRA_TEXT).orEmpty(),
                    done = intent.getIntExtra(EXTRA_DONE, 0),
                    total = intent.getIntExtra(EXTRA_TOTAL, 0),
                )
            }

            ACTION_UPDATE -> {
                ensureChannel()
                notificationManager().notify(
                    NOTIFICATION_ID,
                    buildNotification(
                        text = intent.getStringExtra(EXTRA_TEXT).orEmpty(),
                        done = intent.getIntExtra(EXTRA_DONE, 0),
                        total = intent.getIntExtra(EXTRA_TOTAL, 0),
                        ongoing = true,
                    ),
                )
            }

            ACTION_STOP -> stopSelfAndForeground()

            else -> Log.w(TAG, "unknown action: ${intent?.action}")
        }
        // Not sticky: if the process dies there is no in-flight sync left to
        // resume, and a system restart with no context would be worse than
        // simply not running.
        return START_NOT_STICKY
    }

    /**
     * Android 15 stops a `dataSync` foreground service that exceeds its
     * cumulative 6-hour daily budget. A sync takes minutes, so this should
     * never fire — but exit cleanly rather than being force-stopped if it does.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "dataSync FGS timed out (Android 15 budget) — stopping")
        stopSelfAndForeground()
    }

    private fun startInForeground(text: String, done: Int, total: Int) {
        val notification = buildNotification(text, done, total, ongoing = true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopSelfAndForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun buildNotification(
        text: String,
        done: Int,
        total: Int,
        ongoing: Boolean,
    ): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(contentIntent)
            .setOngoing(ongoing)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .apply {
                // Determinate only when the caller knows the total; otherwise a
                // spinner, which is honest about unknown-length work.
                if (total > 0) setProgress(total, done, false) else setProgress(0, 0, true)
            }
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val existing = notificationManager().getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        // IMPORTANCE_LOW: no sound, no heads-up — a multi-minute sync must not
        // buzz the SK's phone.
        val channel = NotificationChannel(
            CHANNEL_ID,
            channelName,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
