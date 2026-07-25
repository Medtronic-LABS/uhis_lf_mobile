package com.medtroniclabs.uhis_next

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class CoachingLlmPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    @Volatile
    private var llm: LlmInference? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.medtroniclabs.uhis_lf_mobile/coaching_llm",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val modelPath = call.argument<String>("modelPath")
                if (modelPath.isNullOrBlank()) {
                    result.error("INVALID_ARG", "modelPath is required", null)
                    return
                }
                scope.launch {
                    try {
                        val instance = withContext(Dispatchers.IO) { buildLlm(modelPath) }
                        llm?.close()
                        llm = instance
                        Log.i(TAG, "LlmInference ready at $modelPath")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "LlmInference init failed", e)
                        result.error("INIT_FAILED", e.message, null)
                    }
                }
            }

            "ask" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt.isNullOrBlank()) {
                    result.error("INVALID_ARG", "prompt is required", null)
                    return
                }
                val inference = llm
                if (inference == null) {
                    result.error("NOT_READY", "Model not initialized", null)
                    return
                }
                scope.launch {
                    try {
                        val answer = withContext(Dispatchers.IO) {
                            val sessionOpts =
                                LlmInferenceSession.LlmInferenceSessionOptions.builder()
                                    .setTopK(40)
                                    .setTemperature(0.8f)
                                    .build()
                            LlmInferenceSession.createFromOptions(inference, sessionOpts).use { session ->
                                session.addQueryChunk(prompt)
                                session.generateResponse()
                                    .substringBefore("<end_of_turn>")
                                    .trim()
                            }
                        }
                        result.success(answer)
                    } catch (e: Exception) {
                        Log.e(TAG, "generateResponse failed", e)
                        result.error("INFERENCE_FAILED", e.message, null)
                    }
                }
            }

            "isReady" -> result.success(llm != null)

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.launch {
            withContext(Dispatchers.IO) {
                runCatching { llm?.close() }
            }
            llm = null
        }
    }

    private fun buildLlm(modelPath: String): LlmInference {
        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(modelPath)
            .setMaxTokens(2048)
            .setMaxTopK(40)
            .build()
        return LlmInference.createFromOptions(context, options)
    }

    companion object {
        private const val TAG = "CoachingLlmPlugin"
    }
}
