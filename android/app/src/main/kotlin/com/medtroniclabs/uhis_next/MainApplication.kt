package com.medtroniclabs.uhis_next

import android.app.Application
import android.content.Context
import com.medtroniclabs.microcoaching.Language
import com.medtroniclabs.microcoaching.MicroCoachingSDK
import com.medtroniclabs.microcoaching.ModelDownloadStrategy
import com.medtroniclabs.microcoaching.ai.model.ModelCatalog
import com.medtroniclabs.microcoaching.ai.model.ModelProvider
import com.medtroniclabs.microcoaching.domain.decision.CoachingMode

class MainApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        instance = this
        // Restore SDK on process restart using config persisted on last login.
        // Ensures Builder.build() is called at most ONCE per process lifetime so
        // the SDK's own "onboarding_complete" SharedPreferences flag is preserved
        // and the welcome screen only appears on first-ever use, not every restart.
        _restoreSdkIfConfigured()
    }

    companion object {
        lateinit var instance: MainApplication
            private set

        private const val PREFS_SDK = "coaching_sdk_config"
        private const val K_TOKEN = "authToken"
        private const val K_URL = "backendUrl"
        private const val K_LANG = "language"
        private const val K_HF = "hfToken"

        private fun _restoreSdkIfConfigured() {
            val p = instance.getSharedPreferences(PREFS_SDK, Context.MODE_PRIVATE)
            val token = p.getString(K_TOKEN, null) ?: return
            _initSdkInternal(
                authToken = token,
                backendUrl = p.getString(K_URL, "https://spice-dev-backend.uhis.labsplatform.com/micro-coaching/medtronics-api/") ?: "https://spice-dev-backend.uhis.labsplatform.com/micro-coaching/medtronics-api/",
                language = p.getString(K_LANG, "bn") ?: "bn",
                hfToken = p.getString(K_HF, "") ?: "",
            )
        }

        fun initSdk(
            authToken: String,
            backendUrl: String,
            language: String,
            hfToken: String = "",
        ) {
            val prefs = instance.getSharedPreferences(PREFS_SDK, Context.MODE_PRIVATE)
            val previousHfToken = prefs.getString(K_HF, "") ?: ""
            val previousLang = prefs.getString(K_LANG, "bn") ?: "bn"
            val previousUrl = prefs.getString(K_URL, "") ?: ""

            // Persist config so Application.onCreate() can restore SDK on next process start.
            prefs.edit()
                .putString(K_TOKEN, authToken)
                .putString(K_URL, backendUrl)
                .putString(K_LANG, language)
                .putString(K_HF, hfToken)
                .apply()

            if (MicroCoachingSDK.isInitialized()) {
                // SDK already running. Re-init if backend URL, HF token, or auth token changed.
                // Builder.build() calls shutdown() internally — safe because _initSdkInternal()
                // re-writes mc_onboarded_v1=true immediately after.
                if (backendUrl != previousUrl || (hfToken.isNotEmpty() && hfToken != previousHfToken)) {
                    _initSdkInternal(authToken, backendUrl, language, hfToken)
                } else if (language != previousLang) {
                    // Language switched without other config change — update running SDK via
                    // setLanguage so CoachingFlowActivity reflects the user's current app language.
                    val lang = if (language == "bn") Language.BANGLA else Language.ENGLISH
                    MicroCoachingSDK.getInstance().setLanguage(lang)
                }
                return
            }
            _initSdkInternal(authToken, backendUrl, language, hfToken)
        }

        fun clearSdkConfig() {
            instance.getSharedPreferences(PREFS_SDK, Context.MODE_PRIVATE).edit().clear().apply()
        }

        private fun _initSdkInternal(
            authToken: String,
            backendUrl: String,
            language: String,
            hfToken: String,
        ) {
            val lang = if (language == "bn") Language.BANGLA else Language.ENGLISH

            val selectedModelId = ModelCatalog.DEFAULT_ID
            val selectedVariant = ModelCatalog.resolve(selectedModelId)

            val modelDir = instance.getExternalFilesDir(null)
            val existingModel = modelDir?.listFiles()
                ?.firstOrNull { it.name == selectedVariant.fileName }
            val downloadStrategy = if (existingModel != null) {
                ModelDownloadStrategy.PROVIDED
            } else {
                ModelDownloadStrategy.ON_FIRST_USE
            }

            MicroCoachingSDK.Builder(instance)
                .authToken(authToken)
                .backendUrl(backendUrl)
                .language(lang)
                .enableChat(true)
                .enableVoice(true)
                .enableLearnModule(true)
                .enableApplyModule(true)
                .enableTelemetry(false)
                .forceMode(CoachingMode.ONLINE)
                .selectedModel(selectedModelId)
                .modelDownloadStrategy(downloadStrategy)
                .modelProviders(listOf(ModelProvider.HuggingFace))
                .modelPath(existingModel?.absolutePath ?: "")
                .huggingFaceToken(hfToken)
                .wifiOnlyModelDownload(false)
                .build()

            MicroCoachingSDK.getInstance().syncCoordinator.schedulePeriodic()

            // CHWs are trained externally; the SDK's built-in onboarding slides are
            // redundant and confusing. Pre-mark as onboarded so the app goes straight
            // to the coaching home screen on every launch.
            instance.getSharedPreferences("mc_coaching_prefs", Context.MODE_PRIVATE)
                .edit().putBoolean("mc_onboarded_v1", true).apply()
        }
    }
}
