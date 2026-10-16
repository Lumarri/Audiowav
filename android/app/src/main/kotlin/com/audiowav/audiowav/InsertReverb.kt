package com.audiowav.audiowav

import android.media.audiofx.AudioEffect
import android.media.audiofx.EnvironmentalReverb
import kotlin.math.log10
import kotlin.math.roundToInt

/** Public Android API; requires the OEM's environmental effect to support an insert session. */
class InsertReverb(session: Int) {
    private val effect = EnvironmentalReverb(0, session).also {
        if (it.descriptor.connectMode != AudioEffect.EFFECT_INSERT) {
            it.release()
            error("El dispositivo no permite reverberación de inserción para otras apps.")
        }
    }
    private var lastMode = -1
    var failure: String? = null
        private set

    fun apply(enabled: Boolean, mode: Int, wet: Double) {
        failure = runCatching {
            check(effect.hasControl()) { "Otra aplicación controla la reverberación." }
            if (mode != lastMode && mode != 0) {
                val decay = intArrayOf(0, 400, 850, 1400, 1800, 3200, 2200)[mode.coerceIn(0, 6)]
                effect.roomLevel = (-600).toShort()
                effect.roomHFLevel = (if (mode == 6) -200 else -600).toShort()
                effect.decayTime = decay
                effect.decayHFRatio = (if (mode == 6) 1100 else 800).toShort()
                effect.reflectionsLevel = (-1200).toShort()
                effect.reflectionsDelay = if (mode >= 4) 20 else 7
                effect.reverbDelay = if (mode >= 4) 25 else 10
                effect.diffusion = 1000.toShort()
                effect.density = (if (mode == 6) 1000 else 850).toShort()
                lastMode = mode
            }
            if (mode != 0) {
                val level = if (wet <= 0) -9000 else (2000 * log10(wet.coerceIn(0.0001, 1.0))).roundToInt().coerceIn(-9000, 0)
                effect.reverbLevel = level.toShort()
            }
            check(effect.setEnabled(enabled && mode != 0 && wet > 0) == AudioEffect.SUCCESS)
        }.exceptionOrNull()?.let { it.message ?: "No se pudo aplicar la reverberación." }
        if (failure != null) runCatching { effect.setEnabled(false) }
    }

    fun available() = failure == null && runCatching { effect.hasControl() }.getOrDefault(false)
    fun diagnostics(): Map<String, Any?> = mapOf(
        "enabled" to runCatching { effect.enabled }.getOrNull(),
        "decayMs" to runCatching { effect.decayTime }.getOrNull(),
        "levelMb" to runCatching { effect.reverbLevel }.getOrNull()
    )
    fun release() { runCatching { effect.release() } }
}
