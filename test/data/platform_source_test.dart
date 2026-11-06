import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:weekly_lens/src/data/activity_source.dart';
import 'package:weekly_lens/src/platform/activity_api.g.dart';

RawRange range(UsageColumns usage) => RawRange(
  usage: usage,
  notifications: [],
  media: [],
  packageChanges: [],
  ads: [],
  apps: [
    RawApp(pkg: 'chat', label: 'Chat', category: 4),
    RawApp(pkg: 'odd', label: 'Odd', category: 99),
  ],
  homePackages: ['home'],
  earliestUsageEvent: 5,
  notificationsSince: 6,
  adsSince: 0,
);

void main() {
  test('usage events arrive as columns and are rebuilt in order with their strings', () {
    final cases = <({String name, UsageColumns columns, List<(int, String, String, int)> expected})>[
      (
        name: 'two events sharing the string table',
        columns: UsageColumns(
          ts: Int64List.fromList([10, 20]),
          type: Int32List.fromList([1, 2]),
          pkg: Int32List.fromList([0, 0]),
          cls: Int32List.fromList([1, 2]),
          strings: ['chat', 'List', 'Thread'],
        ),
        expected: [(10, 'chat', 'List', 1), (20, 'chat', 'Thread', 2)],
      ),
      (
        name: 'no events',
        columns: UsageColumns(ts: Int64List(0), type: Int32List(0), pkg: Int32List(0), cls: Int32List(0), strings: []),
        expected: [],
      ),
    ];

    for (final c in cases) {
      final data = PlatformActivitySource.fromRaw(range(c.columns));
      expect(data.usage.map((e) => (e.ts, e.pkg, e.cls, e.type)).toList(), c.expected, reason: c.name);
      expect(data.usageSince, 5, reason: '${c.name}: usage history start');
      expect(data.labelOf('chat'), 'Chat', reason: '${c.name}: app labels');
    }
  });
}
