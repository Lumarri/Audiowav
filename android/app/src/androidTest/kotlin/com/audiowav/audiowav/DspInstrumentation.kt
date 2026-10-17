package com.audiowav.audiowav

import android.app.Activity
import android.app.Instrumentation
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.audiofx.DynamicsProcessing
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.sin

/** Device checks for actual platform decoding, JNI and AudioTrack, with generated audio only. */
class DspInstrumentation : Instrumentation() {
    private var sourceControlOnly = false
    override fun onCreate(arguments: Bundle?) { sourceControlOnly = arguments?.getString("check") == "sourceControl"; super.onCreate(arguments); start() }
    override fun onStart() {
        val result = Bundle()
        try {
            if (sourceControlOnly) {
                sourceControlCheck()
                result.putString("stream", "\nPASS source attenuation and restoration on a generated silent audio session.\n")
                finish(Activity.RESULT_OK, result)
                return
            }
            jniSignalCheck()
            val stereo = File(targetContext.cacheDir, "dsp-test-stereo.wav")
            val mono = File(targetContext.cacheDir, "dsp-test-mono.wav")
            val aac = File(targetContext.cacheDir, "dsp-test-aac.m4a")
            wave(stereo, 2); wave(mono, 1); encodeAac(aac)
            val reports = listOf(stereo, mono, aac).map { playback(it) }
            result.putString("stream", "\nPASS native JNI dry/wet mapping\n${reports.joinToString("\n")}\nAll 4 device checks passed.\n")
            listOf(stereo, mono, aac).forEach { it.delete() }
            finish(Activity.RESULT_OK, result)
        } catch (failure: Throwable) {
            result.putString("stream", "\nFAIL: ${failure.stackTraceToString()}\n")
            finish(Activity.RESULT_CANCELED, result)
        }
    }
    private fun sourceControlCheck() {
        val track = AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_NONE).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(9600).build()
        var observer: DynamicsProcessing? = null
        val controller = SourceAttenuator()
        try {
            check(track.state == AudioTrack.STATE_INITIALIZED)
            track.write(ShortArray(4800), 0, 4800); track.play()
            // Exercise creation on a fresh session before an observer can initialize the engine.
            check(controller.update(setOf(track.audioSessionId), true)) { controller.failure ?: "No fresh-session source control" }
            controller.close()
            observer = DynamicsProcessing(-1, track.audioSessionId, null)
            check(controller.update(setOf(track.audioSessionId), true)) { controller.failure ?: "No source control" }
            check(observer.getInputGainByChannelIndex(0) <= -80f) { "Original attenuation was not applied" }
            controller.close()
            check(kotlin.math.abs(observer.getInputGainByChannelIndex(0)) < .01f) { "Original gain was not restored" }
            check(!observer.enabled) { "Source attenuation remained enabled after close" }
        } finally {
            controller.close(); observer?.release(); track.pause(); track.release()
        }
    }
    private fun jniSignalCheck() {
        NativeReverb(48000).use { engine ->
            val buffer = ByteBuffer.allocateDirect(1024*8).order(ByteOrder.nativeOrder())
            val floats = buffer.asFloatBuffer()
            val settings = JSONObject("""{"enabled":true,"reverb":3,"wet":0,"reverbParams":{"dry":0.25}}""")
            floats.put(0, .4f); floats.put(1, -.2f)
            engine.configure(DspSettings.from(settings)); engine.process(buffer, 1024)
            check(kotlin.math.abs(floats.get(0)-.1f) < .000001f && kotlin.math.abs(floats.get(1)+.05f) < .000001f) { "JNI dry gain mapping failed" }
            settings.getJSONObject("reverbParams").put("dry", 0)
            engine.reset(); engine.configure(DspSettings.from(settings))
            for (i in 0 until 2048) floats.put(i, .2f)
            engine.process(buffer, 1024)
            for (i in 0 until 2048) check(floats.get(i) == 0f) { "JNI wet/dry mute failed" }
        }
    }
    private fun until(message: String, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
        while (!condition()) {
            check(System.nanoTime() < deadline) { message }
            Thread.sleep(20)
        }
    }
    private fun playback(file: File): String {
        val prepared = CountDownLatch(1)
        val completed = CountDownLatch(1)
        val failure = AtomicReference<String?>(null)
        val player = PcmPlayer(targetContext, Uri.fromFile(file),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build(),
            Handler(Looper.getMainLooper()), onReady = { prepared.countDown() },
            onComplete = { completed.countDown() }, onError = { _, message -> failure.set(message); prepared.countDown(); completed.countDown() })
        try {
            val config = JSONObject("""{"enabled":true,"reverb":3,"wet":0.4,"reverbParams":{"decay":0.3,"preDelay":30,"dry":0.5}}""")
            // Five percent output gain; the source itself is also quiet.
            player.configure(DspSettings.from(config), 0f, .05f)
            player.prepareAsync()
            check(prepared.await(15, TimeUnit.SECONDS)) { "Preparation timed out: ${file.name}" }
            check(failure.get() == null) { failure.get().orEmpty() }
            check(player.ready && player.duration >= 1900) { "Incorrect decoder metadata" }
            player.start()
            until("Playback did not advance") { player.currentPosition >= 250 || failure.get() != null }
            check(failure.get() == null) { failure.get().orEmpty() }
            val startUnderruns = player.underruns
            player.pause()
            Thread.sleep(100)
            val paused = player.currentPosition
            Thread.sleep(200)
            check(kotlin.math.abs(player.currentPosition - paused) <= 30) { "Position advanced while paused" }
            player.seekTo(1000)
            until("Paused seek did not reset position") { player.currentPosition in 980..1050 || failure.get() != null }
            config.getJSONObject("reverbParams").put("lowCut", 250).put("highCut", 6000).put("width", .5)
            player.configure(DspSettings.from(config), -.25f, .05f)
            player.start()
            until("Playback did not resume after seek") { player.currentPosition >= 1250 || failure.get() != null }
            check(failure.get() == null) { failure.get().orEmpty() }
            val seekUnderruns = player.underruns
            check(completed.await(15, TimeUnit.SECONDS)) { "End of stream or tail did not complete" }
            check(failure.get() == null) { failure.get().orEmpty() }
            check(player.processedFrames > 0 && !player.isPlaying) { "DSP did not process or stop" }
            val endUnderruns = player.underruns
            player.start()
            until("Replay after EOS failed") { player.currentPosition in 100..750 || failure.get() != null }
            check(failure.get() == null) { failure.get().orEmpty() }
            return "PASS ${file.name}: ${player.sampleRate} Hz, ${player.processedFrames} DSP frames, max block ${player.maxProcessMicros} us; underruns start=$startUnderruns afterSeek=$seekUnderruns atEOF=$endUnderruns afterReplay=${player.underruns}; pause/seek/EOF/replay"
        } finally { player.release() }
    }
    private fun wave(file: File, channels: Int) {
        val rate = 48000
        val count = rate * 2
        val bytes = count * channels * 2
        val buffer = ByteBuffer.allocate(44 + bytes).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray()).putInt(36+bytes).put("WAVEfmt ".toByteArray()).putInt(16)
        buffer.putShort(1).putShort(channels.toShort()).putInt(rate).putInt(rate*channels*2).putShort((channels*2).toShort()).putShort(16)
        buffer.put("data".toByteArray()).putInt(bytes)
        repeat(count) { frame -> repeat(channels) { ch -> buffer.putShort((sin(frame*2*Math.PI*(220+ch*110)/rate)*1200).toInt().toShort()) } }
        file.writeBytes(buffer.array())
    }
    private fun encodeAac(file: File) {
        val rate = 48000
        val codec = MediaCodec.createEncoderByType("audio/mp4a-latm")
        val muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        try {
            val format = MediaFormat.createAudioFormat("audio/mp4a-latm", rate, 2).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 128000)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE); codec.start()
            var inputFrame = 0; var sentEos = false; var trackIndex = -1
            val info = MediaCodec.BufferInfo()
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
            while (System.nanoTime() < deadline) {
                if (!sentEos) {
                    val slot = codec.dequeueInputBuffer(5000)
                    if (slot >= 0) {
                        val input = codec.getInputBuffer(slot)!!.order(ByteOrder.nativeOrder()); input.clear()
                        val frames = minOf(1024, rate*2-inputFrame, input.capacity()/4)
                        repeat(frames) { offset -> repeat(2) { input.putShort((sin((inputFrame+offset)*2*Math.PI*330/rate)*1200).toInt().toShort()) } }
                        val eos = frames == 0
                        codec.queueInputBuffer(slot, 0, frames*4, inputFrame*1000000L/rate, if (eos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                        inputFrame += frames; sentEos = eos
                    }
                }
                val slot = codec.dequeueOutputBuffer(info, 5000)
                if (slot == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) { trackIndex = muxer.addTrack(codec.outputFormat); muxer.start(); started = true }
                else if (slot >= 0) {
                    if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        check(started)
                        muxer.writeSampleData(trackIndex, codec.getOutputBuffer(slot)!!, info)
                    }
                    val done = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(slot, false)
                    if (done) return
                }
            }
            error("AAC fixture encoding timed out")
        } finally {
            runCatching { codec.stop() }; codec.release()
            if (started) runCatching { muxer.stop() }
            muxer.release()
        }
    }
}
