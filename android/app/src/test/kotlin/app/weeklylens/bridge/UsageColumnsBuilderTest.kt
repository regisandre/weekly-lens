package app.weeklylens.bridge

import org.junit.Assert.assertEquals
import org.junit.Test

class UsageColumnsBuilderTest {

    @Test
    fun packsEventsIntoColumnsWithOneStringTable() {
        data class Row(val ts: Long, val pkg: String, val cls: String, val type: Int)
        data class Case(val name: String, val rows: List<Row>, val strings: List<String>)

        val cases = listOf(
            Case(
                "repeated package and class names are stored once",
                listOf(Row(10, "chat", "List", 1), Row(20, "chat", "List", 2), Row(30, "maps", "", 1)),
                listOf("chat", "List", "maps", ""),
            ),
            Case("no events", emptyList(), emptyList()),
        )

        for (c in cases) {
            val b = UsageColumnsBuilder(c.rows.size)
            c.rows.forEach { b.add(it.ts, it.pkg, it.cls, it.type) }
            val cols = b.build()

            assertEquals(c.name, c.strings, cols.strings)
            val rebuilt = cols.ts.indices.map { i ->
                Row(cols.ts[i], cols.strings[cols.pkg[i]], cols.strings[cols.cls[i]], cols.type[i])
            }
            assertEquals("${c.name}: round trip", c.rows, rebuilt)
        }
    }
}
