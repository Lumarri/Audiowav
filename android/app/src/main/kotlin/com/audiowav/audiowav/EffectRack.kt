package com.audiowav.audiowav

import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import org.json.JSONObject
import kotlin.math.ln
import kotlin.math.roundToInt

/** Each rack owns effects for one real session; never attaches insert effects to session 0. */
class EffectRack(session: Int) {
    private var eq = runCatching { Equalizer(0, session) }.getOrNull()
    private var bass = runCatching { BassBoost(0, session) }.getOrNull()
    private var gain = runCatching { LoudnessEnhancer(session) }.getOrNull()
    private val frequencies = doubleArrayOf(60.0, 230.0, 910.0, 3600.0, 14000.0)
    private var eqFailed = false
    private var bassFailed = false
    private var gainFailed = false

    fun apply(settings: JSONObject) {
        val enabled = settings.optBoolean("enabled", false)
        eqFailed = runCatching {
            eq?.let { effect ->
                val range = effect.bandLevelRange
                val bands = settings.optJSONArray("bands")
                val levels = DoubleArray(5) { bands?.optDouble(it, 0.0)?.coerceIn(-12.0, 12.0) ?: 0.0 }
                for (band in 0 until effect.numberOfBands.toInt()) {
                    val frequency = effect.getCenterFreq(band.toShort()) / 1000.0
                    val level = interpolate(frequency, levels)
                    effect.setBandLevel(band.toShort(), (level * 100).roundToInt().coerceIn(range[0].toInt(), range[1].toInt()).toShort())
                }
                check(effect.setEnabled(enabled) == AudioEffect.SUCCESS)
            }
        }.isFailure
        bassFailed = runCatching {
            bass?.let {
                val strength = settings.optDouble("bass", 0.0).coerceIn(0.0, 1.0)
                if (it.strengthSupported) it.setStrength((strength * 1000).roundToInt().toShort())
                check(it.setEnabled(enabled && strength > 0) == AudioEffect.SUCCESS)
            }
        }.isFailure
        gainFailed = runCatching {
            gain?.let {
                val db = settings.optDouble("gain", 0.0).coerceIn(0.0, 12.0)
                it.setTargetGain((db * 100).roundToInt())
                check(it.setEnabled(enabled && db > 0) == AudioEffect.SUCCESS)
            }
        }.isFailure
    }

    private fun interpolate(frequency: Double, levels: DoubleArray): Double {
        if (frequency <= frequencies.first()) return levels.first()
        if (frequency >= frequencies.last()) return levels.last()
        for (i in 0..3) {
            if (frequency <= frequencies[i + 1]) {
                val weight = ln(frequency / frequencies[i]) / ln(frequencies[i + 1] / frequencies[i])
                return levels[i] + weight * (levels[i + 1] - levels[i])
            }
        }
        return 0.0
    }

    fun capabilities() = mapOf(
        "equalizer" to (!eqFailed && runCatching { eq?.hasControl() == true }.getOrDefault(false)),
        "bass" to (!bassFailed && runCatching { bass?.hasControl() == true && bass?.strengthSupported == true }.getOrDefault(false)),
        "gain" to (!gainFailed && runCatching { gain?.hasControl() == true }.getOrDefault(false))
    )

    fun release() {
        listOf(eq, bass, gain).forEach { effect -> runCatching { effect?.release() } }
        eq = null; bass = null; gain = null
    }
}
