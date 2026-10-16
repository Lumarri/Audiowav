package com.audiowav.audiowav

import kotlin.math.log10
import kotlin.math.roundToInt

/** Normalized public EnvironmentalReverb parameters, independent of Android for JVM tests. */
data class ReverbParameters(
    val decayMs: Int, val preDelayMs: Int, val density: Int, val diffusion: Int,
    val hfRatio: Int, val hfLevelMb: Int, val earlyLevelMb: Int, val earlyDelayMs: Int,
    val wetLevelMb: Int, val wet: Double
) {
    companion object {
        fun level(value: Double): Int = if (value <= 0 || !value.isFinite()) -9000
            else (2000 * log10(value.coerceIn(0.0001, 1.0))).roundToInt().coerceIn(-9000, 0)

        fun from(values: Map<String, Double>, mode: Int, wet: Double): ReverbParameters {
            val m = mode.coerceIn(0, 6)
            fun v(key: String, fallback: Double, min: Double, max: Double) =
                (values[key]?.takeIf { it.isFinite() } ?: fallback).coerceIn(min, max)
            val mix = wet.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.0
            return ReverbParameters(
                (v("decay", doubleArrayOf(1.4, .4, .85, 1.4, 1.8, 3.2, 2.2)[m], .1, 20.0) * 1000).roundToInt(),
                v("preDelay", if (m >= 4) 25.0 else 10.0, 0.0, 100.0).roundToInt(),
                (v("size", if (m == 6) 100.0 else 85.0, 0.0, 100.0) * 10).roundToInt(),
                (v("diffusion", 100.0, 0.0, 100.0) * 10).roundToInt(),
                (v("hfRatio", if (m == 6) 1.1 else .8, .1, 2.0) * 1000).roundToInt(),
                (v("hfLevel", if (m == 6) -2.0 else -6.0, -90.0, 0.0) * 100).roundToInt(),
                level(v("earlyLevel", .25, 0.0, 1.0)),
                v("earlyDelay", if (m >= 4) 20.0 else 7.0, 0.0, 300.0).roundToInt(),
                level(mix), mix
            )
        }
    }
}
