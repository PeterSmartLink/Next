package com.petersmartlink.next

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class NextLockscreenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }

        val density = resources.displayMetrics.density
        val padding = (28 * density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(10, 12, 16))
        }

        root.addView(TextView(this).apply {
            text = "Next"
            textSize = 34f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = "I'm here. Unlock your phone to continue privately."
            textSize = 16f
            setTextColor(Color.rgb(190, 200, 215))
            gravity = Gravity.CENTER
            setPadding(0, padding / 2, 0, padding)
        })
        root.addView(Button(this).apply {
            text = "Unlock and open Next"
            setOnClickListener { requestUnlock() }
        })

        setContentView(root)
    }

    private fun requestUnlock() {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && keyguard.isKeyguardLocked) {
            keyguard.requestDismissKeyguard(
                this,
                object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() = openNext()
                },
            )
        } else {
            openNext()
        }
    }

    private fun openNext() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            action = "com.petersmartlink.next.ASSIST"
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        })
        finish()
    }
}
