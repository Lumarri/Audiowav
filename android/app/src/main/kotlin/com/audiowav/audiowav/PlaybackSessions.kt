package com.audiowav.audiowav

/** Parses only current music/game playback track tables, never logs or recording tracks. */
object PlaybackSessions {
    fun parse(dump: String): Set<Int> {
        val sessions = mutableSetOf<Int>()
        var inPlaybackTable = false
        for (line in dump.lineSequence()) {
            val text = line.trim()
            if (text.startsWith("Type") && text.contains("Active") && text.contains("Client") && text.contains("Session")) {
                inPlaybackTable = true
                continue
            }
            if (!inPlaybackTable) continue
            val fields = text.split(Regex("\\s+"))
            val active = fields.indexOfFirst { it == "yes" || it == "no" }
            if (active !in 1..2 || fields.size <= active + 10) {
                inPlaybackTable = false
                continue
            }
            val session = fields.getOrNull(active + 2)?.toIntOrNull() ?: continue
            val stream = fields.getOrNull(active + 9)?.toIntOrNull()
            val usage = fields.getOrNull(active + 10)?.toIntOrNull()
            if (fields[active] == "yes" && session > 0 && stream == 3 && usage in setOf(1, 14)) sessions.add(session)
        }
        return sessions
    }
}
