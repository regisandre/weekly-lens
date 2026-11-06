package app.weeklylens.bridge

/**
 * Packs usage events into parallel arrays plus one string table. A week holds tens of thousands
 * of events naming a few hundred packages and classes, so this ships each name once instead of
 * one object per event.
 */
class UsageColumnsBuilder(capacity: Int) {
    private val ts = LongArray(capacity)
    private val type = IntArray(capacity)
    private val pkg = IntArray(capacity)
    private val cls = IntArray(capacity)
    private val index = HashMap<String, Int>()
    private val strings = ArrayList<String>()
    private var size = 0

    fun add(ts: Long, pkg: String, cls: String, type: Int) {
        this.ts[size] = ts
        this.type[size] = type
        this.pkg[size] = intern(pkg)
        this.cls[size] = intern(cls)
        size++
    }

    fun build() = UsageColumns(
        ts = ts.copyOf(size),
        type = type.copyOf(size),
        pkg = pkg.copyOf(size),
        cls = cls.copyOf(size),
        strings = strings,
    )

    private fun intern(s: String): Int = index.getOrPut(s) { strings.add(s); strings.size - 1 }
}
