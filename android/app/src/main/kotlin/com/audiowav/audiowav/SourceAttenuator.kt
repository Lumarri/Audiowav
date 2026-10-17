package com.audiowav.audiowav

import android.media.audiofx.AudioEffect
import android.media.audiofx.DynamicsProcessing

/** Owned by the DSP worker. Only sessions verified against the chosen UID are accepted. */
class SourceAttenuator : AutoCloseable {
    private val effects = mutableMapOf<Int, DynamicsProcessing>()
    var failure: String? = null
        private set

    fun update(sessions: Set<Int>, allowed: Boolean): Boolean {
        val wanted = if (allowed && failure == null) sessions.filter { it > 0 }.toSet() else emptySet()
        (effects.keys - wanted).forEach { release(it) }
        if (wanted.isEmpty()) return false
        var step = "crear el control"
        try {
            for (session in wanted - effects.keys) {
                // Let Android choose its supported architecture and actual channel count.
                // Some implementations reject the optional time-domain variant on a fresh session.
                step = "crear el control de la sesión $session"
                val effect = DynamicsProcessing(0, session, null)
                effects[session] = effect
                check(effect.hasControl()) { "Otra app controla el volumen de esta sesión." }
                step = "atenuar el original"
                effect.setInputGainAllChannelsTo(-90f)
                step = "activar la atenuación"
                check(effect.setEnabled(true) == AudioEffect.SUCCESS && effect.enabled)
                step = "verificar la atenuación"
                check(effect.getInputGainByChannelIndex(0) <= -80f) { "Android no confirmó la atenuación del original." }
            }
            check(effects.values.all { it.hasControl() && it.enabled }) { "Se perdió el control del original." }
            return true
        } catch (error: Exception) {
            disable("No se pudo $step: ${error.localizedMessage ?: "Android rechazó el control."}")
            return false
        }
    }

    fun disable(reason: String) { failure = reason; close() }
    private fun release(session: Int) {
        effects.remove(session)?.let { effect ->
            runCatching { if (effect.hasControl()) { effect.setInputGainAllChannelsTo(0f); effect.setEnabled(false) } }
            runCatching { effect.release() }
        }
    }
    override fun close() { effects.keys.toList().forEach { release(it) } }
}
