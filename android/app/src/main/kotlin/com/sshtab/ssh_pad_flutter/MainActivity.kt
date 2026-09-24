package com.sshtab.ssh_pad_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
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
                    // Default ON: CN OEMs freeze same-process Dart without mediaPlayback audio.
                    val weakAudio = call.argument<Boolean>("weakAudio") ?: true
                    Log.i(TAG, "updateSessions count=$count weakAudio=$weakAudio title=$title")
                    if (count > 0 || sessions.isNotEmpty()) {
                        SessionForegroundService.start(this, sessions, title, weakAudio)
                    } else {
                        SessionForegroundService.stop(this)
                    }
                    result.success(null)
                }
                "ensureKeepAlive" -> {
                    SessionForegroundService.ensure(this)
                    result.success(null)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBattery()
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBattery())
                }
                "openOemAutostartSettings" -> {
                    KeepAliveOem.openVendorKeepAlive(this)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    result.success(requestNotifications())
                }
                "openOverlayPermissionSettings" -> {
                    openOverlaySettings()
                    result.success(null)
                }
                "canDrawOverlays" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= 23) Settings.canDrawOverlays(this) else true,
                    )
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

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Home / recent-apps: re-ensure FGS while still in a privileged state.
        Log.i(TAG, "onUserLeaveHint — ensure FGS")
        SessionForegroundService.ensure(this)
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

    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBattery()) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            Log.i(TAG, "requested ignore battery optimizations")
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }

    private fun openOverlaySettings() {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName")),
                )
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        private const val TAG = "SshPadMain"
    }
}
