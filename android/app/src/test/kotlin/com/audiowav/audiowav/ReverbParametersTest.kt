package com.audiowav.audiowav

import org.junit.Assert.assertEquals
import org.junit.Test

class ReverbParametersTest {
    @Test fun convertsStudioControlsToNativeUnits() {
        val p = ReverbParameters.from(mapOf("decay" to 8.5, "preDelay" to 45.0,
            "size" to 72.0, "diffusion" to 90.0, "hfRatio" to .6,
            "hfLevel" to -12.0, "earlyLevel" to .5, "earlyDelay" to 18.0), 3, .25)
        assertEquals(8500, p.decayMs)
        assertEquals(45, p.preDelayMs)
        assertEquals(720, p.density)
        assertEquals(900, p.diffusion)
        assertEquals(600, p.hfRatio)
        assertEquals(-1200, p.hfLevelMb)
        assertEquals(-602, p.earlyLevelMb)
        assertEquals(-1204, p.wetLevelMb)
    }
    @Test fun clampsUntrustedNativeValuesAndPreservesLegacyDefaults() {
        val legacy = ReverbParameters.from(emptyMap(), 5, 1.0)
        assertEquals(3200, legacy.decayMs)
        assertEquals(25, legacy.preDelayMs)
        val p = ReverbParameters.from(mapOf("decay" to 99.0, "size" to -50.0,
            "preDelay" to 900.0, "hfRatio" to Double.NaN, "earlyDelay" to 999.0), 3, -1.0)
        assertEquals(20000, p.decayMs)
        assertEquals(0, p.density)
        assertEquals(100, p.preDelayMs)
        assertEquals(800, p.hfRatio)
        assertEquals(300, p.earlyDelayMs)
        assertEquals(-9000, p.wetLevelMb)
    }
}
