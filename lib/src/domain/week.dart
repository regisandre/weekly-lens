/// A calendar week, Monday 00:00 to the next Monday 00:00, in the phone's local time.
///
/// Built from calendar dates, never from `start + 7 days`: a week with a clock change
/// lasts 167 or 169 hours, and adding a fixed Duration would land at 23:00 or 01:00.
class Week {
  Week._(this.start)
    : end = DateTime(start.year, start.month, start.day + 7),
      dayStarts = List.unmodifiable([for (var i = 0; i <= 7; i++) DateTime(start.year, start.month, start.day + i)]);

  factory Week.containing(DateTime t) {
    final local = t.toLocal();
    return Week._(DateTime(local.year, local.month, local.day - (local.weekday - DateTime.monday)));
  }

  final DateTime start;
  final DateTime end;

  /// The 8 local midnights that bound the 7 days of the week.
  final List<DateTime> dayStarts;

  Week get previous => Week._(DateTime(start.year, start.month, start.day - 7));
  Week get next => Week._(end);

  int get startMs => start.millisecondsSinceEpoch;
  int get endMs => end.millisecondsSinceEpoch;

  bool contains(int ms) => ms >= startMs && ms < endMs;

  /// Index 0..6 of the day containing [ms], or -1 outside the week.
  int dayIndexOf(int ms) {
    for (var i = 0; i < 7; i++) {
      if (ms >= dayStarts[i].millisecondsSinceEpoch && ms < dayStarts[i + 1].millisecondsSinceEpoch) return i;
    }
    return -1;
  }

  @override
  bool operator ==(Object other) => other is Week && other.start == start;

  @override
  int get hashCode => start.hashCode;
}
