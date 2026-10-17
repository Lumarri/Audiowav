package com.audiowav.audiowav

import org.junit.Assert.*
import org.junit.Test

class CaptureSignalMeterTest {
    @Test fun silenceDoesNotConfirmCompatibility() {
        val meter = CaptureSignalMeter()
        repeat(20) { meter.add(ShortArray(2048), 2048) }
        val result = meter.snapshot()
        assertEquals(false, result["signalDetected"])
        assertEquals(-120.0, result["peakDb"])
        assertEquals(20480L, result["frames"])
    }

    @Test fun oneClickDoesNotCountAsConfirmedSignal() {
        val meter = CaptureSignalMeter()
        meter.add(shortArrayOf(32767, -32768), 2)
        repeat(20) { meter.add(ShortArray(2048), 2048) }
        assertEquals(false, meter.snapshot()["signalDetected"])
    }

    @Test fun repeatedSignalIsDetectedAndOnlyValidSamplesAreMeasured() {
        val meter = CaptureSignalMeter()
        val pcm = shortArrayOf(16384, -16384, 32767, -32768)
        repeat(3) { meter.add(pcm, 2) }
        pcm.fill(0)
        val result = meter.snapshot()
        assertEquals(true, result["signalDetected"])
        assertEquals(3L, result["frames"])
        assertEquals(-6.0206, result["peakDb"] as Double, .0001)
        assertEquals(-6.0206, result["rmsDb"] as Double, .0001)
    }
}
