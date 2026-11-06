package app.weeklylens.collect

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import app.weeklylens.bridge.UsageColumns
import app.weeklylens.bridge.UsageColumnsBuilder

/**
 * The only place collected data lives: one SQLite file in the app's private storage.
 * Raw rows are kept so the aggregation rules can change without losing history;
 * [prune] drops anything older than the retention window.
 */
class ActivityDb private constructor(context: Context) :
    SQLiteOpenHelper(context, "activity.db", null, 1), NotificationStore {

    init {
        // Readers (the report) no longer block the listener and accessibility writers.
        setWriteAheadLoggingEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE usage_event(ts INTEGER NOT NULL, pkg TEXT NOT NULL, cls TEXT NOT NULL, " +
                "type INTEGER NOT NULL, UNIQUE(ts, pkg, cls, type))",
        )
        db.execSQL("CREATE INDEX usage_event_ts ON usage_event(ts)")
        db.execSQL(
            "CREATE TABLE notification(id INTEGER PRIMARY KEY, key TEXT NOT NULL, pkg TEXT NOT NULL, " +
                "posted_at INTEGER NOT NULL, removed_at INTEGER)",
        )
        db.execSQL("CREATE INDEX notification_active ON notification(key) WHERE removed_at IS NULL")
        db.execSQL("CREATE INDEX notification_posted ON notification(posted_at)")
        db.execSQL("CREATE TABLE media_segment(pkg TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL)")
        db.execSQL(
            "CREATE TABLE app_inventory(pkg TEXT PRIMARY KEY, label TEXT NOT NULL, " +
                "first_install INTEGER NOT NULL, category INTEGER NOT NULL)",
        )
        db.execSQL(
            "CREATE TABLE package_change(pkg TEXT NOT NULL, label TEXT NOT NULL, kind TEXT NOT NULL, " +
                "at INTEGER NOT NULL, exact INTEGER NOT NULL)",
        )
        db.execSQL("CREATE TABLE ad_impression(pkg TEXT NOT NULL, advertiser TEXT NOT NULL, seen_at INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE kv(k TEXT PRIMARY KEY, v INTEGER NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    // --- key/value state (cursors, first-run markers) ---

    fun getLong(key: String): Long? =
        readableDatabase.rawQuery("SELECT v FROM kv WHERE k = ?", arrayOf(key)).use {
            if (it.moveToFirst()) it.getLong(0) else null
        }

    fun putLong(key: String, value: Long) {
        writableDatabase.insertWithOnConflict(
            "kv", null,
            ContentValues().apply { put("k", key); put("v", value) },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun remove(key: String) {
        writableDatabase.delete("kv", "k = ?", arrayOf(key))
    }

    fun <T> inTransaction(block: () -> T): T {
        val db = writableDatabase
        db.beginTransaction()
        try {
            return block().also { db.setTransactionSuccessful() }
        } finally {
            db.endTransaction()
        }
    }

    // --- usage events ---

    fun insertUsageEvents(rows: List<UsageRow>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val st = db.compileStatement("INSERT OR IGNORE INTO usage_event(ts, pkg, cls, type) VALUES (?, ?, ?, ?)")
            for (r in rows) {
                st.bindLong(1, r.ts); st.bindString(2, r.pkg); st.bindString(3, r.cls); st.bindLong(4, r.type.toLong())
                st.executeInsert()
                st.clearBindings()
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Events of [types] in [from, to), oldest first; rowid breaks same-millisecond ties stably. */
    fun usageColumns(from: Long, to: Long, types: Set<Int>): UsageColumns {
        val typeList = types.sorted().joinToString(",") // ints from our own constants, safe to inline
        return readableDatabase.rawQuery(
            "SELECT ts, pkg, cls, type FROM usage_event WHERE ts >= ? AND ts < ? AND type IN ($typeList) ORDER BY ts, rowid",
            arrayOf(from.toString(), to.toString()),
        ).use { c ->
            val b = UsageColumnsBuilder(c.count)
            while (c.moveToNext()) b.add(c.getLong(0), c.getString(1), c.getString(2), c.getInt(3))
            b.build()
        }
    }

    // --- notifications (NotificationStore) ---

    override fun isActive(key: String): Boolean =
        readableDatabase.rawQuery(
            "SELECT 1 FROM notification WHERE key = ? AND removed_at IS NULL LIMIT 1", arrayOf(key),
        ).use { it.moveToFirst() }

    override fun insertArrival(key: String, pkg: String, postedAt: Long) {
        writableDatabase.insert(
            "notification", null,
            ContentValues().apply { put("key", key); put("pkg", pkg); put("posted_at", postedAt) },
        )
    }

    override fun markRemoved(key: String, removedAt: Long) {
        writableDatabase.update(
            "notification", ContentValues().apply { put("removed_at", removedAt) },
            "key = ? AND removed_at IS NULL", arrayOf(key),
        )
    }

    override fun activeKeys(): Set<String> =
        readableDatabase.rawQuery("SELECT key FROM notification WHERE removed_at IS NULL", null).use { c ->
            buildSet { while (c.moveToNext()) add(c.getString(0)) }
        }

    fun notifications(from: Long, to: Long): List<Pair<String, Long>> =
        readableDatabase.rawQuery(
            "SELECT pkg, posted_at FROM notification WHERE posted_at >= ? AND posted_at < ? ORDER BY posted_at",
            arrayOf(from.toString(), to.toString()),
        ).use { c -> buildList { while (c.moveToNext()) add(c.getString(0) to c.getLong(1)) } }

    // --- media ---

    fun insertMediaSegment(pkg: String, start: Long, end: Long) {
        writableDatabase.insert(
            "media_segment", null,
            ContentValues().apply { put("pkg", pkg); put("started_at", start); put("ended_at", end) },
        )
    }

    fun mediaSegments(from: Long, to: Long): List<Triple<String, Long, Long>> =
        readableDatabase.rawQuery(
            "SELECT pkg, started_at, ended_at FROM media_segment WHERE ended_at > ? AND started_at < ? ORDER BY started_at",
            arrayOf(from.toString(), to.toString()),
        ).use { c -> buildList { while (c.moveToNext()) add(Triple(c.getString(0), c.getLong(1), c.getLong(2))) } }

    // --- inventory and package changes ---

    fun inventory(): List<InstalledApp> =
        readableDatabase.rawQuery("SELECT pkg, label, first_install, category FROM app_inventory", null).use { c ->
            buildList { while (c.moveToNext()) add(InstalledApp(c.getString(0), c.getString(1), c.getLong(2), c.getInt(3))) }
        }

    fun replaceInventory(apps: List<InstalledApp>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("app_inventory", null, null)
            for (a in apps) {
                db.insert(
                    "app_inventory", null,
                    ContentValues().apply {
                        put("pkg", a.pkg); put("label", a.label); put("first_install", a.firstInstall); put("category", a.category)
                    },
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun insertPackageChanges(changes: List<PackageChange>) = inTransaction {
        val st = writableDatabase.compileStatement("INSERT INTO package_change(pkg, label, kind, at, exact) VALUES (?, ?, ?, ?, ?)")
        for (ch in changes) {
            st.bindString(1, ch.pkg); st.bindString(2, ch.label); st.bindString(3, ch.kind.name)
            st.bindLong(4, ch.at); st.bindLong(5, if (ch.exact) 1 else 0)
            st.executeInsert()
            st.clearBindings()
        }
    }

    fun inventoryLabel(pkg: String): String? =
        readableDatabase.rawQuery("SELECT label FROM app_inventory WHERE pkg = ?", arrayOf(pkg)).use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    fun removedSince(since: Long): Set<String> =
        readableDatabase.rawQuery(
            "SELECT pkg FROM package_change WHERE kind = 'REMOVED' AND at >= ?", arrayOf(since.toString()),
        ).use { c -> buildSet { while (c.moveToNext()) add(c.getString(0)) } }

    fun packageChanges(from: Long, to: Long): List<PackageChange> =
        readableDatabase.rawQuery(
            "SELECT pkg, label, kind, at, exact FROM package_change WHERE at >= ? AND at < ? ORDER BY at",
            arrayOf(from.toString(), to.toString()),
        ).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(PackageChange(c.getString(0), c.getString(1), PackageChange.Kind.valueOf(c.getString(2)), c.getLong(3), c.getInt(4) == 1))
                }
            }
        }

    // --- ads ---

    fun insertAdImpression(pkg: String, advertiser: String, seenAt: Long) {
        writableDatabase.insert(
            "ad_impression", null,
            ContentValues().apply { put("pkg", pkg); put("advertiser", advertiser); put("seen_at", seenAt) },
        )
    }

    fun adImpressions(from: Long, to: Long): List<Triple<String, String, Long>> =
        readableDatabase.rawQuery(
            "SELECT pkg, advertiser, seen_at FROM ad_impression WHERE seen_at >= ? AND seen_at < ? ORDER BY seen_at",
            arrayOf(from.toString(), to.toString()),
        ).use { c -> buildList { while (c.moveToNext()) add(Triple(c.getString(0), c.getString(1), c.getLong(2))) } }

    /** Deletes raw rows older than [before]. Inventory and kv state are kept. */
    fun prune(before: Long) {
        val arg = arrayOf(before.toString())
        writableDatabase.delete("usage_event", "ts < ?", arg)
        writableDatabase.delete("notification", "posted_at < ? AND removed_at IS NOT NULL", arg)
        writableDatabase.delete("media_segment", "ended_at < ?", arg)
        writableDatabase.delete("package_change", "at < ?", arg)
        writableDatabase.delete("ad_impression", "seen_at < ?", arg)
    }

    /**
     * Deletes every collected row. The inventory stays: it is the current list of apps, not
     * history, and without it the next snapshot would report every app as newly installed.
     */
    fun wipeHistory() = inTransaction {
        for (t in listOf("usage_event", "notification", "media_segment", "package_change", "ad_impression")) {
            writableDatabase.delete(t, null, null)
        }
    }

    companion object {
        @Volatile private var instance: ActivityDb? = null

        fun get(context: Context): ActivityDb =
            instance ?: synchronized(this) {
                instance ?: ActivityDb(context.applicationContext).also { instance = it }
            }
    }
}

data class UsageRow(val ts: Long, val pkg: String, val cls: String, val type: Int)
