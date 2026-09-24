package com.sshtab.ssh_pad_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridges:
 * - keepalive FGS: com.sshtab.ssh_pad_flutter/keepalive
 * - IME / hardware keyboard: com.sshtab.ssh_pad_flutter/ime
 */
class MainActivity : FlutterActivity() {
    private val keepaliveChannelName = "com.sshtab.ssh_pad_flutter/keepalive"
    private val imeChannelName = "com.sshtab.ssh_pad_flutter/ime"
    private var keepaliveChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        keepaliveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keepaliveChannelName)
        SessionForegroundService.stopCallback = {
            runOnUiThread {
                keepaliveChannel?.invokeMethod("stopRequested", null)
            }
        }
        keepaliveChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateSessions" -> {
                    @Suppress("UNCHECKED_CAST")
                    val sessions = (call.argument<List<String>>("sessions")) ?: emptyList()
                    val count = call.argument<Int>("count") ?: sessions.size
                    val title = call.argument<String>("title")
                    val weakAudio = call.argument<Boolean>("weakAudio") ?: false
                    if (count > 0 || sessions.isNotEmpty()) {
                        SessionForegroundService.start(this, sessions, title, weakAudio)
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
                    KeepAliveOem.openVendorKeepAlive(this)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    result.success(requestNotifications())
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imeChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restartInput" -> {
                        restartInput()
                        result.success(null)
                    }
                    "hasHardwareKeyboard" -> {
                        result.success(hasHardwareKeyboard())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Clear IME composition by restarting the current input connection. */
    private fun restartInput() {
        try {
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            val focus = currentFocus ?: window?.decorView
            if (focus != null) {
                imm.restartInput(focus)
            }
        } catch (_: Exception) {
        }
    }

    /**
     * Physical / Bluetooth keyboard attached.
     * HARDKEYBOARDHIDDEN_NO or keyboard != NOKEYS.
     */
    private fun hasHardwareKeyboard(): Boolean {
        val cfg = resources.configuration
        if (cfg.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO) return true
        return cfg.keyboard != Configuration.KEYBOARD_NOKEYS
    }

    private fun requestNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return true
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            4401,
        )
        return false
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
            }
        }
    }
}
