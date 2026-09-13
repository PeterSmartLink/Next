package com.petersmartlink.next

import android.Manifest
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.petersmartlink.next/device"
    private val voiceChannelName = "com.petersmartlink.next/voice"
    private val microphoneRequestCode = 4201

    private var voiceSink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingVoiceStart = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    voiceSink = events
                }

                override fun onCancel(arguments: Any?) {
                    voiceSink = null
                }
            })

        initialiseTts()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAssistantRoleAvailable" -> result.success(isAssistantRoleAvailable())
                    "isAssistantRoleHeld" -> result.success(isAssistantRoleHeld())
                    "requestAssistantRole" -> {
                        requestAssistantRole()
                        result.success(null)
                    }
                    "startVoiceListening" -> {
                        startVoiceListening()
                        result.success(null)
                    }
                    "stopVoiceListening" -> {
                        stopVoiceListening()
                        result.success(null)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrBlank()) {
                            result.error("bad_request", "text is required", null)
                        } else {
                            speak(text)
                            result.success(null)
                        }
                    }
                    "stopSpeaking" -> {
                        tts?.stop()
                        emitVoice(mapOf("type" to "state", "state" to "idle"))
                        result.success(null)
                    }
                    "isSpeaking" -> result.success(tts?.isSpeaking == true)
                    "openApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("bad_request", "packageName is required", null)
                        } else {
                            openApp(packageName, result)
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("bad_request", "url is required", null)
                        } else {
                            openUrl(url, result)
                        }
                    }
                    "deviceSnapshot" -> result.success(deviceSnapshot())
                    else -> result.notImplemented()
                }
            }
    }

    private fun initialiseTts() {
        if (tts != null) return
        tts = TextToSpeech(this) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.getDefault()
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        runOnUiThread {
                            emitVoice(mapOf("type" to "state", "state" to "speaking"))
                        }
                    }

                    override fun onDone(utteranceId: String?) {
                        runOnUiThread {
                            emitVoice(mapOf("type" to "tts_done"))
                            emitVoice(mapOf("type" to "state", "state" to "idle"))
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        runOnUiThread {
                            emitVoice(mapOf("type" to "error", "message" to "Voice playback failed."))
                        }
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        runOnUiThread {
                            emitVoice(
                                mapOf(
                                    "type" to "error",
                                    "message" to "Voice playback failed ($errorCode).",
                                ),
                            )
                        }
                    }
                })
                emitVoice(mapOf("type" to "tts_ready"))
            } else {
                emitVoice(mapOf("type" to "error", "message" to "Text-to-speech is unavailable on this phone."))
            }
        }
    }

    private fun startVoiceListening() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingVoiceStart = true
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphoneRequestCode)
            return
        }
        startRecognizer()
    }

    private fun startRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            emitVoice(mapOf("type" to "error", "message" to "Speech recognition is unavailable on this phone."))
            return
        }

        if (tts?.isSpeaking == true) tts?.stop()
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(this).also { speech ->
                speech.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        emitVoice(mapOf("type" to "state", "state" to "listening"))
                    }

                    override fun onBeginningOfSpeech() {
                        emitVoice(mapOf("type" to "state", "state" to "hearing"))
                    }

                    override fun onRmsChanged(rmsdB: Float) {
                        val normalized = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
                        emitVoice(mapOf("type" to "level", "value" to normalized.toDouble()))
                    }

                    override fun onBufferReceived(buffer: ByteArray?) = Unit

                    override fun onEndOfSpeech() {
                        emitVoice(mapOf("type" to "state", "state" to "thinking"))
                    }

                    override fun onError(error: Int) {
                        val soft = error == SpeechRecognizer.ERROR_NO_MATCH ||
                            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_CLIENT
                        if (soft) {
                            emitVoice(mapOf("type" to "silence", "code" to error))
                            emitVoice(mapOf("type" to "state", "state" to "idle"))
                        } else {
                            emitVoice(
                                mapOf(
                                    "type" to "error",
                                    "code" to error,
                                    "message" to recognitionError(error),
                                ),
                            )
                        }
                    }

                    override fun onResults(results: Bundle?) {
                        val text = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            ?.trim()
                            .orEmpty()
                        if (text.isNotEmpty()) {
                            emitVoice(mapOf("type" to "final", "text" to text))
                        } else {
                            emitVoice(mapOf("type" to "silence"))
                        }
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val text = partialResults
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            ?.trim()
                            .orEmpty()
                        if (text.isNotEmpty()) {
                            emitVoice(mapOf("type" to "partial", "text" to text))
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) = Unit
                })
            }
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        }
        runCatching { recognizer?.startListening(intent) }
            .onFailure {
                emitVoice(mapOf("type" to "error", "message" to "Microphone listening could not start."))
            }
    }

    private fun stopVoiceListening() {
        pendingVoiceStart = false
        runCatching { recognizer?.stopListening() }
        emitVoice(mapOf("type" to "state", "state" to "idle"))
    }

    private fun speak(text: String) {
        if (!ttsReady) {
            initialiseTts()
            emitVoice(mapOf("type" to "error", "message" to "Voice playback is still starting."))
            return
        }
        runCatching { recognizer?.cancel() }
        val utteranceId = "next-${System.currentTimeMillis()}"
        val result = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), utteranceId)
        if (result == TextToSpeech.ERROR) {
            emitVoice(mapOf("type" to "error", "message" to "Next could not speak this response."))
        }
    }

    private fun recognitionError(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "The microphone audio stream failed."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is required for live voice."
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Voice recognition cannot reach its speech service."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The speech recognizer is busy."
        SpeechRecognizer.ERROR_SERVER,
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "The phone speech service is temporarily unavailable."
        else -> "Voice recognition stopped unexpectedly ($code)."
    }

    private fun emitVoice(event: Map<String, Any?>) {
        runOnUiThread { voiceSink?.success(event) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != microphoneRequestCode) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted && pendingVoiceStart) {
            pendingVoiceStart = false
            startRecognizer()
        } else if (!granted) {
            pendingVoiceStart = false
            emitVoice(mapOf("type" to "error", "message" to "Microphone permission is required for Next live voice."))
        }
    }

    private fun roleManager(): RoleManager? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return getSystemService(Context.ROLE_SERVICE) as? RoleManager
    }

    private fun isAssistantRoleAvailable(): Boolean {
        return roleManager()?.isRoleAvailable(RoleManager.ROLE_ASSISTANT) == true
    }

    private fun isAssistantRoleHeld(): Boolean {
        return roleManager()?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
    }

    private fun requestAssistantRole() {
        val manager = roleManager()
        if (manager != null && manager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
            startActivityForResult(manager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT), 4101)
            return
        }

        runCatching {
            startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
        }
    }

    private fun openApp(packageName: String, result: MethodChannel.Result) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            result.error("not_found", "The requested app is not installed or cannot be launched.", null)
            return
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(launchIntent)
        result.success(null)
    }

    private fun isAllowedTelegramOwnerLink(uri: Uri): Boolean {
        if (!uri.scheme.equals("tg", ignoreCase = true)) return false
        if (!uri.host.equals("resolve", ignoreCase = true)) return false
        val domain = uri.getQueryParameter("domain") ?: return false
        val start = uri.getQueryParameter("start") ?: return false
        return domain.equals("OtyaPlayerBot", ignoreCase = true) &&
            Regex("^owner_[A-Za-z0-9_-]{16,80}$").matches(start)
    }

    private fun openUrl(rawUrl: String, result: MethodChannel.Result) {
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull()
        if (uri == null) {
            result.error("blocked_url", "This link is invalid.", null)
            return
        }

        val scheme = uri.scheme?.lowercase()
        val isWeb = scheme == "https" || scheme == "http"
        val isTelegramOwnerLink = isAllowedTelegramOwnerLink(uri)
        if (!isWeb && !isTelegramOwnerLink) {
            result.error("blocked_url", "This external link is not allowed from Next.", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            if (isTelegramOwnerLink) setPackage("org.telegram.messenger")
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error(
                "not_found",
                if (isTelegramOwnerLink) "Install Telegram to finish trusted-phone enrollment." else "No app can open this link.",
                null,
            )
            return
        }
        startActivity(intent)
        result.success(null)
    }

    private fun deviceSnapshot(): Map<String, Any?> = mapOf(
        "sdk" to Build.VERSION.SDK_INT,
        "release" to Build.VERSION.RELEASE,
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "assistantRoleAvailable" to isAssistantRoleAvailable(),
        "assistantRoleHeld" to isAssistantRoleHeld(),
        "speechRecognitionAvailable" to SpeechRecognizer.isRecognitionAvailable(this),
        "ttsReady" to ttsReady,
    )

    override fun onDestroy() {
        runCatching { recognizer?.destroy() }
        recognizer = null
        runCatching { tts?.stop() }
        runCatching { tts?.shutdown() }
        tts = null
        super.onDestroy()
    }
}
