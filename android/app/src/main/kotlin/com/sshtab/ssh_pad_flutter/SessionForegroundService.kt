package com.sshtab.ssh_pad_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Same-process FGS for session keepalive.
 *
 * Holds PARTIAL_WAKE_LOCK + WifiLock while sessions are active.
 * Optional weak AudioTrack when [EXTRA_WEAK_AUDIO] is true (CN OEM path).
 * Does NOT aggressively auto-reconnect.
 */
class SessionForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "ssh_pad_sessions"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.sshtab.ssh_pad_flutter.STOP_SESSIONS"
        const val ACTION_OPEN = "com.sshtab.ssh_pad_flutter.OPEN_APP"
        const val EXTRA_SESSIONS = "sessions"
        const val EXTRA_TITLE = "title"
        const val EXTRA_WEAK_AUDIO = "weakAudio"

        @Volatile
        var stopCallback: (() -> Unit)? = null

        fun start(
            context: Context,
            sessions: List<String>,
            title: String?,
            weakAudio: Boolean,
        ) {
            val intent = Intent(context, SessionForegroundService::class.java).apply {
                putStringArrayListExtra(EXTRA_SESSIONS, ArrayList(sessions))
                putExtra(EXTRA_TITLE, title ?: "")
                putExtra(EXTRA_WEAK_AUDIO, weakAudio)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SessionForegroundService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var player: KeepAlivePlayer? = null
    private var lastCount = 0
    private var lastTitle = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopCallback?.invoke()
                teardown()
                return START_NOT_STICKY
            }
            ACTION_OPEN -> {
                val launch = packageManager.getLaunchIntentForPackage(packageName)
                launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                if (launch != null) startActivity(launch)
                return START_STICKY
            }
        }

        val sessions = intent?.getStringArrayListExtra(EXTRA_SESSIONS) ?: arrayListOf()
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val weakAudio = intent?.getBooleanExtra(EXTRA_WEAK_AUDIO, false) ?: false
        lastCount = sessions.size
        lastTitle = title

        ensureChannel()
        val notification = buildNotification(sessions.size, title)
        startAsForeground(notification)

        if (sessions.isEmpty()) {
            teardown()
            return START_NOT_STICKY
        }

        acquireLocks()
        if (weakAudio) {
            if (player == null) player = KeepAlivePlayer()
            player?.start()
        } else {
            player?.stop()
            player = null
        }
        return START_STICKY
    }

    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Prefer dataSync; if weak audio path is used we still declare dataSync
            // as primary type in Manifest. Optional mediaPlayback type requires
            // matching permission + manifest type when enabled in a future build.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun teardown() {
        player?.stop()
        player = null
        releaseLocks()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        player?.stop()
        player = null
        releaseLocks()
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SSH Pad 会话保活",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持 SSH/Telnet 等会话在后台不被冻结"
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(count: Int, title: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val contentPi = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = Intent(this, SessionForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val openIntent = Intent(this, SessionForegroundService::class.java).apply {
            action = ACTION_OPEN
        }
        val openPi = PendingIntent.getService(
            this,
            2,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = when {
            count <= 0 -> "无活动会话"
            title.isNotBlank() -> title
            else -> "活动会话：$count"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SSH Pad 会话保活")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, "打开应用", openPi)
            .addAction(0, "断开全部", stopPi)
            .build()
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sshpad:session").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else if (wakeLock?.isHeld != true) {
            wakeLock?.acquire()
        }
        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "sshpad:wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else if (wifiLock?.isHeld != true) {
            wifiLock?.acquire()
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        try {
            wifiLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wifiLock = null
    }
}
