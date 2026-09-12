package com.petersmartlink.next

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

class NextVoiceSession(private val appContext: Context) : VoiceInteractionSession(appContext) {
    private var openedApp = false

    override fun onCreateContentView(): View {
        val padding = (24 * appContext.resources.displayMetrics.density).toInt()
        val root = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(10, 12, 16))
        }

        root.addView(TextView(appContext).apply {
            text = "Next"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        root.addView(TextView(appContext).apply {
            text = "Your private OTYA intelligence"
            textSize = 14f
            setTextColor(Color.rgb(180, 190, 205))
            gravity = Gravity.CENTER
            setPadding(0, padding / 3, 0, padding)
        })
        root.addView(ProgressBar(appContext).apply {
            isIndeterminate = true
        })
        return root
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        if (openedApp) return

        val keyguard = appContext.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard?.isKeyguardLocked == true) {
            // Never surface owner data through the assistant session while the
            // device is locked. Keyguard invocation uses NextLockscreenActivity.
            return
        }

        openedApp = true
        val intent = Intent(appContext, MainActivity::class.java).apply {
            action = "com.petersmartlink.next.ASSIST"
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startAssistantActivity(intent)
        finish()
    }
}
