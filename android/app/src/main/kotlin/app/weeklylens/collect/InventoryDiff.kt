package app.weeklylens.collect

/** A launchable app at snapshot time. The label is kept so a removed app can still be named. */
data class InstalledApp(val pkg: String, val label: String, val firstInstall: Long, val category: Int)

data class PackageChange(val pkg: String, val label: String, val kind: Kind, val at: Long, val exact: Boolean) {
    enum class Kind { INSTALLED, REMOVED }
}

/**
 * Derives installs and removals from two inventory snapshots.
 *
 * Installs are exact: PackageInfo.firstInstallTime survives, so even the first run can backfill
 * them. Removals leave no trace in the system, so they are only known from the moment we have a
 * previous snapshot; their time is the snapshot time unless the PACKAGE_FULLY_REMOVED broadcast
 * already logged them (passed in as [knownRemovals]).
 */
object InventoryDiff {
    fun diff(
        previous: List<InstalledApp>?,
        current: List<InstalledApp>,
        now: Long,
        backfillSince: Long,
        knownRemovals: Set<String>,
    ): List<PackageChange> {
        if (previous == null) {
            return current
                .filter { it.firstInstall >= backfillSince }
                .map { install(it) }
        }
        val before = previous.associateBy { it.pkg }
        val after = current.associateBy { it.pkg }

        val installs = current.filter { app ->
            val old = before[app.pkg]
            old == null || app.firstInstall > old.firstInstall
        }.map { install(it) }

        val removals = previous
            .filter { it.pkg !in after && it.pkg !in knownRemovals }
            .map { PackageChange(it.pkg, it.label, PackageChange.Kind.REMOVED, now, exact = false) }

        return installs + removals
    }

    private fun install(app: InstalledApp) =
        PackageChange(app.pkg, app.label, PackageChange.Kind.INSTALLED, app.firstInstall, exact = true)
}
