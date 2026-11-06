package app.weeklylens.collect

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationCounterTest {

    private class FakeStore : NotificationStore {
        val active = mutableMapOf<String, String>()
        val inserted = mutableListOf<Triple<String, String, Long>>()
        val removed = mutableListOf<Pair<String, Long>>()

        override fun isActive(key: String) = key in active
        override fun insertArrival(key: String, pkg: String, postedAt: Long) {
            active[key] = pkg
            inserted += Triple(key, pkg, postedAt)
        }
        override fun markRemoved(key: String, removedAt: Long) {
            if (active.remove(key) != null) removed += key to removedAt
        }
        override fun activeKeys(): Set<String> = active.keys.toSet()
    }

    private data class Posted(val key: String, val pkg: String, val flags: Int, val at: Long)

    private sealed interface Step
    private data class Post(val n: Posted) : Step
    private data class Remove(val key: String, val at: Long) : Step

    private val own = "app.weeklylens"
    private val ongoing = 0x02 // Notification.FLAG_ONGOING_EVENT
    private val foregroundService = 0x40 // Notification.FLAG_FOREGROUND_SERVICE
    private val groupSummary = 0x200 // Notification.FLAG_GROUP_SUMMARY

    @Test
    fun countsEachArrivalOnceAndSkipsNoise() {
        data class Case(val name: String, val steps: List<Step>, val expectedArrivals: List<String>)

        val cases = listOf(
            Case(
                "a plain notification counts once",
                listOf(Post(Posted("k1", "chat", 0, 10))),
                listOf("k1"),
            ),
            Case(
                "an update re-posting the same key is not a new arrival",
                listOf(Post(Posted("k1", "chat", 0, 10)), Post(Posted("k1", "chat", 0, 20))),
                listOf("k1"),
            ),
            Case(
                "the same key after removal is a new arrival",
                listOf(
                    Post(Posted("k1", "chat", 0, 10)),
                    Remove("k1", 15),
                    Post(Posted("k1", "chat", 0, 20)),
                ),
                listOf("k1", "k1"),
            ),
            Case(
                "ongoing notifications (music, navigation) are skipped",
                listOf(Post(Posted("k2", "music", ongoing, 10))),
                emptyList(),
            ),
            Case(
                "foreground service notifications are skipped",
                listOf(Post(Posted("k3", "sync", foregroundService, 10))),
                emptyList(),
            ),
            Case(
                "group summaries are skipped, their children count",
                listOf(Post(Posted("sum", "mail", groupSummary, 10)), Post(Posted("c1", "mail", 0, 10))),
                listOf("c1"),
            ),
            Case(
                "our own notifications are skipped",
                listOf(Post(Posted("k4", own, 0, 10))),
                emptyList(),
            ),
        )

        for (case in cases) {
            val store = FakeStore()
            val counter = NotificationCounter(store, own)
            for (step in case.steps) when (step) {
                is Post -> counter.onPosted(step.n.key, step.n.pkg, step.n.flags, step.n.at)
                is Remove -> counter.onRemoved(step.key, step.at)
            }
            assertEquals(case.name, case.expectedArrivals, store.inserted.map { it.first })
        }
    }

    @Test
    fun reconcilesWithTheSystemWhenTheListenerReconnects() {
        val store = FakeStore()
        val counter = NotificationCounter(store, own)
        counter.onPosted("gone", "chat", 0, 10)
        counter.onPosted("kept", "chat", 0, 11)

        // While the listener was unbound, "gone" was dismissed and "new" arrived.
        counter.onReconnected(
            current = listOf(ActiveNotification("kept", "chat", 0, 11), ActiveNotification("new", "mail", 0, 30)),
            now = 40,
        )

        assertEquals("dismissed while unbound is closed at reconnect", listOf("gone" to 40L), store.removed)
        assertEquals(
            "posted while unbound is counted with its own post time",
            listOf(Triple("gone", "chat", 10L), Triple("kept", "chat", 11L), Triple("new", "mail", 30L)),
            store.inserted,
        )
    }
}
