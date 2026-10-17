package com.audiowav.audiowav

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackSessionsTest {
    @Test fun ownershipFilterNeverSelectsOtherAppsOrStaleReferences() {
        val dump = """
            Notification Clients:
              pid uid name
              123 10242 app.rvx.android.apps.youtube.music
              124 10264 com.audiowav.audiowav
              125 10242 app.rvx.android.apps.youtube.music:audio
            Global session refs:
              session cnt pid uid name
              999 1 123 10242 app.rvx.android.apps.youtube.music
            3 Tracks of which 2 are active
              Type Id Active Client Session Port Id S Flags Format Chn mask SRate ST Usg CT G db
              10 yes 123 100 15 A 0x000 00000001 00000003 48000 3 1 2 0
              11 yes 124 101 16 A 0x000 00000001 00000003 48000 3 1 2 0
              F1 12 yes 125 102 17 A 0x000 00000001 00000003 48000 3 e 2 0
              13 no 123 103 18 P 0x000 00000001 00000003 48000 3 1 2 0
            Local log:
              14 yes 123 104 19 A 0x000 00000001 00000003 48000 3 1 2 0
        """.trimIndent()
        assertEquals(setOf(100, 102), PlaybackSessions.forUid(dump, 10242))
        assertEquals(setOf(101), PlaybackSessions.forUid(dump, 10264))
        assertEquals(emptySet<Int>(), PlaybackSessions.forUid(dump, 99999))
    }

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
        assertEquals(setOf(30489, 40001), PlaybackSessions.parse(dump))
    }
    @Test fun ignoresInvalidOrMissingPlaybackTables() {
        assertEquals(emptySet<Int>(), PlaybackSessions.parse("Permission Denial: cannot dump AudioFlinger"))
        assertEquals(emptySet<Int>(), PlaybackSessions.parse("3991 yes 24821 30489 4150 A 0x000 00000001 00000003 48000 3 1 2 0"))
    }
}
