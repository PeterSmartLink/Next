package com.petersmartlink.next

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Recognition boundary used when Android selects Next as the device assistant.
 *
 * Next intentionally delegates raw speech decoding to an installed Android
 * speech engine. The transcript can then enter the same private Next/OTYA
 * conversation path as the Flutter live surface; no OTYA credential or owner
 * secret is shared with the speech engine.
 */
class NextRecognitionService : RecognitionService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null

    override fun onStartListening(recognizerIntent: Intent, listener: Callback) {
        mainHandler.post {
            destroyRecognizer()
            val component = externalRecognitionService()
            if (component == null) {
                listener.error(SpeechRecognizer.ERROR_CLIENT)
                return@post
            }

            runCatching {
                SpeechRecognizer.createSpeechRecognizer(this, component)
            }.onSuccess { speechRecognizer ->
                recognizer = speechRecognizer
                speechRecognizer.setRecognitionListener(forwardingListener(listener))
                speechRecognizer.startListening(recognizerIntent)
            }.onFailure {
                listener.error(SpeechRecognizer.ERROR_CLIENT)
            }
        }
    }

    override fun onStopListening(listener: Callback) {
        mainHandler.post {
            runCatching { recognizer?.stopListening() }
        }
    }

    override fun onCancel(listener: Callback) {
        mainHandler.post {
            runCatching { recognizer?.cancel() }
            destroyRecognizer()
        }
    }

    override fun onDestroy() {
        mainHandler.post { destroyRecognizer() }
        super.onDestroy()
    }

    private fun externalRecognitionService(): ComponentName? {
        val intent = Intent(RecognitionService.SERVICE_INTERFACE)
        val services = packageManager.queryIntentServices(intent, 0)
        val selected = services.firstOrNull { candidate ->
            val info = candidate.serviceInfo
            info != null && info.enabled && info.packageName != packageName
        }?.serviceInfo ?: return null
        return ComponentName(selected.packageName, selected.name)
    }

    private fun forwardingListener(callback: Callback): RecognitionListener {
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                callback.readyForSpeech(params ?: Bundle())
            }

            override fun onBeginningOfSpeech() {
                callback.beginningOfSpeech()
            }

            override fun onRmsChanged(rmsdB: Float) {
                callback.rmsChanged(rmsdB)
            }

            override fun onBufferReceived(buffer: ByteArray?) {
                if (buffer != null) callback.bufferReceived(buffer)
            }

            override fun onEndOfSpeech() {
                callback.endOfSpeech()
            }

            override fun onError(error: Int) {
                callback.error(error)
            }

            override fun onResults(results: Bundle?) {
                callback.results(results ?: Bundle())
            }

            override fun onPartialResults(partialResults: Bundle?) {
                callback.partialResults(partialResults ?: Bundle())
            }

            override fun onEvent(eventType: Int, params: Bundle?) {
                callback.event(eventType, params ?: Bundle())
            }
        }
    }

    private fun destroyRecognizer() {
        runCatching { recognizer?.destroy() }
        recognizer = null
    }
}
