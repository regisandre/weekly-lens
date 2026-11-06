// The int-flag PackageManager overloads are deprecated on API 33+ but are the only ones below it.
@file:Suppress("DEPRECATION")

package app.weeklylens.collect

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Process
import android.provider.Settings
import android.util.Log
import java.util.concurrent.TimeUnit

/**
 * Pulls what the OS keeps only for a short time into our own store.
 * Safe to run any number of times: usage rows are de-duplicated by the table's UNIQUE key.
 */
class Collector(private val context: Context) {

    private val db = ActivityDb.get(context)

    /** The worker, a manual sync and a wipe build their own Collector, so they lock the shared store. */
    fun run(now: Long = System.currentTimeMillis()) = synchronized(db) {
        if (hasUsageAccess(context)) ingestUsage(now)
        snapshotInventory(now)
        db.prune(now - RETENTION_MS)
    }

    /**
     * The user's "delete my data": drops every collected row. Each live source restarts its history
     * now, so the next sync does not re-import what the OS still keeps and the report does not show
     * a source that is still recording as switched off.
     */
    fun wipe(now: Long = System.currentTimeMillis()) = synchronized(db) {
        db.wipeHistory()
        val restart = mapOf(
            KEY_EARLIEST_USAGE to hasUsageAccess(context),
            KEY_USAGE_CURSOR to hasUsageAccess(context),
            KEY_NOTIFICATIONS_SINCE to hasNotificationAccess(context),
            KEY_ADS_SINCE to hasAdsAccess(context),
        )
        for ((key, live) in restart) if (live) db.putLong(key, now) else db.remove(key)
    }

    private fun ingestUsage(now: Long) {
        val usm = context.getSystemService(UsageStatsManager::class.java)
        val cursor = db.getLong(KEY_USAGE_CURSOR)
        // First run: ask for far more than the OS keeps and record what actually came back.
        val from = cursor?.minus(OVERLAP_MS) ?: (now - FIRST_RUN_LOOKBACK_MS)
        val events = usm.queryEvents(from, now)
        val rows = ArrayList<UsageRow>()
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType in KEPT_TYPES) rows += UsageRow(e.timeStamp, e.packageName, e.className ?: "", e.eventType)
        }
        db.insertUsageEvents(rows)
        // Set on the first run that returns anything, not only the very first run.
        if (db.getLong(KEY_EARLIEST_USAGE) == null) {
            rows.minOfOrNull { it.ts }?.let { db.putLong(KEY_EARLIEST_USAGE, it) }
        }
        db.putLong(KEY_USAGE_CURSOR, now)
        Log.i(TAG, "usage ingest: ${rows.size} events from $from")
    }

    private fun snapshotInventory(now: Long) {
        val previousAt = db.getLong(KEY_INVENTORY_AT)
        val current = launchableApps()
        val previous = if (previousAt == null) null else db.inventory()
        val changes = InventoryDiff.diff(
            previous = previous,
            current = current,
            now = now,
            backfillSince = now - FIRST_RUN_LOOKBACK_MS,
            knownRemovals = previousAt?.let { db.removedSince(it) } ?: emptySet(),
        )
        // One transaction: a crash halfway must not replay the same changes on the next run.
        db.inTransaction {
            db.insertPackageChanges(changes)
            db.replaceInventory(current)
            db.putLong(KEY_INVENTORY_AT, now)
        }
    }

    /** Apps with a launcher icon: the ones a user thinks of as "installed". */
    private fun launchableApps(): List<InstalledApp> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName }
            .distinct()
            .filter { it != context.packageName }
            .mapNotNull { pkg ->
                try {
                    val info = pm.getPackageInfo(pkg, 0)
                    val ai = info.applicationInfo ?: return@mapNotNull null
                    InstalledApp(pkg, pm.getApplicationLabel(ai).toString(), info.firstInstallTime, ai.category)
                } catch (_: PackageManager.NameNotFoundException) {
                    null
                }
            }
    }

    companion object {
        private const val TAG = "WeeklyLens"
        const val KEY_USAGE_CURSOR = "usage_cursor"
        const val KEY_EARLIEST_USAGE = "earliest_usage_event"
        const val KEY_INVENTORY_AT = "inventory_at"
        const val KEY_NOTIFICATIONS_SINCE = "notifications_since"
        const val KEY_ADS_SINCE = "ads_since"

        private val OVERLAP_MS = TimeUnit.MINUTES.toMillis(10)
        private val FIRST_RUN_LOOKBACK_MS = TimeUnit.DAYS.toMillis(30)
        val RETENTION_MS: Long = TimeUnit.DAYS.toMillis(7L * 8)

        val KEPT_TYPES = setOf(
            UsageEvents.Event.ACTIVITY_RESUMED,
            UsageEvents.Event.ACTIVITY_PAUSED,
            UsageEvents.Event.ACTIVITY_STOPPED,
            UsageEvents.Event.SCREEN_INTERACTIVE,
            UsageEvents.Event.SCREEN_NON_INTERACTIVE,
            UsageEvents.Event.KEYGUARD_SHOWN,
            UsageEvents.Event.KEYGUARD_HIDDEN,
            UsageEvents.Event.DEVICE_SHUTDOWN,
            UsageEvents.Event.DEVICE_STARTUP,
        )

        /**
         * What the report reads today. SCREEN_INTERACTIVE and KEYGUARD_SHOWN are stored so the rules
         * can change later without losing history, but they are not shipped to the UI.
         */
        val REPORTED_TYPES = KEPT_TYPES - setOf(UsageEvents.Event.SCREEN_INTERACTIVE, UsageEvents.Event.KEYGUARD_SHOWN)

        fun hasUsageAccess(context: Context): Boolean {
            val ops = context.getSystemService(AppOpsManager::class.java)
            return ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName,
            ) == AppOpsManager.MODE_ALLOWED
        }

        fun hasNotificationAccess(context: Context): Boolean {
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(context, ActivityNotificationListener::class.java)
            return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
        }

        fun hasAdsAccess(context: Context): Boolean {
            val flat = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = ComponentName(context, AdObserverService::class.java)
            return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
        }
    }
}
