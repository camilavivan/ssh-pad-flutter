package com.sshtab.ssh_pad_flutter

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Process
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.sin

/**
 * Weak near-silent mediaPlayback path for aggressive CN OEMs.
 *
 * No MediaSession (avoids media controls / pause killing the process).
 * Writes an inaudible ~18Hz sine so OEMs do not treat the track as muted silence.
 * Default ON from Dart for CN keepalive reliability.
 */
class KeepAlivePlayer {
    private var track: AudioTrack? = null
    private val running = AtomicBoolean(false)
    private var writer: Thread? = null

    fun start() {
        stop()
        try {
            val sampleRate = 8000
            val min = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufSize = min.coerceAtLeast(1600)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val format = AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val t = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            t.setVolume(0.08f)
            val period = (sampleRate / 18).coerceAtLeast(8)
            val frame = ByteArray(period * 2)
            for (i in 0 until period) {
                val s = (sin(2.0 * PI * i / period) * 280).toInt().toShort()
                frame[i * 2] = (s.toInt() and 0xff).toByte()
                frame[i * 2 + 1] = (s.toInt() shr 8).toByte()
            }
            running.set(true)
            track = t
            t.play()
            // Non-daemon: do not let the process exit while audio is the keepalive signal.
            writer = thread(name = "sshpad-keepalive-audio", isDaemon = false) {
                Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                while (running.get()) {
                    try {
                        if (t.write(frame, 0, frame.size) < 0) break
                    } catch (_: Exception) {
                        break
                    }
                }
            }
            Log.i(TAG, "audiotrack started state=${t.playState} no-media-session")
        } catch (t: Exception) {
            Log.e(TAG, "audiotrack failed: ${t.javaClass.simpleName}: ${t.message}")
            stop()
        }
    }

    fun stop() {
        running.set(false)
        try {
            writer?.interrupt()
        } catch (_: Exception) {
        }
        writer = null
        try {
            track?.pause()
        } catch (_: Exception) {
        }
        try {
            track?.release()
        } catch (_: Exception) {
        }
        track = null
    }

    companion object {
        private const val TAG = "SshPadAudio"
    }
}
