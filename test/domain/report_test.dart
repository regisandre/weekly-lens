import 'package:flutter_test/flutter_test.dart';
import 'package:weekly_lens/src/domain/models.dart';
import 'package:weekly_lens/src/domain/report.dart';
import 'package:weekly_lens/src/domain/week.dart';

/// Week under test: Monday 2 to Monday 9 November 2026, local time.
final week = Week.containing(DateTime(2026, 11, 4));

int at(int day, [int h = 0, int m = 0]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

UsageEvent ev(int ts, String pkg, int type, [String cls = 'Main']) =>
    UsageEvent(ts: ts, pkg: pkg, cls: cls, type: type);

List<UsageEvent> use(String pkg, int from, int to) => [
  ev(from, pkg, UsageEventType.resumed),
  ev(to, pkg, UsageEventType.paused),
];

const apps = {
  'chat': AppMeta(pkg: 'chat', label: 'Chat', category: AppCategory.social),
  'tube': AppMeta(pkg: 'tube', label: 'Tube', category: AppCategory.video),
  'pods': AppMeta(pkg: 'pods', label: 'Pods', category: AppCategory.audio),
  'game': AppMeta(pkg: 'game', label: 'Game', category: AppCategory.game),
  'home': AppMeta(pkg: 'home', label: 'Launcher', category: AppCategory.undefined),
};

ActivityData data({
  List<UsageEvent> usage = const [],
  List<NotificationArrival> notifications = const [],
  List<MediaSegment> media = const [],
  List<PackageChange> changes = const [],
  List<AdImpression> ads = const [],
  int? usageSince,
  int? notificationsSince,
  int? adsSince,
}) => ActivityData(
  usage: usage,
  notifications: notifications,
  media: media,
  packageChanges: changes,
  ads: ads,
  apps: apps,
  homePackages: const {'home'},
  usageSince: usageSince ?? at(1),
  notificationsSince: notificationsSince ?? at(1),
  adsSince: adsSince ?? 0,
);

final afterWeek = DateTime(2026, 11, 10);
const min = Duration(minutes: 1);

void main() {
  test('screen time is split per app and per local day, clipped to the week', () {
    final r = buildReport(
      data(
        usage: [
          ...use('chat', at(2, 9), at(2, 9, 30)),
          ...use('chat', at(3, 23, 50), at(4, 0, 10)), // crosses midnight
          ...use('game', at(1, 23, 50), at(2, 0, 20)), // starts the week before
          ...use('home', at(2, 10), at(2, 11)), // launcher is not an app
          ...use(ownPackage, at(2, 12), at(2, 13)), // nor is this app
          ...use('tube', at(8, 23, 0), at(9, 1, 0)), // ends after the week
        ],
      ),
      week,
      now: afterWeek,
    );

    expect(r.screenTime, min * (30 + 20 + 20 + 60), reason: 'total, clipped');
    expect(r.screenTimePerDay, [
      min * (30 + 20),
      min * 10,
      min * 10,
      Duration.zero,
      Duration.zero,
      Duration.zero,
      min * 60,
    ], reason: 'per day, split at local midnight');
    expect(r.apps.map((a) => (a.label, a.time, a.opens)).toList(), [
      ('Tube', min * 60, 1),
      ('Chat', min * 50, 2),
      ('Game', min * 20, 0),
    ], reason: 'ranked by time; an open counts in the week it started');
  });

  test('unlocks and notifications are counted in the week and per app', () {
    final r = buildReport(
      data(
        usage: [
          ev(at(2, 1, 30), 'android', UsageEventType.keyguardHidden), // late night, not a morning pickup
          ev(at(2, 8), 'android', UsageEventType.keyguardHidden),
          ev(at(2, 12), 'android', UsageEventType.keyguardHidden),
          ev(at(5, 8), 'android', UsageEventType.keyguardHidden),
          ev(at(1, 8), 'android', UsageEventType.keyguardHidden), // week before
        ],
        notifications: [
          NotificationArrival(pkg: 'chat', postedAt: at(2, 9)),
          NotificationArrival(pkg: 'chat', postedAt: at(3, 9)),
          NotificationArrival(pkg: 'tube', postedAt: at(3, 10)),
          NotificationArrival(pkg: 'chat', postedAt: at(9, 0, 1)), // week after
        ],
      ),
      week,
      now: afterWeek,
    );

    expect(r.unlocks, 4, reason: 'unlocks in the week');
    expect(r.unlocksPerDay, [3, 0, 0, 1, 0, 0, 0], reason: 'unlocks per day');
    expect(
      r.firstUnlockPerDay[0],
      DateTime(2026, 11, 2, 8),
      reason: 'first pickup of Monday ignores the night before 04:00',
    );
    expect(r.notifications, 3, reason: 'notifications in the week');
    expect(r.notificationsByApp.map((a) => (a.label, a.count)).toList(), [
      ('Chat', 2),
      ('Tube', 1),
    ], reason: 'notifications ranked per app');
  });

  test('installs and removals of the week are listed with their labels', () {
    final r = buildReport(
      data(
        changes: [
          PackageChange(pkg: 'new', label: 'New App', installed: true, at: at(3, 10), exact: true),
          PackageChange(pkg: 'old', label: 'Old App', installed: false, at: at(4, 10), exact: false),
          PackageChange(pkg: 'prev', label: 'Earlier', installed: true, at: at(1, 10), exact: true),
        ],
      ),
      week,
      now: afterWeek,
    );

    expect(r.installed.map((c) => c.label).toList(), ['New App'], reason: 'installed this week');
    expect(r.removed.map((c) => (c.label, c.exact)).toList(), [
      ('Old App', false),
    ], reason: 'removed, time approximate');
  });

  test('video time is the union of playback in video apps, clipped to the week', () {
    final r = buildReport(
      data(
        media: [
          MediaSegment(pkg: 'tube', start: at(2, 20), end: at(2, 21)),
          MediaSegment(pkg: 'tube', start: at(2, 20, 30), end: at(2, 21, 30)), // overlaps: count once
          MediaSegment(pkg: 'youtube_unknown', start: at(3, 20), end: at(3, 20, 10)), // unknown app
          MediaSegment(pkg: 'pods', start: at(4, 7), end: at(4, 8)), // audio
          MediaSegment(pkg: 'tube', start: at(1, 23, 30), end: at(2, 0, 30)), // straddles week start
        ],
      ),
      week,
      now: afterWeek,
    );

    expect(r.videoTime, min * (90 + 30), reason: 'video, overlaps merged, clipped');
    expect(r.audioTime, min * 60, reason: 'audio apps');
    expect(r.otherMediaTime, min * 10, reason: 'media from apps of unknown kind');
  });

  test('ads seen are ranked by advertiser across apps', () {
    final r = buildReport(
      data(
        adsSince: at(1),
        ads: [
          AdImpression(pkg: 'chat', advertiser: 'Acme', seenAt: at(2, 9)),
          AdImpression(pkg: 'tube', advertiser: 'acme', seenAt: at(3, 9)),
          AdImpression(pkg: 'chat', advertiser: 'Bolt Bikes', seenAt: at(3, 10)),
          AdImpression(pkg: 'chat', advertiser: 'Bolt Bikes', seenAt: at(1, 10)), // week before
        ],
      ),
      week,
      now: afterWeek,
    );

    expect(r.adImpressions, 3, reason: 'ads in the week');
    expect(
      r.topAdvertisers.map((a) => (a.name, a.count, a.appLabels.join(', '))).toList(),
      [('Acme', 2, 'Chat, Tube'), ('Bolt Bikes', 1, 'Chat')],
      reason: 'merged without case, with the apps they were seen in',
    );
  });

  test('each metric says from when it is measured, so a partial week is never shown as complete', () {
    final cases =
        <
          ({
            String name,
            int usageSince,
            int notificationsSince,
            int adsSince,
            DateTime now,
            bool usageComplete,
            DateTime? notificationsFrom,
            bool adsOn,
            bool inProgress,
          })
        >[
          (
            name: 'everything on before the week',
            usageSince: at(1),
            notificationsSince: at(1),
            adsSince: at(1),
            now: afterWeek,
            usageComplete: true,
            notificationsFrom: DateTime(2026, 11, 2),
            adsOn: true,
            inProgress: false,
          ),
          (
            name: 'notifications enabled on Thursday, ads never',
            usageSince: at(1),
            notificationsSince: at(5, 17),
            adsSince: 0,
            now: afterWeek,
            usageComplete: true,
            notificationsFrom: DateTime(2026, 11, 5, 17),
            adsOn: false,
            inProgress: false,
          ),
          (
            name: 'OS history starts mid-week, week still running',
            usageSince: at(3, 7),
            notificationsSince: 0,
            adsSince: 0,
            now: DateTime(2026, 11, 6, 12),
            usageComplete: false,
            notificationsFrom: null,
            adsOn: false,
            inProgress: true,
          ),
        ];

    for (final c in cases) {
      final r = buildReport(
        data(usageSince: c.usageSince, notificationsSince: c.notificationsSince, adsSince: c.adsSince),
        week,
        now: c.now,
      );
      expect(r.usageCoverage.complete, c.usageComplete, reason: '${c.name}: usage complete');
      expect(r.notificationCoverage.from, c.notificationsFrom, reason: '${c.name}: notifications from');
      expect(r.adCoverage.enabled, c.adsOn, reason: '${c.name}: ads enabled');
      expect(r.inProgress, c.inProgress, reason: '${c.name}: week in progress');
    }
  });

  test('the previous week is compared only when it was fully measured', () {
    final usage = [
      ...use('chat', at(2, 9), at(2, 11)), // this week: 2 h
      ...use(
        'chat',
        DateTime(2026, 10, 28, 9).millisecondsSinceEpoch,
        DateTime(2026, 10, 28, 10).millisecondsSinceEpoch,
      ), // previous week: 1 h
    ];

    final cases = <({String name, int usageSince, Duration? expected})>[
      (
        name: 'history covers the previous week',
        usageSince: DateTime(2026, 10, 20).millisecondsSinceEpoch,
        expected: const Duration(hours: 1),
      ),
      (
        name: 'history starts inside the previous week',
        usageSince: DateTime(2026, 10, 28).millisecondsSinceEpoch,
        expected: null,
      ),
    ];

    for (final c in cases) {
      final r = buildReport(
        data(usage: usage, usageSince: c.usageSince),
        week,
        now: afterWeek,
      );
      expect(r.previousScreenTime, c.expected, reason: c.name);
    }
  });
}
