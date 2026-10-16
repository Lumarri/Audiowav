package com.audiowav.audiowav

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.audiofx.AudioEffect
import android.media.audiofx.PresetReverb
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.io.FileDescriptor
import java.io.PrintWriter

/** User-started foreground engine. It does not record or capture audio. */
class AudioService : Service() {
    companion object {
        const val OPEN_FILE = "com.audiowav.OPEN_FILE"
        const val OPEN_SESSION = "com.audiowav.OPEN_SESSION"
        private const val STOP = "com.audiowav.STOP"
        private const val TOGGLE = "com.audiowav.TOGGLE"
        var instance: AudioService? = null
            private set
        fun capabilities(): Map<String, Boolean> {
            val types = runCatching { AudioEffect.queryEffects()?.map { it.type } ?: emptyList() }.getOrDefault(emptyList())
            return mapOf("equalizer" to types.contains(AudioEffect.EFFECT_TYPE_EQUALIZER),
                "bass" to types.contains(AudioEffect.EFFECT_TYPE_BASS_BOOST),
                "gain" to types.contains(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER),
                "reverb" to types.contains(AudioEffect.EFFECT_TYPE_PRESET_REVERB))
        }
    }
    private var player: MediaPlayer? = null
    private var prepared = false
    private var localRack: EffectRack? = null
    private var reverb: PresetReverb? = null
    private var reverbFailed = false
    private val externalRacks = mutableMapOf<Int, EffectRack>()
    private val announcedSessions = mutableSetOf<Int>()
    private var detectedSessions: Set<Int> = emptySet()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val detector = Executors.newSingleThreadScheduledExecutor()
    private var detectionError: String? = null
    private var settings = JSONObject()
    private var title: String? = null
    private var error: String? = null
    private var ducked = false
    private var resumeAfterFocus = false
    private lateinit var audioManager: AudioManager
    private lateinit var focusRequest: AudioFocusRequest
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                if (prepared) { player?.pause(); resumeAfterFocus = false; updateNotification() }
                return
            }
            val session = intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1)
            val source = intent.getStringExtra(AudioEffect.EXTRA_PACKAGE_NAME)
            if (session <= 0 || source.isNullOrBlank() || source == packageName || session == player?.audioSessionId) return
            if (intent.action == AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION) {
                announcedSessions.add(session)
                reconcileSessions()
            } else if (intent.action == AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION) {
                announcedSessions.remove(session)
                reconcileSessions()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener { change ->
                if (!prepared) return@setOnAudioFocusChangeListener
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> { player?.pause(); resumeAfterFocus = false; ducked = false }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> { resumeAfterFocus = player?.isPlaying == true; player?.pause() }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> { ducked = true; applyPlayerSettings() }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        ducked = false; applyPlayerSettings()
                        if (resumeAfterFocus) { player?.start(); resumeAfterFocus = false }
                    }
                }
                updateNotification()
            }.build()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("audio", "Motor de audio", NotificationManager.IMPORTANCE_LOW))
        startForeground(7, notification())
        val filter = IntentFilter().apply {
            addAction(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION)
            addAction(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION)
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else { @Suppress("DEPRECATION") registerReceiver(receiver, filter) }
        configure()
        detector.scheduleWithFixedDelay({ detectPlayback() }, 0, 1500, TimeUnit.MILLISECONDS)
    }

    private fun advancedDetection() = checkSelfPermission("android.permission.DUMP") == PackageManager.PERMISSION_GRANTED

    private fun detectPlayback() {
        if (!advancedDetection()) return
        try {
            val process = ProcessBuilder("dumpsys", "-t", "2", "media.audio_flinger").redirectErrorStream(true).start()
            val dump = process.inputStream.bufferedReader().use { it.readText() }
            process.waitFor()
            check(process.exitValue() == 0 && !dump.contains("Permission Denial")) { "No se pudo consultar la sesión de audio." }
            val sessions = PlaybackSessions.parse(dump)
            mainHandler.post {
                if (instance !== this) return@post
                detectionError = null
                detectedSessions = sessions
                reconcileSessions()
            }
        } catch (failure: Exception) {
            mainHandler.post { if (instance === this) detectionError = failure.message }
        }
    }

    private fun reconcileSessions() {
        val wanted = (announcedSessions + detectedSessions).filter { it > 0 && it != player?.audioSessionId }.take(32).toSet()
        (externalRacks.keys - wanted).forEach { externalRacks.remove(it)?.release() }
        (wanted - externalRacks.keys).forEach { session ->
            externalRacks[session] = EffectRack(session, external = true).also { it.apply(settings) }
            Log.i("Audiowav", "Connected session $session: ${externalRacks[session]?.capabilities()}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            STOP -> stopSelf()
            TOGGLE -> togglePlayback()
            OPEN_FILE -> intent.getStringExtra("uri")?.let { load(Uri.parse(it), intent.getStringExtra("title") ?: "Archivo de audio") }
            OPEN_SESSION -> {
                configure()
                val session = intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1)
                if (session > 0) { announcedSessions.add(session); reconcileSessions() }
            }
        }
        return START_NOT_STICKY
    }

    fun configure() {
        settings = JSONObject(getSharedPreferences("studio", MODE_PRIVATE).getString("settings", "{}") ?: "{}")
        localRack?.apply(settings)
        externalRacks.values.forEach { it.apply(settings) }
        applyPlayerSettings()
        updateNotification()
    }

    private fun load(uri: Uri, name: String) {
        releasePlayer()
        title = name; error = null
        try {
            val next = MediaPlayer()
            player = next
            next.setAudioAttributes(attributes)
            next.setDataSource(this, uri)
            next.setOnPreparedListener { ready ->
                if (ready !== player) return@setOnPreparedListener
                prepared = true
                localRack = EffectRack(ready.audioSessionId).also { it.apply(settings) }
                reverbFailed = false
                reverb = runCatching { PresetReverb(0, 0) }.getOrElse { reverbFailed = true; null }
                applyPlayerSettings()
                if (audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) ready.start()
                else error = "Otra aplicación tiene prioridad de audio. Pulsa reproducir para intentarlo otra vez."
                updateNotification()
            }
            next.setOnCompletionListener { resumeAfterFocus = false; audioManager.abandonAudioFocusRequest(focusRequest); updateNotification() }
            next.setOnErrorListener { _, _, _ ->
                error = "No se pudo reproducir este archivo. Prueba otro formato de audio."
                releasePlayer(); updateNotification(); true
            }
            next.prepareAsync()
        } catch (_: Exception) { error = "No se pudo abrir el archivo de audio."; releasePlayer() }
        updateNotification()
    }

    private fun applyPlayerSettings() {
        if (!prepared) return
        val enabled = settings.optBoolean("enabled", false)
        val pan = if (enabled) settings.optDouble("balance", 0.0).coerceIn(-1.0, 1.0).toFloat() else 0f
        val duck = if (ducked) 0.2f else 1f
        player?.setVolume((if (pan > 0) 1 - pan else 1f) * duck, (if (pan < 0) 1 + pan else 1f) * duck)
        reverbFailed = reverbFailed || runCatching {
            reverb?.let {
                val preset = settings.optInt("reverb", 0).coerceIn(0, 6)
                it.preset = preset.toShort()
                check(it.setEnabled(enabled && preset != 0) == AudioEffect.SUCCESS)
                player?.attachAuxEffect(it.id)
                player?.setAuxEffectSendLevel(if (enabled && preset != 0) settings.optDouble("wet", 0.25).coerceIn(0.0, 1.0).toFloat() else 0f)
            }
        }.isFailure
    }

    fun togglePlayback() {
        if (!prepared) return
        error = null; resumeAfterFocus = false
        if (player?.isPlaying == true) { player?.pause(); audioManager.abandonAudioFocusRequest(focusRequest) }
        else if (audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { ducked = false; applyPlayerSettings(); player?.start() }
        else error = "El teléfono no concedió el foco de audio. Inténtalo otra vez."
        updateNotification()
    }
    fun seek(position: Int) { if (prepared) player?.seekTo(position.coerceIn(0, player?.duration ?: 0)) }

    fun snapshot(): Map<String, Any?> {
        val racks = listOfNotNull(localRack) + externalRacks.values
        val available = listOf("equalizer", "bass", "gain", "reverb").associateWith { name -> racks.any { it.capabilities()[name] == true } }.toMutableMap()
        if (prepared) available["reverb"] = available["reverb"] == true || (!reverbFailed && runCatching { reverb?.hasControl() == true }.getOrDefault(false))
        return mapOf("running" to true, "hasTrack" to prepared, "playing" to (prepared && player?.isPlaying == true),
            "position" to (if (prepared) player?.currentPosition else 0), "duration" to (if (prepared) player?.duration else 0),
            "title" to title, "sessions" to externalRacks.size, "capabilities" to available, "error" to error,
            "advancedDetection" to advancedDetection(), "detectionError" to detectionError,
            "reverbError" to externalRacks.values.mapNotNull { it.reverbError() }.firstOrNull())
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, AudioService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val toggle = PendingIntent.getService(this, 2, Intent(this, AudioService::class.java).setAction(TOGGLE), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "audio").setContentTitle("Audiowav")
            .setContentText(title ?: "Motor activo · esperando una sesión compatible")
            .setSmallIcon(R.drawable.ic_wave).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .apply { if (prepared) addAction(Notification.Action.Builder(null, if (player?.isPlaying == true) "Pausar" else "Reproducir", toggle).build()) }
            .addAction(Notification.Action.Builder(null, "Detener", stop).build()).build()
    }
    private fun updateNotification() { (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(7, notification()) }

    private fun releasePlayer() {
        prepared = false; resumeAfterFocus = false; ducked = false
        player?.release(); player = null
        localRack?.release(); localRack = null
        runCatching { reverb?.release() }; reverb = null
        audioManager.abandonAudioFocusRequest(focusRequest)
    }
    override fun onDestroy() {
        instance = null
        detector.shutdownNow()
        mainHandler.removeCallbacksAndMessages(null)
        settings.put("enabled", false)
        getSharedPreferences("studio", MODE_PRIVATE).edit().putString("settings", settings.toString()).apply()
        unregisterReceiver(receiver)
        releasePlayer()
        externalRacks.values.forEach { it.release() }; externalRacks.clear()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null

    override fun dump(fd: FileDescriptor, writer: PrintWriter, args: Array<out String>?) {
        writer.println("Audiowav audio diagnostics")
        writer.println("advancedDetection=${advancedDetection()} detectionError=$detectionError")
        writer.println("settings=$settings")
        writer.println("local=${localRack?.diagnostics()}")
        externalRacks.forEach { (session, rack) -> writer.println("session=$session actual=${rack.diagnostics()}") }
    }
}
