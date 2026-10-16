package com.audiowav.audiowav

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackSessionsTest {
    @Test fun detectsCurrentMusicAndGamesButIgnoresCallsLogsAndEffectTables() {
        val dump = """
            Global session refs:
              session cnt pid uid name
                555 1 42 1000 example
            2 Tracks of which 1 are active
                Type Id Active Client Session Port Id S Flags Format Chn mask SRate ST Usg CT G db
                   3991 yes 24821 30489 4150 A 0x000 00000001 00000003 48000 3 1 2 0
                   3992 no 24821 30490 4151 P 0x000 00000001 00000003 48000 3 1 2 0
            0 Effect Chains
            Local log:
               AT::add 3993 yes 24821 90000 4150 A 0x000 00000001 00000003 48000 3 1 2 0
            2 Tracks
                Type Id Active Client Session Port Id S Flags Format Chn mask SRate ST Usg CT G db
                F 4000 yes 1234 40001 42 A 0x001 00000001 00000003 48000 3 14 2 0
                F 4001 yes 1234 40002 43 A 0x001 00000001 00000003 48000 0 2 1 0
            1 Effect Chains
                Session State Registered Enabled Suspended:
                99999 003 y y n
        """.trimIndent()
        assertEquals(setOf(30489, 30490, 40001), PlaybackSessions.parse(dump))
    }
    @Test fun ignoresInvalidOrMissingPlaybackTables() {
        assertEquals(emptySet<Int>(), PlaybackSessions.parse("Permission Denial: cannot dump AudioFlinger"))
        assertEquals(emptySet<Int>(), PlaybackSessions.parse("3991 yes 24821 30489 4150 A 0x000 00000001 00000003 48000 3 1 2 0"))
    }
}
