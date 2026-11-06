package app.weeklylens.collect

import org.junit.Assert.assertEquals
import org.junit.Test

class AdLabelParserTest {

    @Test
    fun findsTheAdvertiserNextToASponsoredLabel() {
        data class Case(val name: String, val texts: List<String?>, val expected: List<String>)

        val cases = listOf(
            Case(
                "feed post: advertiser name right above 'Sponsored'",
                listOf("Home", "Stories", "Acme Shoes", "Sponsored", "Shop now", "Like"),
                listOf("Acme Shoes"),
            ),
            Case(
                "French and Dutch labels, case and spaces ignored",
                listOf("Brasserie Lupulus", " sponsorisé ", "Bol", "Gesponsord"),
                listOf("Brasserie Lupulus", "Bol"),
            ),
            Case(
                "a label glued to a dot separator (YouTube style)",
                listOf("Visit site", "Nordic VPN", "Sponsored · nordvpn.com"),
                listOf("Nordic VPN"),
            ),
            Case(
                "nulls and blanks between name and label are skipped",
                listOf("Acme", null, "  ", "Sponsored"),
                listOf("Acme"),
            ),
            Case(
                "a call to action is not an advertiser",
                listOf("Learn more", "Sponsored"),
                emptyList(),
            ),
            Case(
                "a label with nothing before it gives nothing",
                listOf("Sponsored", "Acme"),
                emptyList(),
            ),
            Case(
                "the word inside a sentence is not a label",
                listOf("Alice", "This post is not sponsored at all"),
                emptyList(),
            ),
            Case(
                "long texts (a caption) are never taken as a name",
                listOf("A".repeat(81), "Sponsored"),
                emptyList(),
            ),
            Case(
                "a name more than three nodes above the label is too far to trust",
                listOf("Acme", "Like", "Share", "Learn more", "Sponsored"),
                emptyList(),
            ),
        )

        for (case in cases) {
            assertEquals(case.name, case.expected, AdLabelParser.advertisers(case.texts))
        }
    }

    @Test
    fun onlyScansAScreenThatBelongsToAnObservedFeedApp() {
        data class Case(val name: String, val eventPkg: String?, val rootPkg: String?, val expected: Boolean)

        val cases = listOf(
            Case("event and screen from Instagram", "com.instagram.android", "com.instagram.android", true),
            Case("late Instagram event while a banking app is on screen", "com.instagram.android", "com.bank.app", false),
            Case("an app outside the allowlist, even if it sent the event", "com.bank.app", "com.bank.app", false),
            Case("unknown screen owner", "com.instagram.android", null, false),
            Case("unknown event source", null, "com.instagram.android", false),
        )

        for (case in cases) {
            assertEquals(case.name, case.expected, AdLabelParser.shouldScan(case.eventPkg, case.rootPkg))
        }
    }

    @Test
    fun countsAnAdOnScreenOnceWhileItStaysVisible() {
        data class Seen(val pkg: String, val advertiser: String, val at: Long)
        data class Case(val name: String, val seen: List<Seen>, val expectedImpressions: Int)

        val minute = 60_000L
        val cases = listOf(
            Case("scroll events on the same ad count once", listOf(Seen("ig", "Acme", 0), Seen("ig", "Acme", minute)), 1),
            Case("the same ad 10 minutes later is a new impression", listOf(Seen("ig", "Acme", 0), Seen("ig", "Acme", 10 * minute)), 2),
            Case("same advertiser in two apps is two impressions", listOf(Seen("ig", "Acme", 0), Seen("fb", "Acme", 0)), 2),
            Case("advertiser names are compared without case", listOf(Seen("ig", "Acme", 0), Seen("ig", "ACME", 1)), 1),
        )

        for (case in cases) {
            val deduper = AdImpressionDeduper(windowMs = 5 * minute)
            val count = case.seen.count { deduper.isNew(it.pkg, it.advertiser, it.at) }
            assertEquals(case.name, case.expectedImpressions, count)
        }
    }
}
