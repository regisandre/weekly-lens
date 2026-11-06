package app.weeklylens.collect

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Opt-in, off by default. Reads the accessibility tree of a short allowlist of feed apps
 * (declared in res/xml/ad_observer.xml, so the system never sends us events from other apps),
 * keeps only the advertiser names found by [AdLabelParser], and drops everything else in memory.
 */
class AdObserverService : AccessibilityService() {

    private val deduper = AdImpressionDeduper(TimeUnit.MINUTES.toMillis(5))
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var pendingPackage: String? = null
    private val scan = Runnable { scanNow() }

    override fun onServiceConnected() {
        io.execute {
            val db = ActivityDb.get(this)
            if (db.getLong(Collector.KEY_ADS_SINCE) == null) db.putLong(Collector.KEY_ADS_SINCE, System.currentTimeMillis())
        }
    }

    /**
     * Scroll and content events arrive in bursts. The first one of a burst schedules one scan
     * [SCAN_DELAY_MS] later; that scan reads the screen as it is then, so the screen the user
     * stops on is always read.
     */
    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg !in AdLabelParser.OBSERVED_PACKAGES) return
        val wasPending = pendingPackage != null
        pendingPackage = pkg
        if (!wasPending) main.postDelayed(scan, SCAN_DELAY_MS)
    }

    private fun scanNow() {
        val eventPackage = pendingPackage
        pendingPackage = null
        val root = rootInActiveWindow ?: return
        val now = System.currentTimeMillis()
        try {
            val pkg = root.packageName?.toString()
            if (pkg == null || !AdLabelParser.shouldScan(eventPackage, pkg)) return
            val texts = ArrayList<String?>(256)
            collect(root, texts, 0, intArrayOf(0))
            val found = AdLabelParser.advertisers(texts).distinct().filter { deduper.isNew(pkg, it, now) }
            if (found.isEmpty()) return
            io.execute {
                val db = ActivityDb.get(this)
                for (advertiser in found) db.insertAdImpression(pkg, advertiser, now)
            }
        } finally {
            recycle(root)
        }
    }

    /** Depth-first, in screen order. [visited] caps the binder calls, not only the texts kept. */
    private fun collect(node: AccessibilityNodeInfo, out: MutableList<String?>, depth: Int, visited: IntArray) {
        if (depth > MAX_DEPTH) return
        if (node.isVisibleToUser) out += (node.text ?: node.contentDescription)?.toString()
        for (i in 0 until node.childCount) {
            if (++visited[0] > MAX_VISITED) return
            val child = node.getChild(i) ?: continue
            try {
                collect(child, out, depth + 1, visited)
            } finally {
                recycle(child)
            }
        }
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        main.removeCallbacks(scan)
        io.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val SCAN_DELAY_MS = 750L
        const val MAX_DEPTH = 40
        const val MAX_VISITED = 2_000

        /** Nodes come from a pool below API 33 and must go back; from 33 on, recycle() does nothing. */
        @Suppress("DEPRECATION")
        fun recycle(node: AccessibilityNodeInfo) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) node.recycle()
        }
    }
}
