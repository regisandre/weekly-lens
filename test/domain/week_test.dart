import 'package:flutter_test/flutter_test.dart';
import 'package:weekly_lens/src/domain/week.dart';

void main() {
  test('a week runs from local Monday midnight to the next, whatever the clock change', () {
    final cases = <({String name, DateTime at, DateTime start, DateTime end})>[
      (name: 'mid-week', at: DateTime(2026, 11, 5, 14), start: DateTime(2026, 11, 2), end: DateTime(2026, 11, 9)),
      (
        name: 'Monday 00:00 belongs to the week it starts',
        at: DateTime(2026, 11, 2),
        start: DateTime(2026, 11, 2),
        end: DateTime(2026, 11, 9),
      ),
      (
        name: 'Sunday 23:59 belongs to the week it ends',
        at: DateTime(2026, 11, 8, 23, 59),
        start: DateTime(2026, 11, 2),
        end: DateTime(2026, 11, 9),
      ),
      (
        name: 'week with the autumn clock change (169 h in Brussels)',
        at: DateTime(2026, 10, 25, 12),
        start: DateTime(2026, 10, 19),
        end: DateTime(2026, 10, 26),
      ),
      (
        name: 'week with the spring clock change (167 h in Brussels)',
        at: DateTime(2026, 3, 29, 12),
        start: DateTime(2026, 3, 23),
        end: DateTime(2026, 3, 30),
      ),
      (
        name: 'across a year boundary',
        at: DateTime(2027, 1, 1),
        start: DateTime(2026, 12, 28),
        end: DateTime(2027, 1, 4),
      ),
    ];

    for (final c in cases) {
      final week = Week.containing(c.at);
      expect(week.start, c.start, reason: '${c.name}: start');
      expect(week.end, c.end, reason: '${c.name}: end');
      expect(week.dayStarts, hasLength(8), reason: '${c.name}: 7 days need 8 boundaries');
      expect(
        week.dayStarts.every((d) => d.hour == 0 && d.minute == 0),
        isTrue,
        reason: '${c.name}: every day starts at local midnight',
      );
      expect(week.previous.end, week.start, reason: '${c.name}: previous week ends where this one starts');
      expect(week.next.start, week.end, reason: '${c.name}: next week starts where this one ends');
    }
  });
}
