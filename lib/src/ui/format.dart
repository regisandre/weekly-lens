const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 1) return d.inSeconds > 0 ? '<1 min' : '0 min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "2 - 8 Nov" or "27 Oct - 2 Nov".
String formatWeekRange(DateTime start, DateTime endExclusive) {
  final last = DateTime(endExclusive.year, endExclusive.month, endExclusive.day - 1);
  if (start.month == last.month) return '${start.day} - ${last.day} ${_months[last.month - 1]}';
  return '${start.day} ${_months[start.month - 1]} - ${last.day} ${_months[last.month - 1]}';
}

String formatDayTime(DateTime t) => '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, ${formatClock(t)}';

String formatClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String formatDelta(Duration now, Duration before) {
  if (before == Duration.zero) return '';
  final pct = ((now.inSeconds - before.inSeconds) / before.inSeconds * 100).round();
  if (pct == 0) return 'Same as the week before';
  return pct > 0 ? '$pct% more than the week before' : '${-pct}% less than the week before';
}
