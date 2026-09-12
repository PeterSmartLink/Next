package com.petersmartlink.next

import android.content.Intent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Android recognition-service boundary for the selected assistant role.
 *
 * Realtime OTYA voice will be connected to the backend voice transport. Until
 * then this service fails closed instead of pretending local recognition works.
 */
class NextRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent, listener: Callback) {
        listener.error(SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onStopListening(listener: Callback) = Unit

    override fun onCancel(listener: Callback) = Unit
}
