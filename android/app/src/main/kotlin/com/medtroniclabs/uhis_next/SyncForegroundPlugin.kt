package com.medtroniclabs.uhis_next

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val TAG = "SyncForeground"

/**
 * MethodChannel bridge to [SyncForegroundService]. Mirrors [MicroCoachingPlugin]'s
 * structure so both native bridges read the same way.
 *
 * Every user-facing string is passed in from Dart — `app_strings.dart` remains
 * the single localization seam.
 */
class SyncForegroundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.medtroniclabs.uhis_next/sync_foreground"
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val intent = serviceIntent(SyncForegroundService.ACTION_START, call).apply {
                    putExtra(
                        SyncForegroundService.EXTRA_CHANNEL_NAME,
                        call.argument<String>("channelName").orEmpty(),
                    )
                }
                try {
                    // Android 12+ forbids starting a foreground service from the
                    // background. A connectivity-triggered AutomaticSync can hit
                    // exactly that. Report it to Dart, which degrades to an
                    // in-app sync rather than failing the sync itself.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(true)
                } catch (e: IllegalStateException) {
                    // ForegroundServiceStartNotAllowedException extends this on API 31+.
                    Log.w(TAG, "foreground start refused (app in background?): ${e.message}")
                    result.success(false)
                } catch (e: SecurityException) {
                    Log.w(TAG, "foreground start denied: ${e.message}")
                    result.success(false)
                }
            }

            "update" -> {
                context.startService(serviceIntent(SyncForegroundService.ACTION_UPDATE, call))
                result.success(null)
            }

            "stop" -> {
                context.startService(
                    Intent(context, SyncForegroundService::class.java).apply {
                        action = SyncForegroundService.ACTION_STOP
                    },
                )
                result.success(null)
            }

            "showFailure" -> {
                showFailure(
                    title = call.argument<String>("title").orEmpty(),
                    text = call.argument<String>("text").orEmpty(),
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun serviceIntent(action: String, call: MethodCall): Intent =
        Intent(context, SyncForegroundService::class.java).apply {
            this.action = action
            putExtra(SyncForegroundService.EXTRA_TITLE, call.argument<String>("title").orEmpty())
            putExtra(SyncForegroundService.EXTRA_TEXT, call.argument<String>("text").orEmpty())
            putExtra(SyncForegroundService.EXTRA_DONE, call.argument<Int>("done") ?: 0)
            putExtra(SyncForegroundService.EXTRA_TOTAL, call.argument<Int>("total") ?: 0)
        }

    /**
     * Dismissible notice posted after the foreground notification is torn down,
     * so a sync that failed while the SK was elsewhere leaves a trace.
     */
    private fun showFailure(title: String, text: String) {
        val notification = NotificationCompat.Builder(context, SyncForegroundService.CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setAutoCancel(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(SyncForegroundService.FAILURE_NOTIFICATION_ID, notification)
    }
}
