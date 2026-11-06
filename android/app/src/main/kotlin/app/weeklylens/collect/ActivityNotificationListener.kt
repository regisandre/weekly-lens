package app.weeklylens.collect

import android.content.ComponentName
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * One permission (Notification access) gives two signals:
 * notification arrivals, and the media sessions other apps publish (play/pause state),
 * which is the only cross-app view of "time spent watching or listening" Android offers.
 */
class ActivityNotificationListener : NotificationListenerService() {

    private lateinit var counter: NotificationCounter
    private lateinit var tracker: MediaSegmentTracker
    private val callbacks = mutableMapOf<MediaController, MediaController.Callback>()
    private val main = Handler(Looper.getMainLooper())

    /** Every SQLite read and write runs here, in order, never on the main thread. */
    private lateinit var io: ExecutorService

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        syncSessions(controllers.orEmpty())
    }

    override fun onCreate() {
        super.onCreate()
        io = Executors.newSingleThreadExecutor()
        val db = ActivityDb.get(this)
        counter = NotificationCounter(db, packageName)
        tracker = MediaSegmentTracker { pkg, start, end -> io.execute { db.insertMediaSegment(pkg, start, end) } }
    }

    override fun onDestroy() {
        io.shutdown() // queued writes still run
        super.onDestroy()
    }

    override fun onListenerConnected() {
        val now = System.currentTimeMillis()
        val current = activeNotifications.orEmpty().map {
            ActiveNotification(it.key, it.packageName, it.notification.flags, it.postTime)
        }
        io.execute {
            val db = ActivityDb.get(this)
            if (db.getLong(Collector.KEY_NOTIFICATIONS_SINCE) == null) db.putLong(Collector.KEY_NOTIFICATIONS_SINCE, now)
            db.inTransaction { counter.onReconnected(current, now) }
        }

        val msm = getSystemService(MediaSessionManager::class.java)
        val me = ComponentName(this, ActivityNotificationListener::class.java)
        msm.addOnActiveSessionsChangedListener(sessionsListener, me, main)
        syncSessions(msm.getActiveSessions(me))
    }

    override fun onListenerDisconnected() {
        getSystemService(MediaSessionManager::class.java).removeOnActiveSessionsChangedListener(sessionsListener)
        for ((controller, cb) in callbacks) controller.unregisterCallback(cb)
        callbacks.clear()
        tracker.closeAll(System.currentTimeMillis())
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val key = sbn.key
        val pkg = sbn.packageName
        val flags = sbn.notification.flags
        val at = sbn.postTime
        io.execute { counter.onPosted(key, pkg, flags, at) }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val key = sbn.key
        val at = System.currentTimeMillis()
        io.execute { counter.onRemoved(key, at) }
    }

    private fun syncSessions(controllers: List<MediaController>) {
        val now = System.currentTimeMillis()
        val tokens = controllers.map { it.sessionToken }.toSet()
        for (gone in callbacks.keys.filter { it.sessionToken !in tokens }) {
            gone.unregisterCallback(callbacks.remove(gone)!!)
            tracker.onSessionGone(key(gone), now)
        }
        for (c in controllers) {
            if (callbacks.keys.any { it.sessionToken == c.sessionToken }) continue
            val cb = object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) {
                    tracker.onPlaybackState(key(c), c.packageName, state?.state == PlaybackState.STATE_PLAYING, System.currentTimeMillis())
                }

                override fun onSessionDestroyed() {
                    tracker.onSessionGone(key(c), System.currentTimeMillis())
                }
            }
            c.registerCallback(cb, main)
            callbacks[c] = cb
            tracker.onPlaybackState(key(c), c.packageName, c.playbackState?.state == PlaybackState.STATE_PLAYING, now)
        }
    }

    private fun key(c: MediaController) = "${c.packageName}#${c.sessionToken.hashCode()}"
}
