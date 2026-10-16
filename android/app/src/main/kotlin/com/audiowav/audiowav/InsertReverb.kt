package com.audiowav.audiowav

import android.media.MediaPlayer
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.media.audiofx.AudioEffect
import android.media.audiofx.EnvironmentalReverb
import org.json.JSONObject
import kotlin.math.abs

/** Keeps one native engine alive and commits a changed parameter block in a single call. */
class InsertReverb(session: Int, private val requireInsert: Boolean = true) {
    companion object {
        private val learnedDecayLimits = mutableMapOf<java.util.UUID, Int>()
        private var limitPreferences: SharedPreferences? = null
        fun loadDeviceLimits(context: Context) {
            limitPreferences = context.applicationContext.getSharedPreferences("reverb-limits", Context.MODE_PRIVATE)
        }
    }
    private val effect = EnvironmentalReverb(0, session).also {
        val expected = if (requireInsert) AudioEffect.EFFECT_INSERT else AudioEffect.EFFECT_AUXILIARY
        if (it.descriptor.connectMode != expected) {
            it.release()
            error("El dispositivo no ofrece el modo de reverberación requerido.")
        }
    }
    private var lastParameters: ReverbParameters? = null
    private var lastEnabled: Boolean? = null
    private var propertyWrites = 0
    private val limitKey = "${Build.FINGERPRINT}:${effect.descriptor.uuid}"
    private var maxDecayMs = learnedDecayLimits[effect.descriptor.uuid] ?: limitPreferences?.getInt(limitKey, 20000) ?: 20000
    private var controls: Map<String, Boolean> = emptyMap()
    var failure: String? = null
        private set

    fun attachTo(player: MediaPlayer) {
        check(!requireInsert)
        player.attachAuxEffect(effect.id)
        player.setAuxEffectSendLevel(1f)
    }

    fun apply(settings: JSONObject) {
        val mode = settings.optInt("reverb", 0).coerceIn(0, 6)
        val json = settings.optJSONObject("reverbParams")
        val values = json?.keys()?.asSequence()?.associateWith { json.optDouble(it) } ?: emptyMap()
        val requested = ReverbParameters.from(values, mode, settings.optDouble("wet", .25))
        val p = requested.copy(decayMs = requested.decayMs.coerceAtMost(maxDecayMs))
        val enabled = settings.optBoolean("enabled") && mode != 0 && p.wet > 0
        failure = runCatching {
            check(effect.hasControl()) { "Otra aplicación controla la reverberación de esta sesión." }
            if (lastParameters != p) {
                effect.properties = EnvironmentalReverb.Settings().apply {
                    roomLevel = (-600).toShort()
                    roomHFLevel = p.hfLevelMb.toShort()
                    decayTime = p.decayMs
                    decayHFRatio = p.hfRatio.toShort()
                    reflectionsLevel = p.earlyLevelMb.toShort()
                    reflectionsDelay = p.earlyDelayMs
                    reverbLevel = p.wetLevelMb.toShort()
                    reverbDelay = p.preDelayMs
                    diffusion = p.diffusion.toShort()
                    density = p.density.toShort()
                }
                propertyWrites++
                val actual = effect.properties
                if (actual.decayTime in 100 until (p.decayMs - 2)) {
                    maxDecayMs = minOf(maxDecayMs, actual.decayTime)
                    learnedDecayLimits[effect.descriptor.uuid] = maxDecayMs
                    limitPreferences?.edit()?.putInt(limitKey, maxDecayMs)?.apply()
                }
                controls = mapOf(
                    "decay" to (actual.decayTime in 100..20000),
                    "preDelay" to (abs(actual.reverbDelay - p.preDelayMs) <= 1),
                    "size" to (abs(actual.density.toInt() - p.density) <= 10),
                    "diffusion" to (abs(actual.diffusion.toInt() - p.diffusion) <= 10),
                    "hfRatio" to (abs(actual.decayHFRatio.toInt() - p.hfRatio) <= 2),
                    "hfLevel" to (abs(actual.roomHFLevel.toInt() - p.hfLevelMb) <= 2),
                    "earlyLevel" to (abs(actual.reflectionsLevel.toInt() - p.earlyLevelMb) <= 2),
                    "earlyDelay" to (abs(actual.reflectionsDelay - p.earlyDelayMs) <= 1),
                    "wet" to (abs(actual.reverbLevel.toInt() - p.wetLevelMb) <= 2)
                )
                lastParameters = p.copy(decayMs = p.decayMs.coerceAtMost(maxDecayMs))
            }
            if (lastEnabled != enabled) {
                val status = effect.setEnabled(enabled)
                check(status == AudioEffect.SUCCESS) { "Android no pudo activar la reverb en esta sesión (código $status)." }
                lastEnabled = enabled
            }
        }.exceptionOrNull()?.let { it.message ?: "No se pudo aplicar la reverberación." }
        if (failure != null) { runCatching { effect.setEnabled(false) }; lastEnabled = null }
    }

    fun controlSupport() = controls
    fun maximumDecayMs() = maxDecayMs
    fun available() = failure == null && runCatching { effect.hasControl() }.getOrDefault(false)
    fun diagnostics(): Map<String, Any?> = runCatching {
        val p = effect.properties
        mapOf("enabled" to effect.enabled, "decayMs" to p.decayTime,
            "preDelayMs" to p.reverbDelay, "density" to p.density, "diffusion" to p.diffusion,
            "hfRatio" to p.decayHFRatio, "hfLevelMb" to p.roomHFLevel,
            "earlyLevelMb" to p.reflectionsLevel, "earlyDelayMs" to p.reflectionsDelay,
            "levelMb" to p.reverbLevel, "maxDecayMs" to maxDecayMs, "propertyWrites" to propertyWrites, "controls" to controls)
    }.getOrDefault(mapOf("error" to failure))
    fun release() { runCatching { effect.release() } }
}
