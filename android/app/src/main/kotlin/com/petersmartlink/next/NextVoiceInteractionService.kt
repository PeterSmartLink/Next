package com.petersmartlink.next

import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionService

/**
 * Lightweight always-on Android assistant entry point.
 *
 * Keep this service deliberately small. Conversation UI, network calls and AI
 * work belong in the session/app processes, not in the always-running service.
 */
class NextVoiceInteractionService : VoiceInteractionService() {
    override fun onReady() {
        super.onReady()
    }

    override fun onLaunchVoiceAssistFromKeyguard() {
        val intent = Intent(this, NextLockscreenActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(intent)
    }

    override fun onGetSupportedVoiceActions(voiceActions: Set<String>): Set<String> {
        // Extended platform actions are enabled only when Next implements them
        // end-to-end. Returning an empty set prevents false capability claims.
        return emptySet()
    }

    override fun onPrepareToShowSession(args: Bundle, flags: Int) {
        super.onPrepareToShowSession(args, flags)
    }
}
