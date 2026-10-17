package com.audiowav.audiowav

import java.nio.ByteBuffer
import org.json.JSONObject

/** JNI ownership belongs exclusively to the PCM playback thread. */
class NativeReverb(sampleRate: Int) : AutoCloseable {
    companion object { init { System.loadLibrary("audiowav_dsp") } }
    private var handle = create(sampleRate).also { check(it != 0L) { "No se pudo crear el motor DSP." } }
    private external fun create(rate: Int): Long
    private external fun configure(handle: Long, parameters: FloatArray)
    private external fun process(handle: Long, buffer: ByteBuffer, frames: Int)
    private external fun reset(handle: Long)
    private external fun destroy(handle: Long)
    fun configure(parameters: FloatArray) = configure(handle, parameters)
    fun process(buffer: ByteBuffer, frames: Int) = process(handle, buffer, frames)
    fun reset() = reset(handle)
    override fun close() { destroy(handle); handle = 0 }
}

object DspSettings {
    fun from(settings: JSONObject): FloatArray {
        val p = settings.optJSONObject("reverbParams") ?: JSONObject()
        fun value(key: String, default: Double, min: Double, max: Double): Float {
            val v = p.optDouble(key, default)
            return (if (v.isFinite()) v.coerceIn(min, max) else default).toFloat()
        }
        return floatArrayOf(
            if (settings.optBoolean("enabled") && settings.optInt("reverb") != 0) 1f else 0f,
            value("decay", 1.4, .1, 20.0), value("preDelay", 10.0, 0.0, 100.0),
            value("size", 85.0, 0.0, 100.0), value("diffusion", 100.0, 0.0, 100.0),
            value("hfRatio", .8, .1, 2.0), value("hfLevel", -6.0, -90.0, 0.0),
            value("earlyLevel", .25, 0.0, 1.0), value("earlyDelay", 7.0, 0.0, 300.0),
            settings.optDouble("wet", .25).let { if (it.isFinite()) it.coerceIn(0.0, 1.0).toFloat() else .25f },
            value("dry", 1.0, 0.0, 1.0), value("lowCut", 20.0, 20.0, 2000.0),
            value("highCut", 18000.0, 2000.0, 20000.0), value("width", 1.0, 0.0, 2.0), 1f
        )
    }
}
