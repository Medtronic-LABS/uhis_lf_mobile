package com.medtroniclabs.uhis_next

import android.app.Activity
import android.content.Context
import com.medtroniclabs.uhis_next.BuildConfig
import android.util.Log
import com.medtroniclabs.microcoaching.Language
import com.medtroniclabs.microcoaching.MicroCoachingSDK
import com.medtroniclabs.microcoaching.domain.context.CHWWorkContext
import com.medtroniclabs.microcoaching.domain.context.RecentPatientSummary
import com.medtroniclabs.microcoaching.domain.context.TodaysVisit
import com.medtroniclabs.microcoaching.ui.flow.CoachingFlowActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val TAG = "MicroCoaching"

class MicroCoachingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            // ── Lifecycle ────────────────────────────────────────────────────

            "initialize" -> {
                val token = call.argument<String>("authToken")
                    ?: return result.error("MISSING_ARG", "authToken required", null)
                val url = call.argument<String>("backendUrl")
                    ?: (BuildConfig.API_BASE_URL.trimEnd('/') + "/micro-coaching/medtronics-api/")
                val lang = call.argument<String>("language") ?: "bn"
                val hfToken = call.argument<String>("hfToken") ?: ""
                Log.d(TAG, "initialize: url=$url lang=$lang hfToken=${hfToken.isNotEmpty()} token=${token.take(10)}...")
                try {
                    MainApplication.initSdk(
                        authToken = token,
                        backendUrl = url,
                        language = lang,
                        hfToken = hfToken,
                    )
                    Log.d(TAG, "initialize: SDK init success")
                    result.success(null)
                } catch (e: Exception) {
                    Log.e(TAG, "initialize: SDK init failed: ${e.message}", e)
                    result.error("INIT_FAILED", e.message, null)
                }
            }

            "updateToken" -> {
                val token = call.argument<String>("authToken")
                    ?: return result.error("MISSING_ARG", "authToken required", null)
                Log.d(TAG, "updateToken: token=${token.take(10)}... (stored in prefs; no SDK API to update in-process)")
                // SDK has no updateToken() — store in prefs so next process restart uses fresh token
                MainApplication.instance.getSharedPreferences("coaching_sdk_config", Context.MODE_PRIVATE)
                    .edit().putString("authToken", token).apply()
                result.success(null)
            }

            "isInitialized" -> {
                val v = MicroCoachingSDK.isInitialized()
                Log.d(TAG, "isInitialized: $v")
                result.success(v)
            }

            // ── Navigation hooks (no-launch) ─────────────────────────────────

            "onHomeScreenShown" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val chwId = call.argument<String>("chwId") ?: ""
                Log.d(TAG, "onHomeScreenShown: chwId=$chwId")
                MicroCoachingSDK.getInstance().onHomeScreenShown(chwId)
                result.success(null)
            }

            // Flutter-only hooks with no SDK counterpart — succeed silently so
            // unawaited fire-and-forget calls don't throw MissingPluginException.
            "onDashboardShown",
            "onPatientSelected",
            "onScreeningCompleted",
            "onVitalThresholdCrossed" -> result.success(null)

            // ── Launch ───────────────────────────────────────────────────────

            "launch" -> {
                val act = activity
                    ?: return result.error("NO_ACTIVITY", "Activity not attached", null)
                if (!MicroCoachingSDK.isInitialized())
                    return result.error("NOT_INITIALIZED", "Call initialize first", null)
                val chwId = call.argument<String>("chwId")
                    ?: return result.error("MISSING_ARG", "chwId required", null)
                Log.d(TAG, "launch: chwId=$chwId")
                MicroCoachingSDK.getInstance().onHomeScreenShown(chwId)
                CoachingFlowActivity.launch(act, chwId = chwId)
                result.success(null)
            }

            // ── Visit / assessment hooks (mirror spice-coaching-android SDK contract) ──

            "onAssessmentSubmitted" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val encounterId = call.argument<String>("encounterId") ?: ""
                val patientId = call.argument<String>("patientId") ?: ""
                @Suppress("UNCHECKED_CAST")
                val assessmentData = (call.argument<Map<*, *>>("assessmentData") ?: emptyMap<String, Any>())
                    .mapKeys { it.key.toString() }
                    .mapValues { it.value as Any }
                Log.d(TAG, "onAssessmentSubmitted: encounterId=$encounterId patientId=$patientId keys=${assessmentData.keys}")
                MicroCoachingSDK.getInstance().onAssessmentSubmitted(encounterId, patientId, assessmentData)
                result.success(null)
            }

            "onReferralSubmitted" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val encounterId = call.argument<String>("encounterId") ?: ""
                val patientId = call.argument<String>("patientId") ?: ""
                @Suppress("UNCHECKED_CAST")
                // Flutter service sends key "referralContext"; fall back to "referralData" for future alignment.
                val referralData = (call.argument<Map<*, *>>("referralContext")
                    ?: call.argument<Map<*, *>>("referralData")
                    ?: emptyMap<String, Any>())
                    .mapKeys { it.key.toString() }
                    .mapValues { it.value as Any }
                Log.d(TAG, "onReferralSubmitted: encounterId=$encounterId patientId=$patientId")
                MicroCoachingSDK.getInstance().onReferralSubmitted(encounterId, patientId, referralData)
                result.success(null)
            }

            "onRiskFlagSurfaced" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val riskLevel = call.argument<String>("riskLevel") ?: "high"
                val patientId = call.argument<String>("patientId")
                Log.d(TAG, "onRiskFlagSurfaced: riskLevel=$riskLevel patientId=$patientId")
                MicroCoachingSDK.getInstance().onRiskFlagObserved(riskLevel, patientId)
                result.success(null)
            }

            "onVisitCompleted" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val encounterId = call.argument<String>("encounterId") ?: ""
                Log.d(TAG, "onVisitCompleted: encounterId=$encounterId")
                MicroCoachingSDK.getInstance().onVisitCompleted(encounterId)
                result.success(null)
            }

            "onFormSubmitted" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val formId = call.argument<String>("formId") ?: ""
                @Suppress("UNCHECKED_CAST")
                val payload = (call.argument<Map<*, *>>("payload") ?: emptyMap<String, String>())
                    .mapKeys { it.key.toString() }
                    .mapValues { it.value.toString() }
                Log.d(TAG, "onFormSubmitted: formId=$formId")
                MicroCoachingSDK.getInstance().onFormSubmitted(formId, payload)
                result.success(null)
            }

            "onRuleFired" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val ruleId = call.argument<String>("ruleId") ?: ""
                @Suppress("UNCHECKED_CAST")
                val payload = (call.argument<Map<*, *>>("payload") ?: emptyMap<String, String>())
                    .mapKeys { it.key.toString() }
                    .mapValues { it.value.toString() }
                Log.d(TAG, "onRuleFired: ruleId=$ruleId")
                MicroCoachingSDK.getInstance().onRuleFired(ruleId, payload)
                result.success(null)
            }

            // ── Morning / content ────────────────────────────────────────────

            "onMorningOpen" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                Log.d(TAG, "onMorningOpen")
                MicroCoachingSDK.getInstance().onMorningOpen()
                result.success(null)
            }

            "onModuleQuizCompleted" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val moduleFamilyId = call.argument<String>("moduleFamilyId") ?: ""
                val moduleId = call.argument<String>("moduleId")
                val scoreFraction = (call.argument<Double>("scoreFraction") ?: 0.0).toFloat()
                val passed = call.argument<Boolean>("passed") ?: false
                Log.d(TAG, "onModuleQuizCompleted: moduleFamilyId=$moduleFamilyId passed=$passed score=$scoreFraction")
                MicroCoachingSDK.getInstance().onModuleQuizCompleted(moduleFamilyId, moduleId, scoreFraction, passed)
                result.success(null)
            }

            "onEquipmentAnomaly" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val detail = call.argument<String>("detail") ?: ""
                Log.d(TAG, "onEquipmentAnomaly: detail=$detail")
                MicroCoachingSDK.getInstance().onEquipmentAnomaly(detail)
                result.success(null)
            }

            // ── Context updates ──────────────────────────────────────────────

            "onCHWContextUpdated" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                @Suppress("UNCHECKED_CAST")
                // Flutter service passes the map as the args directly (not wrapped under a key).
                val raw: Map<*, *> = call.argument<Map<*, *>>("chwWorkContext")
                    ?: (call.arguments as? Map<*, *>)
                    ?: emptyMap<String, Any>()
                val screenedTodayCount = (raw["screenedTodayCount"] as? Int) ?: 0
                @Suppress("UNCHECKED_CAST")
                val recentPatients = (raw["recentPatients"] as? List<Map<*, *>> ?: emptyList())
                    .map { p ->
                        @Suppress("UNCHECKED_CAST")
                        RecentPatientSummary(
                            conditions = (p["conditions"] as? List<String>) ?: emptyList(),
                            riskLevel = p["riskLevel"] as? String,
                            screenedAtMs = (p["screenedAtMs"] as? Long) ?: System.currentTimeMillis(),
                            villageId = p["villageId"] as? String,
                        )
                    }
                val ctx = CHWWorkContext(
                    screenedTodayCount = screenedTodayCount,
                    recentPatients = recentPatients,
                )
                Log.d(TAG, "onCHWContextUpdated: screenedToday=$screenedTodayCount patients=${recentPatients.size}")
                MicroCoachingSDK.getInstance().onCHWContextUpdated(ctx)
                result.success(null)
            }

            "onTodaysVisitsUpdated" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                @Suppress("UNCHECKED_CAST")
                val rawList = call.argument<List<Map<*, *>>>("visits") ?: emptyList()
                val visits = rawList.map { v ->
                    TodaysVisit(
                        type = (v["type"] as? String) ?: "",
                        encounterType = v["encounterType"] as? String,
                        dueDateIso = (v["dueDateIso"] as? String) ?: "",
                        isPregnant = v["isPregnant"] as? Boolean,
                        villageId = v["villageId"] as? String,
                    )
                }
                Log.d(TAG, "onTodaysVisitsUpdated: count=${visits.size}")
                MicroCoachingSDK.getInstance().onTodaysVisitsUpdated(visits)
                result.success(null)
            }

            // ── Connectivity ─────────────────────────────────────────────────

            "onConnectivityRestored" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                Log.d(TAG, "onConnectivityRestored")
                MicroCoachingSDK.getInstance().onConnectivityRestored()
                result.success(null)
            }

            // ── Lifecycle ─────────────────────────────────────────────────────

            "shutdown" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                Log.d(TAG, "shutdown")
                MicroCoachingSDK.getInstance().shutdown()
                MainApplication.clearSdkConfig()
                result.success(null)
            }

            "flushTelemetryNow" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                Log.d(TAG, "flushTelemetryNow")
                MicroCoachingSDK.getInstance().flushTelemetryNow()
                result.success(null)
            }

            "setLanguage" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val lang = call.argument<String>("language") ?: "bn"
                val language = if (lang == "bn") Language.BANGLA else Language.ENGLISH
                Log.d(TAG, "setLanguage: $lang")
                MicroCoachingSDK.getInstance().setLanguage(language)
                result.success(null)
            }

            // ── Refresher management ──────────────────────────────────────────

            "refreshRefreshers" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                Log.d(TAG, "refreshRefreshers")
                MicroCoachingSDK.getInstance().refreshRefreshers()
                result.success(null)
            }

            "dismissMorningRefresher" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                Log.d(TAG, "dismissMorningRefresher")
                MicroCoachingSDK.getInstance().dismissMorningRefresher()
                result.success(null)
            }

            "markRefresherSkipped" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val moduleFamilyId = call.argument<String>("moduleFamilyId") ?: return result.error("MISSING_ARG", "moduleFamilyId required", null)
                Log.d(TAG, "markRefresherSkipped: moduleFamilyId=$moduleFamilyId")
                MicroCoachingSDK.getInstance().markRefresherSkipped(moduleFamilyId)
                result.success(null)
            }

            "clearRefresherSkipped" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val moduleFamilyId = call.argument<String>("moduleFamilyId") ?: return result.error("MISSING_ARG", "moduleFamilyId required", null)
                Log.d(TAG, "clearRefresherSkipped: moduleFamilyId=$moduleFamilyId")
                MicroCoachingSDK.getInstance().clearRefresherSkipped(moduleFamilyId)
                result.success(null)
            }

            "retainActiveSkippedRefreshers" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                @Suppress("UNCHECKED_CAST")
                val activeFamilyIds = (call.argument<List<String>>("activeFamilyIds") ?: emptyList()).toSet()
                Log.d(TAG, "retainActiveSkippedRefreshers: count=${activeFamilyIds.size}")
                MicroCoachingSDK.getInstance().retainActiveSkippedRefreshers(activeFamilyIds)
                result.success(null)
            }

            // ── Queries (read-back) ───────────────────────────────────────────

            "checkHealth" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(mapOf(
                    "isModelPresent" to false,
                    "modelFileSizeBytes" to 0L,
                    "modelStateName" to "NotInitialized",
                    "morningCardCount" to 0,
                ))
                val h = MicroCoachingSDK.getInstance().checkHealth()
                Log.d(TAG, "checkHealth: isModelPresent=${h.isModelPresent} state=${h.modelStateName}")
                result.success(mapOf(
                    "isModelPresent" to h.isModelPresent,
                    "modelFileSizeBytes" to h.modelFileSizeBytes,
                    "modelStateName" to h.modelStateName,
                    "morningCardCount" to h.morningCardCount,
                ))
            }

            "loadCHWContext" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val ctx = MicroCoachingSDK.getInstance().loadCHWContext()
                if (ctx == null) return result.success(null)
                result.success(mapOf(
                    "screenedTodayCount" to ctx.screenedTodayCount,
                    "updatedAtMs" to ctx.updatedAtMs,
                    "recentPatients" to ctx.recentPatients.map { p ->
                        mapOf(
                            "conditions" to p.conditions,
                            "riskLevel" to p.riskLevel,
                            "screenedAtMs" to p.screenedAtMs,
                            "villageId" to p.villageId,
                        )
                    },
                ))
            }

            "loadTodaysVisits" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(emptyList<Map<*, *>>())
                val visits = MicroCoachingSDK.getInstance().loadTodaysVisits()
                result.success(visits.map { v ->
                    mapOf(
                        "type" to v.type,
                        "encounterType" to v.encounterType,
                        "dueDateIso" to v.dueDateIso,
                        "isPregnant" to v.isPregnant,
                        "villageId" to v.villageId,
                    )
                })
            }

            "loadLastPatientSnapshot" -> {
                if (!MicroCoachingSDK.isInitialized()) return result.success(null)
                val snap = MicroCoachingSDK.getInstance().loadLastPatientSnapshot()
                if (snap == null) return result.success(null)
                result.success(mapOf(
                    "patientId" to snap.patientId,
                    "ageYears" to snap.ageYears,
                    "gender" to snap.gender,
                    "conditions" to snap.conditions,
                    "avgSystolic" to snap.avgSystolic,
                    "avgDiastolic" to snap.avgDiastolic,
                    "bmi" to snap.bmi,
                    "riskLevel" to snap.riskLevel,
                    "riskScore" to snap.riskScore,
                    "glucose" to snap.glucose,
                    "pregnancyStatus" to snap.pregnancyStatus,
                    "villageId" to snap.villageId,
                    "upazilaId" to snap.upazilaId,
                ))
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.medtroniclabs.uhis_next/micro_coaching"
    }
}
