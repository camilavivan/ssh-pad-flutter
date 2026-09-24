package com.sshtab.ssh_pad_flutter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge for keepalive FGS.
 * Channel: com.sshtab.ssh_pad_flutter/keepalive
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.sshtab.ssh_pad_flutter/keepalive"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        SessionForegroundService.stopCallback = {
            runOnUiThread {
                channel?.invokeMethod("stopRequested", null)
            }
        }
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateSessions" -> {
                    @Suppress("UNCHECKED_CAST")
                    val sessions = (call.argument<List<String>>("sessions")) ?: emptyList()
                    val count = call.argument<Int>("count") ?: sessions.size
                    if (count > 0 || sessions.isNotEmpty()) {
                        SessionForegroundService.start(this, sessions)
                    } else {
                        SessionForegroundService.stop(this)
                    }
                    result.success(null)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBattery()
                    result.success(null)
                }
                "openOemAutostartSettings" -> {
                    openOemOrAppDetails()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestIgnoreBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    private fun openOemOrAppDetails() {
        // OEM-specific intents are filled in M1b (KeepAliveOem-style).
        // M0: fall back to application details.
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {
            // ignore
        }
    }
}
