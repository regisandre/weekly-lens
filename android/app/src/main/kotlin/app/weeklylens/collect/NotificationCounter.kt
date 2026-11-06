package app.weeklylens.collect

/** Persistence port for notification arrivals, so the counting rules run without Android. */
interface NotificationStore {
    fun isActive(key: String): Boolean
    fun insertArrival(key: String, pkg: String, postedAt: Long)
    fun markRemoved(key: String, removedAt: Long)
    fun activeKeys(): Set<String>
}

data class ActiveNotification(val key: String, val pkg: String, val flags: Int, val postedAt: Long)

/**
 * Turns the raw NotificationListenerService callbacks into "arrivals".
 *
 * An app re-posts the same key to update a notification (progress, a new message in a thread),
 * so an arrival is a key that is not already showing. Ongoing, foreground-service and group
 * summary notifications are excluded: they are status, not something the user "received".
 */
class NotificationCounter(private val store: NotificationStore, private val ownPackage: String) {

    fun onPosted(key: String, pkg: String, flags: Int, postedAt: Long) {
        if (!counts(pkg, flags)) return
        if (store.isActive(key)) return
        store.insertArrival(key, pkg, postedAt)
    }

    fun onRemoved(key: String, removedAt: Long) = store.markRemoved(key, removedAt)

    /** The listener can be unbound by the system; resync with what is showing now. */
    fun onReconnected(current: List<ActiveNotification>, now: Long) {
        val showing = current.map { it.key }.toSet()
        for (key in store.activeKeys() - showing) store.markRemoved(key, now)
        for (n in current) onPosted(n.key, n.pkg, n.flags, n.postedAt)
    }

    private fun counts(pkg: String, flags: Int): Boolean =
        pkg != ownPackage && flags and EXCLUDED_FLAGS == 0

    companion object {
        // Notification.FLAG_ONGOING_EVENT | FLAG_FOREGROUND_SERVICE | FLAG_GROUP_SUMMARY
        const val EXCLUDED_FLAGS = 0x02 or 0x40 or 0x200
    }
}
