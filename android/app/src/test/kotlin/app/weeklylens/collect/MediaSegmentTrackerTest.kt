package app.weeklylens.collect

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaSegmentTrackerTest {

    private data class Seg(val pkg: String, val start: Long, val end: Long)

    private sealed interface Step
    private data class State(val session: String, val pkg: String, val playing: Boolean, val at: Long) : Step
    private data class Gone(val session: String, val at: Long) : Step
    private data class CloseAll(val at: Long) : Step

    @Test
    fun turnsPlaybackStatesIntoSegments() {
        data class Case(val name: String, val steps: List<Step>, val expected: List<Seg>)

        val cases = listOf(
            Case(
                "play then pause gives one segment",
                listOf(State("s1", "video", true, 100), State("s1", "video", false, 160)),
                listOf(Seg("video", 100, 160)),
            ),
            Case(
                "repeated playing states do not restart the segment",
                listOf(
                    State("s1", "video", true, 100),
                    State("s1", "video", true, 130),
                    State("s1", "video", false, 160),
                ),
                listOf(Seg("video", 100, 160)),
            ),
            Case(
                "a pause without a play is ignored",
                listOf(State("s1", "video", false, 100)),
                emptyList(),
            ),
            Case(
                "two sessions are tracked independently",
                listOf(
                    State("s1", "video", true, 100),
                    State("s2", "podcast", true, 110),
                    State("s1", "video", false, 150),
                    State("s2", "podcast", false, 200),
                ),
                listOf(Seg("video", 100, 150), Seg("podcast", 110, 200)),
            ),
            Case(
                "a session that disappears while playing is closed",
                listOf(State("s1", "video", true, 100), Gone("s1", 140)),
                listOf(Seg("video", 100, 140)),
            ),
            Case(
                "closeAll ends every open segment (listener unbound)",
                listOf(State("s1", "video", true, 100), State("s2", "music", true, 120), CloseAll(300)),
                listOf(Seg("video", 100, 300), Seg("music", 120, 300)),
            ),
            Case(
                "zero-length segments are dropped",
                listOf(State("s1", "video", true, 100), State("s1", "video", false, 100)),
                emptyList(),
            ),
        )

        for (case in cases) {
            val out = mutableListOf<Seg>()
            val tracker = MediaSegmentTracker { pkg, start, end -> out += Seg(pkg, start, end) }
            for (step in case.steps) when (step) {
                is State -> tracker.onPlaybackState(step.session, step.pkg, step.playing, step.at)
                is Gone -> tracker.onSessionGone(step.session, step.at)
                is CloseAll -> tracker.closeAll(step.at)
            }
            assertEquals(case.name, case.expected.sortedBy { it.start }, out.sortedBy { it.start })
        }
    }
}
