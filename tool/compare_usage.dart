// Validation helper: runs the app's session rules on an exported usage_event table (CSV:
// ts,pkg,cls,type) and prints foreground time per package for a window, to compare with
// `adb shell dumpsys usagestats` or Digital Wellbeing for the same window.
//
// dart run tool/compare_usage.dart usage.csv "2026-11-06 04:16" "2026-11-06 17:39"
import 'dart:io';
import 'dart:math';

import 'package:weekly_lens/src/domain/models.dart';
import 'package:weekly_lens/src/domain/sessions.dart';

void main(List<String> args) {
  final from = DateTime.parse(args[1]).millisecondsSinceEpoch;
  final to = DateTime.parse(args[2]).millisecondsSinceEpoch;
  final events = [
    for (final line in File(args[0]).readAsLinesSync())
      if (line.trim().isNotEmpty)
        () {
          final f = line.split(',');
          return UsageEvent(ts: int.parse(f[0]), pkg: f[1], cls: f[2], type: int.parse(f[3]));
        }(),
  ];
  final time = <String, int>{};
  final opens = <String, int>{};
  for (final s in appSessions(events, until: to)) {
    final int d = min(s.end, to) - max(s.start, from);
    if (d > 0) time.update(s.pkg, (v) => v + d, ifAbsent: () => d);
    if (s.start >= from && s.start < to) opens.update(s.pkg, (v) => v + 1, ifAbsent: () => 1);
  }
  final rows = time.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in rows.take(int.tryParse(args.elementAtOrNull(3) ?? '') ?? 15)) {
    final m = e.value ~/ 60000;
    final s = (e.value % 60000) ~/ 1000;
    stdout.writeln('${e.key}\t$m:${s.toString().padLeft(2, '0')}\topens=${opens[e.key] ?? 0}');
  }
}
