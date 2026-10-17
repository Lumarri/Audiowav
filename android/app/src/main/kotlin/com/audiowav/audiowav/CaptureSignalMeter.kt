package com.audiowav.audiowav

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

/** Aggregate measurements only. No audio samples are retained. */
class CaptureSignalMeter {
    private var samples = 0L
    private var squared = 0.0
    private var peak = 0.0
    private var signalBlocks = 0

    @Synchronized fun add(pcm: ShortArray, count: Int) {
        require(count in 0..pcm.size)
        if (count == 0) return
        var blockSquared = 0.0
        for (i in 0 until count) {
            val value = pcm[i] / 32768.0
            blockSquared += value * value
            peak = maxOf(peak, abs(value))
        }
        samples += count
        squared += blockSquared
        if (sqrt(blockSquared / count) > .0001) signalBlocks++
    }

    @Synchronized fun snapshot(): Map<String, Any> = mapOf(
        "frames" to samples / 2,
        "rmsDb" to if (squared > 0 && samples > 0) (20 * log10(sqrt(squared / samples))).coerceAtLeast(-120.0) else -120.0,
        "peakDb" to if (peak > 0) (20 * log10(peak)).coerceAtLeast(-120.0) else -120.0,
        "signalDetected" to (signalBlocks >= 3),
        "signalBlocks" to signalBlocks
    )
}
