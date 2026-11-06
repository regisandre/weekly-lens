package app.weeklylens.collect

import app.weeklylens.collect.PackageChange.Kind.INSTALLED
import app.weeklylens.collect.PackageChange.Kind.REMOVED
import org.junit.Assert.assertEquals
import org.junit.Test

class InventoryDiffTest {

    private fun app(pkg: String, firstInstall: Long) = InstalledApp(pkg, "Label $pkg", firstInstall, -1)

    @Test
    fun derivesInstallsAndRemovalsFromTwoSnapshots() {
        data class Case(
            val name: String,
            val previous: List<InstalledApp>?,
            val current: List<InstalledApp>,
            val knownRemovals: Set<String>,
            val expected: List<PackageChange>,
        )

        val now = 1_000L
        val backfillSince = 500L

        val cases = listOf(
            Case(
                "first run backfills installs from firstInstallTime",
                previous = null,
                current = listOf(app("old", 100), app("recent", 700)),
                knownRemovals = emptySet(),
                expected = listOf(PackageChange("recent", "Label recent", INSTALLED, 700, exact = true)),
            ),
            Case(
                "a new package is an install at its firstInstallTime",
                previous = listOf(app("a", 100)),
                current = listOf(app("a", 100), app("b", 900)),
                knownRemovals = emptySet(),
                expected = listOf(PackageChange("b", "Label b", INSTALLED, 900, exact = true)),
            ),
            Case(
                "a missing package is a removal at snapshot time, flagged approximate, with its last label",
                previous = listOf(app("a", 100), app("b", 200)),
                current = listOf(app("a", 100)),
                knownRemovals = emptySet(),
                expected = listOf(PackageChange("b", "Label b", REMOVED, now, exact = false)),
            ),
            Case(
                "a removal already caught by the broadcast is not logged twice",
                previous = listOf(app("a", 100), app("b", 200)),
                current = listOf(app("a", 100)),
                knownRemovals = setOf("b"),
                expected = emptyList(),
            ),
            Case(
                "a reinstall (firstInstallTime moved) is an install",
                previous = listOf(app("a", 100)),
                current = listOf(app("a", 800)),
                knownRemovals = emptySet(),
                expected = listOf(PackageChange("a", "Label a", INSTALLED, 800, exact = true)),
            ),
            Case(
                "no change gives nothing",
                previous = listOf(app("a", 100)),
                current = listOf(app("a", 100)),
                knownRemovals = emptySet(),
                expected = emptyList(),
            ),
        )

        for (case in cases) {
            val got = InventoryDiff.diff(case.previous, case.current, now, backfillSince, case.knownRemovals)
            assertEquals(case.name, case.expected, got)
        }
    }
}
