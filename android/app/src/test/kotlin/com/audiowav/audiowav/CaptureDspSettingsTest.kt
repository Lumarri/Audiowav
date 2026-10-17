package com.audiowav.audiowav

import org.junit.Assert.*
import org.junit.Test

class CaptureDspSettingsTest {
    private fun values(enabled: Float) = FloatArray(15).also { it[0] = enabled; it[9] = .6f; it[10] = .8f; it[13] = 1.7f }
    @Test fun wetReturnNeverDuplicatesTheOriginal() {
        val source = values(1f)
        val routed = CaptureDspSettings.forRoute(source, false)
        assertEquals(0f, routed[10], 0f)
        assertEquals(.6f, routed[9], 0f)
        assertEquals(1f, routed[0], 0f)
        assertEquals(.8f, source[10], 0f)
    }
    @Test fun bypassMutesAnAdditiveReturnInsteadOfPlayingDryAudio() {
        val routed = CaptureDspSettings.forRoute(values(0f), false)
        assertEquals(1f, routed[0], 0f)
        assertEquals(0f, routed[9], 0f)
        assertEquals(0f, routed[10], 0f)
    }
    @Test fun replacementPreservesTheFullDryWetSettings() {
        val source = values(1f)
        assertArrayEquals(source, CaptureDspSettings.forRoute(source, true), 0f)
    }
}
