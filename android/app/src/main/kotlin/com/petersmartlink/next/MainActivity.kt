package com.petersmartlink.next

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.petersmartlink.next/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAssistantRoleAvailable" -> result.success(isAssistantRoleAvailable())
                    "isAssistantRoleHeld" -> result.success(isAssistantRoleHeld())
                    "requestAssistantRole" -> {
                        requestAssistantRole()
                        result.success(null)
                    }
                    "openApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("bad_request", "packageName is required", null)
                        } else {
                            openApp(packageName, result)
                        }
                    }
                    "deviceSnapshot" -> result.success(deviceSnapshot())
                    else -> result.notImplemented()
                }
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

        // Older Android versions can still expose the system assistant chooser.
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

    private fun deviceSnapshot(): Map<String, Any?> = mapOf(
        "sdk" to Build.VERSION.SDK_INT,
        "release" to Build.VERSION.RELEASE,
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "assistantRoleAvailable" to isAssistantRoleAvailable(),
        "assistantRoleHeld" to isAssistantRoleHeld(),
    )
}
