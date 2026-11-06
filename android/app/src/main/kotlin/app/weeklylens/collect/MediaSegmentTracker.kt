package app.weeklylens.collect

/**
 * Turns MediaSession playback states into closed [start, end) segments per session.
 * Only closed segments are emitted; an open one is lost if the process dies, which costs at
 * most the time since the last state change.
 */
class MediaSegmentTracker(private val sink: (pkg: String, start: Long, end: Long) -> Unit) {

    private data class Open(val pkg: String, val start: Long)

    private val open = mutableMapOf<String, Open>()

    @Synchronized
    fun onPlaybackState(session: String, pkg: String, playing: Boolean, at: Long) {
        if (playing) {
            open.putIfAbsent(session, Open(pkg, at))
        } else {
            close(session, at)
        }
    }

    @Synchronized
    fun onSessionGone(session: String, at: Long) = close(session, at)

    @Synchronized
    fun closeAll(at: Long) {
        for (session in open.keys.toList()) close(session, at)
    }

    private fun close(session: String, at: Long) {
        val o = open.remove(session) ?: return
        if (at > o.start) sink(o.pkg, o.start, at)
    }
}
