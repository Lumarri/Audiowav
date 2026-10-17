package com.audiowav.audiowav

/** Parses only current music/game playback track tables, never logs or recording tracks. */
object PlaybackSessions {
    fun parse(dump: String): Set<Int> = parseTracks(dump).map { it.second }.toSet()

    fun forUid(dump: String, uid: Int): Set<Int> {
        val pids = mutableSetOf<Int>()
        var clients = false
        for (line in dump.lineSequence()) {
            val text = line.trim()
            if (text == "Notification Clients:") { clients = true; continue }
            if (!clients || text.startsWith("pid")) continue
            val fields = text.split(Regex("\\s+"))
            val pid = fields.getOrNull(0)?.toIntOrNull()
            val owner = fields.getOrNull(1)?.toIntOrNull()
            if (pid == null || owner == null || fields.size != 3) { clients = false; continue }
            if (owner == uid) pids.add(pid)
        }
        return parseTracks(dump).filter { it.first in pids }.map { it.second }.toSet()
    }

    private fun parseTracks(dump: String): Set<Pair<Int, Int>> {
        val tracks = mutableSetOf<Pair<Int, Int>>()
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
            val pid = fields.getOrNull(active + 1)?.toIntOrNull() ?: continue
            val stream = fields.getOrNull(active + 9)?.toIntOrNull()
            val usage = fields.getOrNull(active + 10)
            if (fields[active] == "yes" && session > 0 && stream == 3 && usage in setOf("0", "1", "14", "e")) tracks.add(pid to session)
        }
        return tracks
    }
}
