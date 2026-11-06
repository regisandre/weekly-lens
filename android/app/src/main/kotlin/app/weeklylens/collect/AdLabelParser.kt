package app.weeklylens.collect

import java.util.Locale

/**
 * Finds ads on screen from the texts of the accessibility tree, in traversal order.
 *
 * Feeds label ads with a short word ("Sponsored", "Sponsorisé", "Gesponsord", ...) placed next to
 * the advertiser's name, so the rule is: a node whose text *is* such a label, and the nearest
 * plausible name just before it. Only the name leaves this function; no other screen text is kept.
 */
object AdLabelParser {

    private val LABELS = setOf(
        "sponsored", "promoted", "ad", "advertisement",
        "sponsorisé", "sponsorisée", "publicité", "annonce",
        "gesponsord", "advertentie", "gesponsert", "anzeige", "werbung",
    )

    private val CALLS_TO_ACTION = setOf(
        "shop now", "learn more", "install", "install now", "sign up", "visit site", "download",
        "book now", "watch more", "get offer", "like", "share", "comment", "follow", "more", "send",
        "en savoir plus", "acheter", "installer", "s'inscrire", "j'aime", "partager", "commenter", "suivre",
        "meer info", "nu kopen", "installeren", "vind ik leuk", "delen", "volgen",
    )

    /** Same list as packageNames in res/xml/ad_observer.xml, enforced again here. */
    val OBSERVED_PACKAGES = setOf(
        "com.instagram.android", "com.facebook.katana", "com.google.android.youtube",
        "com.linkedin.android", "com.twitter.android", "com.zhiliaoapp.musically",
    )

    /**
     * packageNames only filters which apps send events; the active window can already belong to
     * another app when a late event arrives. Scan only when both are the same observed app.
     */
    fun shouldScan(eventPackage: String?, screenPackage: String?): Boolean =
        eventPackage != null && eventPackage == screenPackage && eventPackage in OBSERVED_PACKAGES

    private const val MAX_NAME_LENGTH = 80
    private const val LOOK_BACK = 3

    fun advertisers(texts: List<String?>): List<String> {
        val nodes = texts.mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }
        val found = mutableListOf<String>()
        for ((i, text) in nodes.withIndex()) {
            if (!isLabel(text)) continue
            val window = nodes.subList(maxOf(0, i - LOOK_BACK), i).asReversed()
            window.firstOrNull { isPlausibleName(it) }?.let { found += it }
        }
        return found
    }

    private fun isLabel(text: String): Boolean {
        val head = text.split('·', '•', '|').first().trim().lowercase(Locale.ROOT)
        return head in LABELS
    }

    private fun isPlausibleName(text: String): Boolean {
        if (text.length > MAX_NAME_LENGTH) return false
        if (isLabel(text)) return false
        val lower = text.lowercase(Locale.ROOT)
        if (lower in CALLS_TO_ACTION) return false
        return !lower.contains("http") && !lower.contains("www.")
    }
}

/**
 * An ad stays on screen across many scans. It counts once, then again only after it has been
 * out of sight for [windowMs]: every sighting moves the window, so one long look is one impression.
 */
class AdImpressionDeduper(private val windowMs: Long) {
    private val lastSeen = mutableMapOf<String, Long>()

    @Synchronized
    fun isNew(pkg: String, advertiser: String, at: Long): Boolean {
        val key = pkg + "\u0000" + advertiser.lowercase(Locale.ROOT)
        val previous = lastSeen[key]
        lastSeen[key] = at
        if (lastSeen.size > 500) lastSeen.entries.removeAll { at - it.value > windowMs }
        return previous == null || at - previous >= windowMs
    }
}
