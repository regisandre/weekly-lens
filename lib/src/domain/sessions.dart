import 'models.dart';

class AppSession {
  const AppSession(this.pkg, this.start, this.end);
  final String pkg;
  final int start;
  final int end;
}

class _Raw {
  _Raw(this.pkg, this.start, this.end, {required this.endedByScreen});
  final String pkg;
  final int start;
  int end;
  bool endedByScreen;
}

/// Pairs usage events into foreground sessions, one per "open" of an app.
///
/// Rules (each one is a case in sessions_test.dart):
/// - an app is in the foreground while at least one of its activities is resumed, so two
///   overlapping activities of one app never count double;
/// - screen off and device shutdown end everything that is open;
/// - anything resumed between shutdown and startup has no known end and is dropped;
/// - two sessions of the same app separated by less than [mergeGapMs], with no other app and
///   no screen off in between, are one open (moving between screens of an app);
/// - what is still open at [until] (now) is counted up to [until].
List<AppSession> appSessions(List<UsageEvent> events, {required int until, int mergeGapMs = 2000}) {
  final ordered = [for (var i = 0; i < events.length; i++) (i, events[i])]
    ..sort((a, b) => a.$2.ts != b.$2.ts ? a.$2.ts.compareTo(b.$2.ts) : a.$1.compareTo(b.$1));

  final openActivities = <String, Map<String, int>>{};
  final openedAt = <String, int>{};
  final raw = <_Raw>[];
  var afterShutdown = false;

  void closePackage(String pkg, int ts, {required bool byScreen}) {
    final start = openedAt.remove(pkg);
    openActivities.remove(pkg);
    if (start != null && ts > start) raw.add(_Raw(pkg, start, ts, endedByScreen: byScreen));
  }

  void closeAll(int ts, {required bool byScreen}) {
    for (final pkg in openedAt.keys.toList()) {
      closePackage(pkg, ts, byScreen: byScreen);
    }
  }

  for (final (_, e) in ordered) {
    switch (e.type) {
      case UsageEventType.resumed:
        if (afterShutdown) continue;
        final acts = openActivities.putIfAbsent(e.pkg, () => {});
        if (acts.isEmpty) openedAt[e.pkg] = e.ts;
        acts.putIfAbsent(e.cls, () => e.ts);
      case UsageEventType.paused || UsageEventType.stopped:
        final acts = openActivities[e.pkg];
        if (acts == null || acts.remove(e.cls) == null) continue;
        if (acts.isEmpty) closePackage(e.pkg, e.ts, byScreen: false);
      case UsageEventType.screenOff:
        closeAll(e.ts, byScreen: true);
      case UsageEventType.shutdown:
        closeAll(e.ts, byScreen: true);
        afterShutdown = true;
      case UsageEventType.startup:
        openActivities.clear();
        openedAt.clear();
        afterShutdown = false;
    }
  }
  closeAll(until, byScreen: false);

  raw.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Raw>[];
  for (final s in raw) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && last.pkg == s.pkg && !last.endedByScreen && s.start - last.end <= mergeGapMs) {
      if (s.end > last.end) {
        last.end = s.end;
        last.endedByScreen = s.endedByScreen;
      }
    } else {
      merged.add(s);
    }
  }
  return [for (final s in merged) AppSession(s.pkg, s.start, s.end)];
}
