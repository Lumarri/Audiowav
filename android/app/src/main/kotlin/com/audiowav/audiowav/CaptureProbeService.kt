package com.audiowav.audiowav

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicBoolean

/** Explicitly consented, UID-scoped audio-only probe. It neither saves nor plays audio. */
@android.annotation.TargetApi(29)
class CaptureProbeService : Service() {
    companion object {
        const val START = "com.audiowav.PROBE_START"
        const val STOP = "com.audiowav.PROBE_STOP"
        const val DURATION_MS = 20000L
        private val targets = linkedMapOf(
            "com.google.android.apps.youtube.music" to "YouTube Music",
            "app.rvx.android.apps.youtube.music" to "YouTube Music RVX",
            "com.spotify.music" to "Spotify",
            "deezer.android.app" to "Deezer"
        )
        private var instance: CaptureProbeService? = null
        @Volatile private var result: Map<String, Any?> = mapOf("status" to "idle", "active" to false)
        fun snapshot() = result
        fun busy() = instance != null
        @Suppress("DEPRECATION")
        fun targetUid(context: Context, name: String): Int {
            require(name in targets) { "Elige una de las apps compatibles con la prueba." }
            val uid = context.packageManager.getApplicationInfo(name, 0).uid
            require(uid != Process.myUid()) { "La prueba no puede capturar Audiowav." }
            return uid
        }
        fun availableTargets(context: Context): List<Map<String, String>> = targets.mapNotNull { (id, label) ->
            try { targetUid(context, id); mapOf("id" to id, "label" to label) }
            catch (_: PackageManager.NameNotFoundException) { null }
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private val finished = AtomicBoolean(false)
    private val meter = CaptureSignalMeter()
    private var projection: MediaProjection? = null
    private var started = 0L
    private var target = ""
    private val revoked = object : MediaProjection.Callback() {
        override fun onStop() { finishProbe("revoked") }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("capture_probe", "Prueba de audio interno", NotificationManager.IMPORTANCE_LOW))
    }

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { finishProbe("stopped"); return START_NOT_STICKY }
        if (started != 0L) return START_NOT_STICKY
        try {
            check(Build.VERSION.SDK_INT >= 29) { "La prueba requiere Android 10 o posterior." }
            check(intent?.action == START) { "Falta la autorización de captura." }
            target = intent!!.getStringExtra("target") ?: error("Falta la app de origen.")
            val uid = targetUid(this, target)
            val token = intent.getParcelableExtra<Intent>("token") ?: error("Android no entregó la autorización.")
            val code = intent.getIntExtra("resultCode", Activity.RESULT_CANCELED)
            check(code == Activity.RESULT_OK) { "Captura no autorizada." }
            val stop = PendingIntent.getService(this, 50, Intent(this, CaptureProbeService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE)
            val open = PendingIntent.getActivity(this, 51, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
            val notification = Notification.Builder(this, "capture_probe")
                .setContentTitle("Audiowav · Prueba de audio interno")
                .setContentText("20 segundos · Solo ${targets[target]} · Sin guardar audio")
                .setSmallIcon(R.drawable.ic_wave).setOngoing(true).setContentIntent(open)
                .addAction(Notification.Action.Builder(null, "Detener prueba", stop).build()).build()
            startForeground(8, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            val manager = getSystemService(MediaProjectionManager::class.java)
            val granted = manager.getMediaProjection(code, token) ?: error("La autorización de Android ya no es válida.")
            projection = granted
            granted.registerCallback(revoked, main)
            started = SystemClock.elapsedRealtime()
            publish("running", true)
            val config = AudioPlaybackCaptureConfiguration.Builder(projection!!)
                .addMatchingUid(uid).addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME).addMatchingUsage(AudioAttributes.USAGE_UNKNOWN).build()
            Thread({ measure(config) }, "Audiowav-CaptureProbe").start()
            main.postDelayed({ finishProbe(if (meter.snapshot()["signalDetected"] == true) "signal" else "no_signal") }, DURATION_MS)
        } catch (failure: Exception) {
            finishProbe("error", failure.localizedMessage ?: "No se pudo iniciar la prueba.")
        }
        return START_NOT_STICKY
    }

    private fun measure(config: AudioPlaybackCaptureConfiguration) {
        var record: AudioRecord? = null
        val pcm = ShortArray(2048)
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val format = AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
            val minimum = AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            check(minimum > 0) { "El teléfono no admite esta entrada de audio interno." }
            record = AudioRecord.Builder().setAudioFormat(format).setBufferSizeInBytes(maxOf(minimum, 16384))
                .setAudioPlaybackCaptureConfig(config).build()
            check(record.state == AudioRecord.STATE_INITIALIZED) { "No se pudo abrir la captura interna." }
            if (finished.get()) return
            record.startRecording()
            check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Android no inició la captura." }
            var lastPublish = 0L
            while (!finished.get()) {
                val count = record.read(pcm, 0, pcm.size, AudioRecord.READ_NON_BLOCKING)
                if (finished.get()) break
                check(count >= 0) { "La captura se interrumpió (código $count)." }
                meter.add(pcm, count)
                pcm.fill(0)
                val now = SystemClock.elapsedRealtime()
                if (now - lastPublish >= 250) {
                    main.post { if (!finished.get()) publish("running", true) }
                    lastPublish = now
                }
                if (count == 0) Thread.sleep(10)
            }
        } catch (failure: Exception) {
            main.post { finishProbe("error", failure.localizedMessage ?: "La captura falló.") }
        } finally {
            pcm.fill(0)
            runCatching { record?.stop() }; runCatching { record?.release() }
        }
    }
    private fun publish(status: String, active: Boolean, error: String? = null) {
        result = meter.snapshot() + mapOf("status" to status, "active" to active, "target" to target,
            "label" to targets[target], "elapsedMs" to if (started == 0L) 0L else (SystemClock.elapsedRealtime() - started).coerceAtMost(DURATION_MS),
            "error" to error)
    }
    private fun finishProbe(status: String, error: String? = null) {
        if (!finished.compareAndSet(false, true)) return
        main.removeCallbacksAndMessages(null)
        publish(status, false, error)
        runCatching { projection?.unregisterCallback(revoked) }
        runCatching { projection?.stop() }; projection = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    override fun onDestroy() {
        finishProbe("stopped")
        if (instance === this) instance = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
