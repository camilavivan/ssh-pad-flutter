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
import android.view.InputDevice
import android.view.KeyEvent
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

    /**
     * Detect physical Esc across OEM remaps.
     *
     * Chinese OEM tablets (Xiaomi / OnePlus Pad / ColorOS) often remap the
     * physical Esc key to [KeyEvent.KEYCODE_BACK] while keeping a telltale
     * Linux scan code:
     * - scanCode 1  = KEY_ESC  (Xiaomi moonlight-vplus style)
     * - scanCode 158 = KEY_BACK in Generic.kl, but used by OnePlus Pad
     *   external keyboards for the physical Esc keycap
     *
     * Soft / gesture Back usually arrives as KEYCODE_BACK with scanCode 0
     * (or a non-keyboard source) and must NOT be treated as Escape.
     */
    private fun isPhysicalEscape(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_ESCAPE) return true
        // OEM remaps Esc→BACK but keeps KEY_ESC scan code
        if (event.scanCode == SCAN_KEY_ESC) return true
        // OnePlus / many pad keyboards: physical Esc as BACK + KEY_BACK scan
        if (event.keyCode == KeyEvent.KEYCODE_BACK && event.scanCode == SCAN_KEY_BACK) {
            val src = event.source
            if (src and InputDevice.SOURCE_KEYBOARD == InputDevice.SOURCE_KEYBOARD) {
                val dev = event.device
                if (dev == null || !dev.isVirtual) return true
            }
        }
        return false
    }

    /** Rebuild [event] as KEYCODE_ESCAPE, preserving timing / mods / device. */
    private fun asEscapeEvent(event: KeyEvent): KeyEvent {
        return KeyEvent(
            event.downTime,
            event.eventTime,
            event.action,
            KeyEvent.KEYCODE_ESCAPE,
            event.repeatCount,
            event.metaState,
            event.deviceId,
            event.scanCode,
            event.flags,
            event.source,
        )
    }

    private fun logPhysicalEscapeOnce(event: KeyEvent) {
        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return
        val name = try {
            event.device?.name
        } catch (_: Exception) {
            null
        } ?: "null"
        Log.i(
            TAG,
            "physical Esc rewrite keyCode=${event.keyCode} scanCode=${event.scanCode} " +
                "source=${event.source} device=$name",
        )
    }

    /**
     * Esc must never become Android Back / finish the Activity.
     *
     * Deliver a fixed KEYCODE_ESCAPE to Flutter (so Dart AppEscapePolicy can
     * emit a single 0x1b), never the original KEYCODE_BACK, and always consume
     * so ColorOS cannot treat remapped Esc as Back → desktop + session kill.
     *
     * Real soft/gesture Back (scanCode 0 / non-keyboard) is unchanged.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isPhysicalEscape(event)) {
            logPhysicalEscapeOnce(event)
            val fixed =
                if (event.keyCode == KeyEvent.KEYCODE_ESCAPE) {
                    event
                } else {
                    asEscapeEvent(event)
                }
            // Deliver only the Escape event; never the original BACK.
            super.dispatchKeyEvent(fixed)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (event != null && isPhysicalEscape(event)) {
            // Defensive consume if anything reaches here without dispatch rewrite.
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_ESCAPE) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (event != null && isPhysicalEscape(event)) {
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_ESCAPE) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    companion object {
        private const val TAG = "SshPadMain"
        /** Linux KEY_ESC — Xiaomi / generic Esc remap telltale. */
        private const val SCAN_KEY_ESC = 1
        /** Linux KEY_BACK — OnePlus Pad Ace keyboard Esc telltale. */
        private const val SCAN_KEY_BACK = 158
    }
}
