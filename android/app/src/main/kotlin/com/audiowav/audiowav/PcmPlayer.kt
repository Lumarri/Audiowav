package com.audiowav.audiowav

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Process
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Decodes local files to PCM, runs the C++ DSP, then streams a bounded audio queue. */
class PcmPlayer(
    private val context: Context, private val uri: Uri, private val attributes: AudioAttributes,
    private val main: Handler, private val onReady: (PcmPlayer) -> Unit,
    private val onComplete: (PcmPlayer) -> Unit, private val onError: (PcmPlayer, String) -> Unit
) {
    private val gate = Object()
    private val seekRequest = AtomicLong(-1)
    @Volatile private var closed = false
    @Volatile private var wantPlay = false
    @Volatile private var ended = false
    @Volatile private var track: AudioTrack? = null
    @Volatile private var parameters = FloatArray(15).also { it[1] = 1.4f; it[10] = 1f }
    @Volatile private var pan = 0f
    @Volatile private var volume = 1f
    @Volatile private var baseMs = 0L
    @Volatile var duration = 0
        private set
    @Volatile var sampleRate = 48000
        private set
    @Volatile var audioSessionId = 0
        private set
    @Volatile var ready = false
        private set
    @Volatile var tail = false
        private set
    @Volatile var processedFrames = 0L
        private set
    @Volatile var maxProcessMicros = 0L
        private set
    val isPlaying get() = wantPlay && ready && !closed
    val underruns get() = runCatching { track?.underrunCount ?: 0 }.getOrDefault(0)
    val currentPosition: Int get() {
        val frames = runCatching { track?.playbackHeadPosition?.toLong()?.and(0xffffffffL) ?: 0L }.getOrDefault(0L)
        return (baseMs + frames * 1000 / sampleRate).coerceIn(0L, duration.toLong()).toInt()
    }
    private val thread = Thread({ decode() }, "Audiowav-PCM")
    fun prepareAsync() = thread.start()
    fun configure(values: FloatArray, balance: Float, level: Float) {
        parameters = values
        pan = balance.coerceIn(-1f, 1f); volume = level.coerceIn(0f, 1f)
    }
    fun start() {
        if (closed) return
        if (ended) { seekRequest.set(0); ended = false }
        wantPlay = true
        synchronized(gate) { gate.notifyAll() }
    }
    fun pause() {
        synchronized(gate) {
            wantPlay = false
            runCatching { track?.pause() }
        }
    }
    fun seekTo(ms: Int) {
        seekRequest.set(ms.coerceIn(0, duration).toLong())
        synchronized(gate) { gate.notifyAll() }
    }
    fun release() {
        closed = true; wantPlay = false
        runCatching { track?.pause() }
        synchronized(gate) { gate.notifyAll() }
        // Codec, track and native memory are released by their owning thread.
    }
    private fun waitUntilPlaying(): Boolean {
        synchronized(gate) {
            while (!closed && !wantPlay && seekRequest.get() < 0) gate.wait()
        }
        return !closed && seekRequest.get() < 0
    }

    private fun decode() {
        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var dsp: NativeReverb? = null
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val source = MediaExtractor().also { extractor = it; it.setDataSource(context, uri, null) }
            val index = (0 until source.trackCount).firstOrNull {
                source.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("El archivo no contiene una pista de audio.")
            source.selectTrack(index)
            val format = source.getTrackFormat(index)
            duration = if (format.containsKey(MediaFormat.KEY_DURATION))
                (format.getLong(MediaFormat.KEY_DURATION) / 1000).coerceIn(0, Int.MAX_VALUE.toLong()).toInt() else 0
            val mime = format.getString(MediaFormat.KEY_MIME) ?: error("Formato de audio desconocido.")
            var channels = 2
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var engine: NativeReverb? = null
            val block = ByteBuffer.allocateDirect(1024 * 8).order(ByteOrder.nativeOrder())
            val floats = block.asFloatBuffer()
            var applied: FloatArray? = null
            var framesWritten = 0L
            var playbackStarted = false
            var primedBytes = 0
            var skipUntilUs = 0L

            fun outputFormat(f: MediaFormat) {
                val rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val count = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val pcm = if (f.containsKey(MediaFormat.KEY_PCM_ENCODING)) f.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                check(count in 1..2) { "El motor DSP admite archivos mono y estéreo. Convierte el audio multicanal a estéreo." }
                check(rate in 8000..192000) { "Frecuencia de muestreo no compatible." }
                check(pcm == AudioFormat.ENCODING_PCM_16BIT || pcm == AudioFormat.ENCODING_PCM_FLOAT) { "El decodificador produjo un formato PCM no compatible." }
                if (track != null) {
                    check(rate == sampleRate && count == channels && pcm == encoding) { "El formato del archivo cambia durante la reproducción." }
                    return
                }
                sampleRate = rate; channels = count; encoding = pcm
                val minimum = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_FLOAT)
                check(minimum > 0) { "El teléfono no admite esta salida de audio." }
                val output = AudioTrack.Builder().setAudioAttributes(attributes)
                    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_FLOAT).build())
                    .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(max(minimum, rate * 8 / 20)).build()
                track = output
                check(output.state == AudioTrack.STATE_INITIALIZED) { "No se pudo abrir la salida de audio." }
                audioSessionId = output.audioSessionId
                engine = NativeReverb(rate).also { dsp = it }
                ready = true
                main.post { if (!closed) onReady(this) }
            }

            fun writeBlock(frames: Int): Boolean {
                if (!waitUntilPlaying()) return false
                val next = parameters
                if (applied !== next) { engine!!.configure(next); applied = next }
                val started = System.nanoTime()
                engine!!.process(block, frames)
                maxProcessMicros = max(maxProcessMicros, (System.nanoTime() - started) / 1000)
                processedFrames += frames
                val output = track!!
                @Suppress("DEPRECATION")
                output.setStereoVolume((if (pan > 0) 1 - pan else 1f) * volume, (if (pan < 0) 1 + pan else 1f) * volume)
                block.position(0); block.limit(frames * 8)
                while (block.hasRemaining() && !closed && seekRequest.get() < 0) {
                    if (!waitUntilPlaying()) return false
                    val bytes = synchronized(gate) {
                        if (!wantPlay || closed || seekRequest.get() >= 0) 0 else {
                            if (playbackStarted && output.playState != AudioTrack.PLAYSTATE_PLAYING) output.play()
                            val written = output.write(block, block.remaining(), AudioTrack.WRITE_NON_BLOCKING)
                            // A seek can leave a first AAC packet shorter than one block.
                            // Queue the full output buffer before starting its playback clock.
                            if (!playbackStarted && written >= 0) {
                                primedBytes += written
                                if (primedBytes >= output.bufferSizeInFrames * 8 || written == 0) {
                                    output.play(); playbackStarted = true
                                }
                            }
                            written
                        }
                    }
                    check(bytes >= 0) { "La salida de audio se interrumpió ($bytes)." }
                    if (bytes == 0) synchronized(gate) { gate.wait(4) }
                }
                framesWritten += frames
                return !closed && seekRequest.get() < 0
            }
            fun pcm(buffer: ByteBuffer, timestampUs: Long): Boolean {
                buffer.order(ByteOrder.nativeOrder())
                val bytesPerFrame = channels * (if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2)
                if (timestampUs < skipUntilUs) {
                    val skip = min(buffer.remaining() / bytesPerFrame, ((skipUntilUs - timestampUs) * sampleRate / 1000000).toInt())
                    buffer.position(buffer.position() + skip * bytesPerFrame)
                }
                while (buffer.remaining() >= bytesPerFrame && !closed && seekRequest.get() < 0) {
                    val frames = min(1024, buffer.remaining() / bytesPerFrame)
                    floats.position(0)
                    repeat(frames) {
                        val left = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) buffer.float else buffer.short / 32768f
                        val right = if (channels == 1) left else if (encoding == AudioFormat.ENCODING_PCM_FLOAT) buffer.float else buffer.short / 32768f
                        floats.put(left); floats.put(right)
                    }
                    if (!writeBlock(frames)) return false
                }
                return !closed && seekRequest.get() < 0
            }
            fun resetForSeek(ms: Long) {
                track?.pause(); track?.flush()
                engine?.reset(); framesWritten = 0; applied = null; playbackStarted = false; primedBytes = 0
                baseMs = ms; skipUntilUs = ms * 1000
                source.seekTo(ms * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                decoder?.flush()
                tail = false; ended = false
            }

            val raw = mime == "audio/raw"
            if (raw) outputFormat(format)
            else {
                val codec = MediaCodec.createDecoderByType(mime)
                decoder = codec
                codec.configure(format, null, null, 0); codec.start()
            }
            val rawBuffer = if (raw) ByteBuffer.allocateDirect(1024 * 1024) else null
            val info = MediaCodec.BufferInfo()
            var inputEos = false
            var outputEos = false
            while (!closed) {
                val seek = seekRequest.getAndSet(-1)
                if (seek >= 0) { resetForSeek(seek); inputEos = false; outputEos = false }
                if (ended) { waitUntilPlaying(); continue }
                if (outputEos) {
                    tail = true
                    // Render decay until quiet, with an absolute 22-second tail budget.
                    var tailFrames = 0
                    var quietFrames = 0
                    while (!closed && seekRequest.get() < 0 && tailFrames < sampleRate * 22) {
                        floats.position(0); repeat(2048) { floats.put(0f) }
                        if (!writeBlock(1024)) break
                        var peak = 0f
                        for (i in 0 until 2048) peak = max(peak, abs(floats.get(i)))
                        quietFrames = if (peak < .00003f) quietFrames + 1024 else 0
                        tailFrames += 1024
                        if (quietFrames >= sampleRate / 2) break
                    }
                    // Let already queued frames reach the speaker before reporting completion.
                    if (!playbackStarted && !closed && seekRequest.get() < 0) {
                        track?.play(); playbackStarted = true
                    }
                    while (!closed && seekRequest.get() < 0 && (track!!.playbackHeadPosition.toLong() and 0xffffffffL) < framesWritten) {
                        if (!waitUntilPlaying()) break
                        synchronized(gate) { gate.wait(5) }
                    }
                    if (closed || seekRequest.get() >= 0) continue
                    wantPlay = false; ended = true; tail = false; track?.pause()
                    main.post { if (!closed) onComplete(this) }
                    continue
                }
                if (ready && !waitUntilPlaying()) continue
                if (raw) {
                    val buffer = rawBuffer!!; buffer.clear()
                    val size = source.readSampleData(buffer, 0)
                    if (size < 0) { outputEos = true; continue }
                    buffer.position(0); buffer.limit(size)
                    pcm(buffer, source.sampleTime)
                    source.advance()
                } else {
                    val codec = decoder!!
                    if (!inputEos) {
                        val slot = codec.dequeueInputBuffer(5000)
                        if (slot >= 0) {
                            val buffer = codec.getInputBuffer(slot)!!; buffer.clear()
                            val size = source.readSampleData(buffer, 0)
                            if (size < 0) { codec.queueInputBuffer(slot, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputEos = true }
                            else { codec.queueInputBuffer(slot, 0, size, source.sampleTime, 0); source.advance() }
                        }
                    }
                    val slot = codec.dequeueOutputBuffer(info, 5000)
                    if (slot == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) outputFormat(codec.outputFormat)
                    else if (slot >= 0) {
                        if (!ready) outputFormat(codec.outputFormat)
                        try {
                            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                val buffer = codec.getOutputBuffer(slot)!!
                                buffer.position(info.offset); buffer.limit(info.offset + info.size)
                                pcm(buffer, info.presentationTimeUs)
                            }
                            outputEos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        } finally { codec.releaseOutputBuffer(slot, false) }
                    }
                }
            }
        } catch (failure: Throwable) {
            if (!closed) main.post { if (!closed) onError(this, failure.message ?: "No se pudo reproducir el archivo con DSP.") }
        } finally {
            ready = false; wantPlay = false
            runCatching { decoder?.stop() }; runCatching { decoder?.release() }
            runCatching { extractor?.release() }; runCatching { track?.release() }
            track = null; runCatching { dsp?.close() }
        }
    }
}
