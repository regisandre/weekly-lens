import 'dart:math' as math;

import 'models.dart';
import 'sessions.dart';
import 'week.dart';

const _dayStartsAtHour = 4;

/// Packages whose foreground time is not "time in an app".
const _notApps = {ownPackage, 'android', 'com.android.systemui'};

/// Apps rarely declare a category, so the best-known players are listed by hand.
const _knownVideo = {
  'com.google.android.youtube',
  'com.netflix.mediaclient',
  'com.disney.disneyplus',
  'com.amazon.avod.thirdpartyclient',
  'tv.twitch.android.app',
  'com.zhiliaoapp.musically',
  'com.google.android.apps.youtube.kids',
};
const _knownAudio = {
  'com.spotify.music',
  'deezer.android.app',
  'com.google.android.apps.youtube.music',
  'com.apple.android.music',
  'com.soundcloud.android',
  'au.com.shiftyjelly.pocketcasts',
};

class AppUsage {
  const AppUsage({required this.pkg, required this.label, required this.time, required this.opens});
  final String pkg;
  final String label;
  final Duration time;
  final int opens;
}

class AppCount {
  const AppCount({required this.pkg, required this.label, required this.count});
  final String pkg;
  final String label;
  final int count;
}

class AdvertiserCount {
  const AdvertiserCount({required this.name, required this.count, required this.appLabels});
  final String name;
  final int count;
  final List<String> appLabels;
}

/// From when a metric is measured within the week, so a partial week never looks complete.
class Coverage {
  const Coverage({required this.enabled, required this.from, required this.complete});
  final bool enabled;

  /// Start of measurement inside the week, null when nothing of the week is measured.
  final DateTime? from;
  final bool complete;

  factory Coverage.of(int since, Week week) {
    if (since <= 0) return const Coverage(enabled: false, from: null, complete: false);
    if (since >= week.endMs) return const Coverage(enabled: true, from: null, complete: false);
    return Coverage(
      enabled: true,
      from: DateTime.fromMillisecondsSinceEpoch(math.max(since, week.startMs)),
      complete: since <= week.startMs,
    );
  }
}

class WeeklyReport {
  const WeeklyReport({
    required this.week,
    required this.today,
    required this.screenTime,
    required this.screenTimePerDay,
    required this.previousScreenTime,
    required this.apps,
    required this.unlocks,
    required this.unlocksPerDay,
    required this.firstUnlockPerDay,
    required this.notifications,
    required this.notificationsByApp,
    required this.installed,
    required this.removed,
    required this.videoTime,
    required this.audioTime,
    required this.otherMediaTime,
    required this.adImpressions,
    required this.topAdvertisers,
    required this.usageCoverage,
    required this.notificationCoverage,
    required this.adCoverage,
  });

  final Week week;

  /// Index of the current day while the week is still running, null once it is over.
  final int? today;
  bool get inProgress => today != null;
  final Duration screenTime;
  final List<Duration> screenTimePerDay;

  /// Null when the previous week was not fully measured: no misleading comparison.
  final Duration? previousScreenTime;
  final List<AppUsage> apps;
  final int unlocks;
  final List<int> unlocksPerDay;

  /// First unlock at or after 04:00 each day.
  final List<DateTime?> firstUnlockPerDay;
  final int notifications;
  final List<AppCount> notificationsByApp;
  final List<PackageChange> installed;
  final List<PackageChange> removed;
  final Duration videoTime;
  final Duration audioTime;
  final Duration otherMediaTime;
  final int adImpressions;
  final List<AdvertiserCount> topAdvertisers;
  final Coverage usageCoverage;
  final Coverage notificationCoverage;
  final Coverage adCoverage;

  int get opens => apps.fold(0, (sum, a) => sum + a.opens);
}

