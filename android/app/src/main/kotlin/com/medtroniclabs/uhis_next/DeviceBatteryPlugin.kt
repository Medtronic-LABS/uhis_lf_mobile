package com.medtroniclabs.uhis_next

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val TAG = "DeviceBattery"

/**
 * Lets the app ask whether it is exempt from battery optimisation, and send the
 * SK to the right settings screen if not.
 *
 * Context: the sync foreground service holds against stock Android's cached-app
 * freezer, but Xiaomi/Oppo/Vivo/Transsion — the phones this app actually runs on
 * in rural Bangladesh — kill background work regardless, via their own
 * "autostart" lists that no API can read or set.
 *
 * Deliberately does NOT declare `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` or use
 * `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the one-tap dialog): that
 * permission is Play-policy restricted and would put an already
 * foreground-service-declaring app under more scrutiny for a nicety. The
 * unrestricted `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` list screen needs
 * no permission and gets the SK to the same place in one extra tap.
 */
class DeviceBatteryPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.medtroniclabs.uhis_next/device_battery"

        /**
         * Vendor "autostart" / background-manager screens, by manufacturer.
         * These are undocumented and vary by ROM version, so each is tried in
         * order and any that does not resolve is skipped. Never assume one
         * exists — a wrong ComponentName throws ActivityNotFoundException.
         */
        private val OEM_AUTOSTART_SCREENS: Map<String, List<ComponentName>> = mapOf(
            "xiaomi" to listOf(
                ComponentName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ),
            "redmi" to listOf(
                ComponentName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ),
            "poco" to listOf(
                ComponentName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ),
            "oppo" to listOf(
                ComponentName("com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
                ComponentName("com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity"),
                ComponentName("com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"),
            ),
            "realme" to listOf(
                ComponentName("com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ),
            "vivo" to listOf(
                ComponentName("com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
                ComponentName("com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            ),
            "huawei" to listOf(
                ComponentName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                ComponentName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            ),
            "honor" to listOf(
                ComponentName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            ),
            "samsung" to listOf(
                ComponentName("com.samsung.android.lool",
                    "com.samsung.android.sm.battery.ui.BatteryActivity"),
            ),
            // Transsion brands (Tecno / Infinix / itel) are common in Bangladesh
            // and ship a HiOS/XOS power manager.
            "tecno" to listOf(
                ComponentName("com.transsion.phonemaster",
                    "com.cyin.himgr.autostart.AutoStartActivity"),
            ),
            "infinix" to listOf(
                ComponentName("com.transsion.phonemaster",
                    "com.cyin.himgr.autostart.AutoStartActivity"),
            ),
            "itel" to listOf(
                ComponentName("com.transsion.phonemaster",
                    "com.cyin.himgr.autostart.AutoStartActivity"),
            ),
        )
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
            "isExempt" -> result.success(isIgnoringBatteryOptimizations())
            "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
            "hasOemAutoStartScreen" -> result.success(resolveOemScreen() != null)
            "openBatterySettings" -> result.success(openBatterySettings())
            "openOemAutoStartSettings" -> result.success(openOemAutoStart())
            else -> result.notImplemented()
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return true
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Opens the system battery-optimisation list. Falls back to this app's
     * details page, which always exists, so the SK is never left staring at a
     * dead button.
     */
    private fun openBatterySettings(): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            ),
        )
        return candidates.any { launch(it) }
    }

    private fun openOemAutoStart(): Boolean {
        val component = resolveOemScreen() ?: return false
        return launch(Intent().setComponent(component))
    }

    /** The first vendor screen for this manufacturer that actually resolves. */
    private fun resolveOemScreen(): ComponentName? {
        val vendor = (Build.MANUFACTURER ?: "").lowercase()
        val candidates = OEM_AUTOSTART_SCREENS.entries
            .firstOrNull { vendor.contains(it.key) }
            ?.value
            ?: return null
        return candidates.firstOrNull { component ->
            context.packageManager.resolveActivity(
                Intent().setComponent(component), 0,
            ) != null
        }
    }

    private fun launch(intent: Intent): Boolean = try {
        // Launched from application context, so a new task is required.
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        // ActivityNotFoundException and SecurityException are both realistic on
        // vendor ROMs — an unopenable screen must not crash the app.
        Log.w(TAG, "could not open ${intent.component ?: intent.action}: ${e.message}")
        false
    }
}
