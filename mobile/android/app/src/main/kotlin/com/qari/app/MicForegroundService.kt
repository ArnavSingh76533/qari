package com.qari.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Microphone foreground service (type `microphone`).
 *
 * On Android 14+ the OS only reliably delivers mic *data* to an app that is
 * capturing from within an active, microphone-typed foreground service. The
 * `record` Flutter plugin opens its `AudioRecord` on the Flutter engine thread,
 * outside that context, so on affected devices it initialises fine and is even
 * granted audio focus yet receives 0 frames forever (the "mic chunks: 0 /
 * focus: yes" failure). Capturing natively *here*, inside the service, is the
 * sanctioned fix.
 *
 * Safety: NOTHING in this service may throw to the OS. Every native call is
 * wrapped so a failure is reported via the status [EventChannel] and the
 * service stops cleanly instead of crashing the app.
 */
class MicForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "qari_mic_capture"
        const val NOTIFICATION_ID = 8841
        const val TARGET_RATE = 16000
        const val FALLBACK_RATE = 44100

        fun start(context: Context) {
            try {
                val intent = Intent(context, MicForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                MicStreamBridge.lastStatus = "start error: ${e.message}"
                try {
                    MicStreamBridge.statusSink?.success(MicStreamBridge.lastStatus)
                } catch (_: Exception) {
                }
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, MicForegroundService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    private var reader: AudioRecord? = null
    private var readThread: Thread? = null

    @Volatile
    private var running = false

    /** Monotonic token for the current capture; bumped in stopCapture so the
     * main-thread flush Runnable from a previous session stops re-posting. */
    private var captureToken = 0

    /** All EventChannel sink calls MUST run on the main thread. Calling a Flutter
     * sink from a background thread is an uncatchable JNI crash on Android. */
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        try {
            createChannel()
        } catch (e: Exception) {
            MicStreamBridge.lastStatus = "createChannel error: ${e.message}"
            try {
                MicStreamBridge.statusSink?.success(MicStreamBridge.lastStatus)
            } catch (_: Exception) {
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            // Android may redeliver start commands. Never create two AudioRecord
            // loops for the same service instance.
            if (!running) {
                startCapture()
            }
        } catch (e: Exception) {
            val msg = "foreground start error: ${e.javaClass.simpleName}: ${e.message}"
            MicStreamBridge.lastStatus = msg
            try {
                MicStreamBridge.statusSink?.success(msg)
            } catch (_: Exception) {
            }
            stopCapture()
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (_: Exception) {
            }
            stopSelf()
        }
        // A sticky restart can resurrect microphone capture without an attached
        // Flutter page/sink. Only start capture from an explicit app request.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopCapture()
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun status(msg: String) {
        MicStreamBridge.lastStatus = msg
        mainHandler.post {
            try {
                MicStreamBridge.statusSink?.success(msg)
            } catch (_: Exception) {
            }
        }
    }

    private fun startCapture() {
        if (running) return
        try {
            val (rate, resample) = pickRate()
            val minBuf = AudioRecord.getMinBufferSize(
                rate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuf <= 0) {
                status("capture error: getMinBufferSize invalid (rate=$rate)")
                return
            }
            val picked = buildAudioRecord(rate, minBuf * 2)
            if (picked == null) {
                status("capture error: AudioRecord not initialized (rate=$rate)")
                return
            }
            val (ar, srcName) = picked
            ar.startRecording()
            if (ar.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                ar.release()
                status("capture error: AudioRecord not recording (rate=$rate)")
                return
            }
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                am.isMicrophoneMute = false
            } catch (_: Exception) {
            }
            reader = ar
            running = true
            status("capture started: rate=$rate resample=$resample source=$srcName gain=3x")
            val shortBuf = ShortArray(minBuf / 2)
            val resampler = if (resample) LinearResampler(rate, TARGET_RATE) else null
            val gain = SoftGain()
            var zeroTicks = 0
            var dataTicks = 0
            var audioDropped = 0
            var lastDiagAt = System.currentTimeMillis()

            val outBuf = java.util.concurrent.ConcurrentLinkedQueue<ByteArray>()
            val maxBufferedBytes = 1_600_000 // ~10s of 16kHz PCM16
            val bufferedBytes = java.util.concurrent.atomic.AtomicInteger(0)
            MicStreamBridge.onAudioSinkAttached = {
                mainHandler.post { flushNow(outBuf, bufferedBytes) }
            }

            readThread = Thread {
                try {
                    Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                } catch (_: Exception) {
                }
                try {
                    while (running) {
                        val n = ar.read(shortBuf, 0, shortBuf.size)
                        if (n > 0) {
                            dataTicks++
                            // Boost first so the resampler interpolates on the
                            // amplified signal (identical result either way, but
                            // this keeps one clear amplification point).
                            gain.apply(shortBuf, n)
                            val bytes = if (resampler != null) {
                                resampler.resample(shortBuf, n)
                            } else {
                                shortsToBytes(shortBuf, n)
                            }
                            if (bufferedBytes.get() + bytes.size <= maxBufferedBytes) {
                                outBuf.add(bytes)
                                bufferedBytes.addAndGet(bytes.size)
                            } else {
                                audioDropped++
                            }
                        } else if (n < 0) {
                            if (running) status("read error: $n")
                            break
                        } else {
                            zeroTicks++
                        }
                        val now = System.currentTimeMillis()
                        if (now - lastDiagAt > 2000) {
                            lastDiagAt = now
                            status("reading: rate=$rate source=$srcName zeroTicks=$zeroTicks dataTicks=$dataTicks dropped=$audioDropped")
                        }
                    }
                } catch (e: Exception) {
                    if (running) {
                        status("read exception: ${e.javaClass.simpleName}: ${e.message}")
                    }
                }
            }
            readThread?.start()

            val myToken = captureToken
            val flushRunnable = object : Runnable {
                override fun run() {
                    if (!running || myToken != captureToken) return
                    flushNow(outBuf, bufferedBytes)
                    mainHandler.postDelayed(this, 50)
                }
            }
            mainHandler.postDelayed(flushRunnable, 50)
        } catch (e: Exception) {
            status("capture exception: ${e.javaClass.simpleName}: ${e.message}")
            stopCapture()
        }
    }

    /**
     * Atomically drains the queue into a stable local snapshot before allocating
     * the merged byte array. The former `sumOf` followed by a separate polling
     * loop raced with the recorder thread: a frame could be appended after the
     * size was calculated and then copied past the end of the array, crashing
     * the Android process with ArrayIndexOutOfBoundsException.
     */
    private fun flushNow(
        outBuf: java.util.concurrent.ConcurrentLinkedQueue<ByteArray>,
        bufferedBytes: java.util.concurrent.atomic.AtomicInteger,
    ) {
        val sink = MicStreamBridge.audioSink ?: return

        val drained = ArrayList<ByteArray>()
        var total = 0
        while (true) {
            val frame = outBuf.poll() ?: break
            drained.add(frame)
            total += frame.size
        }
        if (total <= 0) return

        val merged = ByteArray(total)
        var offset = 0
        for (frame in drained) {
            System.arraycopy(frame, 0, merged, offset, frame.size)
            offset += frame.size
        }
        bufferedBytes.addAndGet(-total)

        try {
            sink.success(merged)
        } catch (_: Exception) {
            // The Flutter listener was cancelled between reading audioSink and
            // delivery. Do not let a stale EventSink terminate the app process.
        }
    }

    /** Preferred capture sources in priority order. VOICE_RECOGNITION applies
     * the device's hardware/AGC input gain and is tuned for exactly this
     * always-on-speech use case; UNPROCESSED intentionally bypasses ALL
     * processing (incl. gain) and was producing mic levels ~20 dB too quiet
     * (RMS 0.0015-0.0027 < server SILENCE_RMS_THRESHOLD 0.006 → every frame
     * discarded as silence). MIC is the safe fallback. */
    private fun buildAudioRecord(rate: Int, bufSize: Int): Pair<AudioRecord, String>? {
        val candidates = listOf(
            "VOICE_RECOGNITION" to MediaRecorder.AudioSource.VOICE_RECOGNITION,
            "MIC" to MediaRecorder.AudioSource.MIC,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                "UNPROCESSED" to MediaRecorder.AudioSource.UNPROCESSED else null,
        ).filterNotNull()
        for ((name, src) in candidates) {
            try {
                val ar = AudioRecord(
                    src,
                    rate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize,
                )
                if (ar.state == AudioRecord.STATE_INITIALIZED) {
                    return ar to name
                }
                ar.release()
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun pickRate(): Pair<Int, Boolean> {
        val ok44 = AudioRecord.getMinBufferSize(
            FALLBACK_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        return if (ok44 > 0) FALLBACK_RATE to true else TARGET_RATE to false
    }

    private fun stopCapture() {
        running = false
        captureToken++
        MicStreamBridge.onAudioSinkAttached = null

        // stop() unblocks a blocking AudioRecord.read(). Joining first can leave
        // the reader thread alive while the service and Flutter sink are torn
        // down, producing late JNI callbacks and hard process crashes.
        try {
            reader?.stop()
        } catch (_: Exception) {
        }
        try {
            readThread?.interrupt()
        } catch (_: Exception) {
        }
        try {
            readThread?.join(1000)
        } catch (_: Exception) {
        }
        readThread = null
        try {
            reader?.release()
        } catch (_: Exception) {
        }
        reader = null
    }

    private fun shortsToBytes(buf: ShortArray, n: Int): ByteArray {
        val bb = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until n) bb.putShort(buf[i])
        return bb.array()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Qari Microphone Capture",
                    NotificationManager.IMPORTANCE_LOW,
                )
                channel.setShowBadge(false)
                mgr.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle("Qari is listening")
            .setContentText("Recording your recitation. Tap to return.")
            .setSmallIcon(R.drawable.ic_mic_notification)
            .setContentIntent(contentIntent)
            .setOngoing(true)
        return builder.build()
    }
}

/** Fixed +9.5 dB software gain as a safety net for devices whose
 * VOICE_RECOGNITION input is still quiet (some OEMs report low input levels
 * even with AGC enabled). Clamps to int16 range so boosted speech never
 * wraps around. Applied AFTER hardware gain, BEFORE resampling. */
class SoftGain(private val factor: Double = 3.0) {
    fun apply(buf: ShortArray, n: Int) {
        for (i in 0 until n) {
            val boosted = (buf[i] * factor).toInt().coerceIn(-32768, 32767)
            buf[i] = boosted.toShort()
        }
    }
}

/** Simple linear-resampler for the 44.1 kHz → 16 kHz fallback. Good enough for
 * ASR (Whisper is fairly robust to mild resampling artifacts). */
class LinearResampler(private val inRate: Int, private val outRate: Int) {
    private val ratio = inRate.toDouble() / outRate.toDouble()

    fun resample(input: ShortArray, n: Int): ByteArray {
        val outLen = (n / ratio).toInt().coerceAtLeast(1)
        val bb = ByteBuffer.allocate(outLen * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until outLen) {
            val pos = i * ratio
            val i0 = pos.toInt().coerceIn(0, n - 1)
            val i1 = (i0 + 1).coerceIn(0, n - 1)
            val frac = pos - i0
            val s0 = input[i0].toInt()
            val s1 = input[i1].toInt()
            val s = (s0 + (s1 - s0) * frac).toInt().coerceIn(-32768, 32767)
            bb.putShort(s.toShort())
        }
        return bb.array()
    }
}