WeeklyReport buildReport(ActivityData data, Week week, {required DateTime now}) {
  final nowMs = now.millisecondsSinceEpoch;
  final excluded = {..._notApps, ...data.homePackages};
  final sessions = appSessions(data.usage, until: nowMs).where((s) => !excluded.contains(s.pkg)).toList();
  final spans = [for (final s in sessions) (s.start, s.end)];

  // Screen time: union over apps (split screen is not double time), per local day.
  final perDay = [
    for (var d = 0; d < 7; d++)
      _unionLength(spans, week.dayStarts[d].millisecondsSinceEpoch, week.dayStarts[d + 1].millisecondsSinceEpoch),
  ];

  // Per app: time clipped to the week, opens counted in the week they started.
  final timeByApp = <String, int>{};
  final opensByApp = <String, int>{};
  for (final s in sessions) {
    final clipped = _overlap(s.start, s.end, week.startMs, week.endMs);
    if (clipped > 0) timeByApp.update(s.pkg, (v) => v + clipped, ifAbsent: () => clipped);
    if (week.contains(s.start)) opensByApp.update(s.pkg, (v) => v + 1, ifAbsent: () => 1);
  }
  final apps = [
    for (final pkg in {...timeByApp.keys, ...opensByApp.keys})
      AppUsage(
        pkg: pkg,
        label: data.labelOf(pkg),
        time: Duration(milliseconds: timeByApp[pkg] ?? 0),
        opens: opensByApp[pkg] ?? 0,
      ),
  ]..sort((a, b) => b.time != a.time ? b.time.compareTo(a.time) : a.label.compareTo(b.label));

  // Unlocks.
  final unlocksPerDay = List.filled(7, 0);
  final firstUnlock = List<DateTime?>.filled(7, null);
  for (final e in data.usage) {
    if (e.type != UsageEventType.keyguardHidden) continue;
    final d = week.dayIndexOf(e.ts);
    if (d < 0) continue;
    unlocksPerDay[d]++;
    final t = DateTime.fromMillisecondsSinceEpoch(e.ts);
    // Unlocks before 04:00 belong to the night before, not to the morning's first pickup.
    if (t.hour < _dayStartsAtHour) continue;
    if (firstUnlock[d] == null || t.isBefore(firstUnlock[d]!)) firstUnlock[d] = t;
  }

  // Notifications.
  final notifByApp = <String, int>{};
  for (final n in data.notifications) {
    if (week.contains(n.postedAt)) notifByApp.update(n.pkg, (v) => v + 1, ifAbsent: () => 1);
  }
  final notificationsByApp = [
    for (final MapEntry(:key, :value) in notifByApp.entries) AppCount(pkg: key, label: data.labelOf(key), count: value),
  ]..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.label.compareTo(b.label));

  // Installs and removals.
  final changes = data.packageChanges.where((c) => week.contains(c.at)).toList()..sort((a, b) => a.at.compareTo(b.at));

  // Media, split by the kind of app playing it.
  final mediaSpans = <_MediaKind, List<(int, int)>>{};
  for (final m in data.media) {
    mediaSpans.putIfAbsent(_kindOf(m.pkg, data), () => []).add((m.start, m.end));
  }
  Duration media(_MediaKind k) => _unionLength(mediaSpans[k] ?? const [], week.startMs, week.endMs);

  // Ads, merged by advertiser name without case.
  final adGroups = <String, ({String name, int count, Set<String> apps})>{};
  var adCount = 0;
  for (final a in data.ads) {
    if (!week.contains(a.seenAt)) continue;
    adCount++;
    final key = a.advertiser.toLowerCase();
    final g = adGroups[key];
    adGroups[key] = (
      name: g?.name ?? a.advertiser,
      count: (g?.count ?? 0) + 1,
      apps: {...?g?.apps, data.labelOf(a.pkg)},
    );
  }
  final topAdvertisers = [
    for (final g in adGroups.values) AdvertiserCount(name: g.name, count: g.count, appLabels: g.apps.toList()..sort()),
  ]..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.compareTo(b.name));

  final previous = week.previous;
  final previousScreenTime = data.usageSince > 0 && data.usageSince <= previous.startMs
      ? _unionLength(spans, previous.startMs, previous.endMs)
      : null;

  return WeeklyReport(
    week: week,
    today: nowMs < week.endMs ? week.dayIndexOf(nowMs) : null,
    screenTime: perDay.fold(Duration.zero, (a, b) => a + b),
    screenTimePerDay: perDay,
    previousScreenTime: previousScreenTime,
    apps: apps,
    unlocks: unlocksPerDay.fold(0, (a, b) => a + b),
    unlocksPerDay: unlocksPerDay,
    firstUnlockPerDay: firstUnlock,
    notifications: notificationsByApp.fold(0, (a, b) => a + b.count),
    notificationsByApp: notificationsByApp,
    installed: changes.where((c) => c.installed).toList(),
    removed: changes.where((c) => !c.installed).toList(),
    videoTime: media(_MediaKind.video),
    audioTime: media(_MediaKind.audio),
    otherMediaTime: media(_MediaKind.other),
    adImpressions: adCount,
    topAdvertisers: topAdvertisers,
    usageCoverage: Coverage.of(data.usageSince, week),
    notificationCoverage: Coverage.of(data.notificationsSince, week),
    adCoverage: Coverage.of(data.adsSince, week),
  );
}

enum _MediaKind { video, audio, other }

_MediaKind _kindOf(String pkg, ActivityData data) {
  if (_knownVideo.contains(pkg)) return _MediaKind.video;
  if (_knownAudio.contains(pkg)) return _MediaKind.audio;
  return switch (data.apps[pkg]?.category) {
    AppCategory.video => _MediaKind.video,
    AppCategory.audio => _MediaKind.audio,
    _ => _MediaKind.other,
  };
}

int _overlap(int s, int e, int from, int to) => math.max(0, math.min(e, to) - math.max(s, from));

/// Length of the union of [spans] inside [from, to).
Duration _unionLength(List<(int, int)> spans, int from, int to) {
  final clipped = [
    for (final (s, e) in spans)
      if (e > from && s < to) (math.max(s, from), math.min(e, to)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0;
  int? curStart;
  int? curEnd;
  for (final (s, e) in clipped) {
    if (curEnd == null || s > curEnd) {
      if (curStart != null) total += curEnd! - curStart;
      curStart = s;
      curEnd = e;
    } else if (e > curEnd) {
      curEnd = e;
    }
  }
  if (curStart != null) total += curEnd! - curStart;
  return Duration(milliseconds: total);
}
