// The int-flag PackageManager overloads are deprecated on API 33+ but are the only ones below it.
@file:Suppress("DEPRECATION")

package app.weeklylens.bridge

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import app.weeklylens.collect.ActivityDb
import app.weeklylens.collect.Collector
import app.weeklylens.collect.PackageChange

/** Host side of the Pigeon contract: reads the local store, never aggregates. */
class ActivityApiImpl(private val context: Context) : ActivityApi {

    private val db get() = ActivityDb.get(context)

    override fun permissions() = PermissionState(
        usageAccess = Collector.hasUsageAccess(context),
        notificationAccess = Collector.hasNotificationAccess(context),
        adsAccess = Collector.hasAdsAccess(context),
    )

    override fun openSettings(screen: SettingsScreen) {
        val intent = when (screen) {
            SettingsScreen.USAGE_ACCESS -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            SettingsScreen.NOTIFICATION_ACCESS -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            SettingsScreen.ACCESSIBILITY -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            SettingsScreen.APP_INFO ->
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    override fun syncNow() = Collector(context).run()

    override fun rawRange(usageFrom: Long, start: Long, end: Long): RawRange {
        val usage = db.usageColumns(usageFrom, end, Collector.REPORTED_TYPES)
        val notifications = db.notifications(start, end)
        val media = db.mediaSegments(start, end)
        val changes = db.packageChanges(start, end)
        val ads = db.adImpressions(start, end)

        val inventory = db.inventory().associateBy { it.pkg }
        // Every package the report can name, so none of them falls back to its raw id.
        val seen = HashSet<String>(usage.strings.size)
        usage.pkg.forEach { seen += usage.strings[it] }
        notifications.forEach { seen += it.first }
        media.forEach { seen += it.first }
        changes.forEach { seen += it.pkg }
        ads.forEach { seen += it.first }
        val apps = seen.map { pkg ->
            inventory[pkg]?.let { RawApp(it.pkg, it.label, it.category.toLong()) } ?: describe(pkg)
        }

        return RawRange(
            usage = usage,
            notifications = notifications.map { (pkg, at) -> RawNotification(pkg, at) },
            media = media.map { (pkg, s, e) -> RawMediaSegment(pkg, s, e) },
            packageChanges = changes.map {
                RawPackageChange(it.pkg, it.label, it.kind == PackageChange.Kind.INSTALLED, it.at, it.exact)
            },
            ads = ads.map { (pkg, adv, at) -> RawAdImpression(pkg, adv, at) },
            apps = apps,
            homePackages = homePackages(),
            earliestUsageEvent = db.getLong(Collector.KEY_EARLIEST_USAGE) ?: 0,
            notificationsSince = db.getLong(Collector.KEY_NOTIFICATIONS_SINCE) ?: 0,
            adsSince = db.getLong(Collector.KEY_ADS_SINCE) ?: 0,
        )
    }

    override fun wipe() = Collector(context).wipe()

    /** Label for a package outside the launcher inventory (visible only if it has a launcher icon). */
    private fun describe(pkg: String): RawApp = try {
        val ai = context.packageManager.getApplicationInfo(pkg, 0)
        RawApp(pkg, context.packageManager.getApplicationLabel(ai).toString(), ai.category.toLong())
    } catch (_: PackageManager.NameNotFoundException) {
        RawApp(pkg, pkg, -1)
    }

    private fun homePackages(): List<String> {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return context.packageManager.queryIntentActivities(home, 0)
            .map { it.activityInfo.packageName }
            .distinct()
    }
}
