package com.audiowav.audiowav

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.AudioTrack
import android.os.Process
import android.os.SystemClock
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/** One worker owns the recorder, output, JNI engine and source attenuation. No PCM is saved. */
@android.annotation.TargetApi(29)
class CapturedDspPlayer(
    private val capture: AudioPlaybackCaptureConfiguration,
    initialSettings: JSONObject,
    private val audioManager: AudioManager,
    private val onUpdate: (Map<String, Any?>) -> Unit,
    private val onError: (String) -> Unit
) {
    @Volatile private var stopped = false
    @Volatile private var settings = initialSettings
    @Volatile private var sessions: Set<Int> = emptySet()
    @Volatile var audioSessionId = 0
        private set
    private val thread = Thread({ run() }, "Audiowav-LiveDSP")
    fun start() = thread.start()
    fun stop() { stopped = true }
    fun configure(next: JSONObject) { settings = next }
    fun sourceSessions(next: Set<Int>) { sessions = next }

    private fun run() {
        var record: AudioRecord? = null
        var output: AudioTrack? = null
        var engine: NativeReverb? = null
        var rack: EffectRack? = null
        val attenuator = SourceAttenuator()
        val meter = CaptureSignalMeter()
        val pcm = ShortArray(1024)
        val encoded = ShortArray(1024)
        val block = ByteBuffer.allocateDirect(512 * 8).order(ByteOrder.nativeOrder())
        val floats = block.asFloatBuffer()
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val inputMin = AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            check(inputMin > 0) { "Entrada de captura no compatible." }
            record = AudioRecord.Builder().setAudioFormat(AudioFormat.Builder().setSampleRate(48000)
                .setChannelMask(AudioFormat.CHANNEL_IN_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(inputMin, 19200)).setAudioPlaybackCaptureConfig(capture).build()
            val outputMin = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            check(outputMin > 0) { "Salida DSP no compatible." }
            output = AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_NONE).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(outputMin, 9600)).setTransferMode(AudioTrack.MODE_STREAM).build()
            check(record.state == AudioRecord.STATE_INITIALIZED && output.state == AudioTrack.STATE_INITIALIZED)
            audioSessionId = output.audioSessionId
            rack = EffectRack(audioSessionId)
            engine = NativeReverb(48000)
            if (stopped) return
            record.startRecording()
            check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            val started = SystemClock.elapsedRealtime()
            var applied: JSONObject? = null
            var wasMuted = false
            var playing = false
            var writtenFrames = 0L
            var processedFrames = 0L
            var maxMicros = 0L
            var lastSignal = started
            var mutedSince = 0L
            var lastPublish = 0L
            var lastControlCheck = 0L
            var oldSessions: Set<Int> = emptySet()
            var receivedSignal = false
            while (!stopped) {
                val count = record.read(pcm, 0, pcm.size, AudioRecord.READ_NON_BLOCKING)
                if (stopped) break
                check(count >= 0) { "Se interrumpió la captura ($count)." }
                val now = SystemClock.elapsedRealtime()
                if (count == 0) {
                    check(receivedSignal || now - started < 12000) { "No llegó señal de la app elegida. Reproduce una canción y vuelve a activar el DSP." }
                    Thread.sleep(3); continue
                }
                check(count % 2 == 0) { "La captura perdió la alineación estéreo." }
                meter.add(pcm, count)
                var peak = 0
                for (i in 0 until count) peak = maxOf(peak, abs(pcm[i].toInt()))
                if (peak > 4) lastSignal = now
                val signal = meter.snapshot()["signalDetected"] == true
                receivedSignal = signal
                check(signal || now - started < 12000) { "No llegó señal de la app elegida. Reproduce una canción y vuelve a activar el DSP." }
                if (now - lastControlCheck >= 1000 || sessions != oldSessions) {
                    check(audioManager.mode == AudioManager.MODE_NORMAL) { "DSP detenido porque el teléfono está usando audio de comunicación." }
                    if (wasMuted && sessions.isNotEmpty() && now - mutedSince >= 1500 && now - lastSignal > 1500) {
                        attenuator.disable("La captura dejó de recibir señal al controlar el original. Se usa un retorno de reverb.")
                    }
                    val muted = attenuator.update(sessions, signal && playing && now - lastSignal < 1500)
                    if (muted && !wasMuted) mutedSince = now
                    val actualMuted = muted && attenuator.failure == null
                    if (wasMuted != actualMuted) applied = null
                    wasMuted = actualMuted
                    oldSessions = sessions
                    lastControlCheck = now
                }
                val next = settings
                if (applied !== next) {
                    engine.configure(CaptureDspSettings.from(next, wasMuted))
                    rack.apply(next)
                    applied = next
                }
                val frames = count / 2
                for (i in 0 until count) floats.put(i, pcm[i] / 32768f)
                val processingStart = System.nanoTime()
                engine.process(block, frames)
                maxMicros = maxOf(maxMicros, (System.nanoTime() - processingStart) / 1000)
                processedFrames += frames
                for (i in 0 until count) encoded[i] = (floats.get(i).coerceIn(-1f, 1f) * 32767).toInt().toShort()
                @Suppress("DEPRECATION")
                output.setStereoVolume((1 - next.optDouble("balance", 0.0).coerceAtLeast(0.0)).toFloat().coerceIn(0f, 1f),
                    (1 + next.optDouble("balance", 0.0).coerceAtMost(0.0)).toFloat().coerceIn(0f, 1f))
                var offset = 0
                while (!stopped && offset < count) {
                    val written = output.write(encoded, offset, count - offset, AudioTrack.WRITE_NON_BLOCKING)
                    check(written >= 0) { "Se interrumpió la salida DSP ($written)." }
                    offset += written
                    writtenFrames += written / 2
                    if (!playing && (writtenFrames >= output.bufferSizeInFrames || written == 0)) {
                        output.play(); playing = true
                    }
                    if (written == 0) Thread.sleep(2)
                }
                pcm.fill(0); encoded.fill(0)
                if (now - lastPublish >= 250) {
                    onUpdate(meter.snapshot() + mapOf("dspReady" to (signal && playing), "originalMuted" to wasMuted,
                        "muteError" to attenuator.failure, "outputSession" to audioSessionId,
                        "signalRecent" to (now - lastSignal < 1500),
                        "processedFrames" to processedFrames, "maxProcessMicros" to maxMicros,
                        "underruns" to output.underrunCount, "outputCapabilities" to rack.capabilities()))
                    lastPublish = now
                }
            }
        } catch (failure: Throwable) {
            if (!stopped) onError(failure.localizedMessage ?: "El DSP externo se interrumpió.")
        } finally {
            // Restore the source even if decoding, JNI, permission or output fails.
            attenuator.close()
            runCatching { output?.pause() }; runCatching { output?.release() }
            runCatching { record?.stop() }; runCatching { record?.release() }
            runCatching { rack?.release() }; runCatching { engine?.close() }
            audioSessionId = 0
            pcm.fill(0); encoded.fill(0)
        }
    }
}
