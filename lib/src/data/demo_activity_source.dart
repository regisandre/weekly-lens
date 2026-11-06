import 'dart:math';

import '../domain/models.dart';
import 'activity_source.dart';

/// Seeded, fictional data: runs anywhere (emulator, desktop, iOS) and keeps real app lists out
/// of public screenshots. The same seed always gives the same weeks.
class DemoActivitySource implements ActivitySource {
  DemoActivitySource({DateTime? now, this.seed = 7}) : _now = now ?? DateTime.now();

  final DateTime _now;
  final int seed;
  bool _wiped = false;

  static const _apps = [
    // pkg, label, category, weight (share of screen time), notifications per day
    ('demo.chat', 'Parley', AppCategory.social, 9, 38),
    ('demo.feed', 'Lumen Feed', AppCategory.social, 8, 6),
    ('demo.video', 'StreamBox', AppCategory.video, 6, 2),
    ('demo.mail', 'Inboxly', AppCategory.productivity, 3, 14),
    ('demo.maps', 'Wayfinder', AppCategory.maps, 2, 1),
    ('demo.news', 'Le Quotidien', AppCategory.news, 2, 5),
    ('demo.music', 'Tempo', AppCategory.audio, 1, 0),
    ('demo.game', 'Tile Quest', AppCategory.game, 3, 2),
    ('demo.bank', 'Banque Nord', AppCategory.undefined, 1, 1),
  ];
  static const _advertisers = [
    'Velora Running',
    'Kasa Coffee',
    'Nordlys Travel',
    'Pixelcraft Studio',
    'Brasserie Lune',
    'Atlas Insurance',
    'Velora Running',
    'Kasa Coffee',
    'Velora Running',
  ];

  @override
  Future<PermissionState> permissions() async =>
      PermissionState(usageAccess: true, notificationAccess: true, adsAccess: true);

  @override
  Future<void> sync() async {}

  @override
  Future<void> openSettings(SettingsScreen screen) async {}

  @override
  Future<void> wipe() async => _wiped = true;

  @override
  Future<ActivityData> load({required int usageFrom, required int from, required int to}) async {
    final since = DateTime(_now.year, _now.month, _now.day - 20).millisecondsSinceEpoch;
    final end = min(to, _now.millisecondsSinceEpoch);
    final usage = <UsageEvent>[];
    final notifications = <NotificationArrival>[];
    final media = <MediaSegment>[];
    final ads = <AdImpression>[];

    if (!_wiped) {
      for (
        var day = DateTime.fromMillisecondsSinceEpoch(max(usageFrom, since));
        day.millisecondsSinceEpoch < end;
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        _day(DateTime(day.year, day.month, day.day), end, usage, notifications, media, ads);
      }
    }

    return ActivityData(
      usage: usage,
      notifications: notifications,
      media: media,
      packageChanges: _wiped ? const [] : _changes(from, end),
      ads: ads,
      apps: {
        for (final a in _apps) a.$1: AppMeta(pkg: a.$1, label: a.$2, category: a.$3),
        'demo.shop': const AppMeta(pkg: 'demo.shop', label: 'Marketly', category: AppCategory.undefined),
      },
      homePackages: const {'demo.launcher'},
      usageSince: since,
      notificationsSince: since,
      adsSince: since,
    );
  }

  void _day(
    DateTime day,
    int end,
    List<UsageEvent> usage,
    List<NotificationArrival> notifications,
    List<MediaSegment> media,
    List<AdImpression> ads,
  ) {
    final rnd = Random(seed * 100000 + day.year * 400 + day.month * 32 + day.day);
    final weekend = day.weekday >= DateTime.saturday;
    final wake = day.add(Duration(minutes: (weekend ? 8 * 60 + 30 : 6 * 60 + 50) + rnd.nextInt(40)));
    final totalWeight = _apps.fold(0, (s, a) => s + a.$4);

    var t = wake;
    final bedtime = day.add(Duration(hours: 23, minutes: rnd.nextInt(70)));
    while (t.isBefore(bedtime) && t.millisecondsSinceEpoch < end) {
      // One pickup: unlock, use 1 to 4 apps, screen off.
      usage.add(UsageEvent(ts: t.millisecondsSinceEpoch, pkg: 'android', cls: '', type: UsageEventType.keyguardHidden));
      var cursor = t.add(const Duration(seconds: 2));
      for (var i = 0, n = 1 + rnd.nextInt(3); i < n; i++) {
        var pick = rnd.nextInt(totalWeight);
        final app = _apps.firstWhere((a) => (pick -= a.$4) < 0);
        final minutes = app.$3 == AppCategory.video ? 3 + rnd.nextInt(12) : 1 + rnd.nextInt(9);
        final stop = cursor.add(Duration(minutes: minutes, seconds: rnd.nextInt(60)));
        usage
          ..add(UsageEvent(ts: cursor.millisecondsSinceEpoch, pkg: app.$1, cls: 'Main', type: UsageEventType.resumed))
          ..add(UsageEvent(ts: stop.millisecondsSinceEpoch, pkg: app.$1, cls: 'Main', type: UsageEventType.paused));
        if (app.$3 == AppCategory.video) {
          media.add(
            MediaSegment(pkg: app.$1, start: cursor.millisecondsSinceEpoch + 4000, end: stop.millisecondsSinceEpoch),
          );
        }
        if (app.$1 == 'demo.feed' || app.$1 == 'demo.video') {
          for (var k = 0, m = rnd.nextInt(minutes ~/ 4 + 1); k < m; k++) {
            ads.add(
              AdImpression(
                pkg: app.$1,
                advertiser: _advertisers[rnd.nextInt(_advertisers.length)],
                seenAt: cursor.millisecondsSinceEpoch + k * 30000,
              ),
            );
          }
        }
        cursor = stop.add(const Duration(seconds: 1));
      }
      usage.add(UsageEvent(ts: cursor.millisecondsSinceEpoch, pkg: 'android', cls: '', type: UsageEventType.screenOff));
      t = cursor.add(Duration(minutes: 10 + rnd.nextInt(weekend ? 50 : 35)));
    }

    // Background audio on the commute.
    if (!weekend) {
      final start = day.add(const Duration(hours: 8, minutes: 5));
      media.add(
        MediaSegment(
          pkg: 'demo.music',
          start: start.millisecondsSinceEpoch,
          end: start.add(Duration(minutes: 25 + rnd.nextInt(15))).millisecondsSinceEpoch,
        ),
      );
    }

    for (final a in _apps) {
      for (var k = 0, n = (a.$5 * (0.6 + rnd.nextDouble() * 0.8)).round(); k < n; k++) {
        final at = wake.add(Duration(minutes: rnd.nextInt(15 * 60)));
        if (at.millisecondsSinceEpoch < end) {
          notifications.add(NotificationArrival(pkg: a.$1, postedAt: at.millisecondsSinceEpoch));
        }
      }
    }
  }

  List<PackageChange> _changes(int from, int to) {
    final base = DateTime(_now.year, _now.month, _now.day);
    return [
      PackageChange(
        pkg: 'demo.shop',
        label: 'Marketly',
        installed: true,
        at: base.subtract(const Duration(days: 3, hours: -14)).millisecondsSinceEpoch,
        exact: true,
      ),
      PackageChange(
        pkg: 'demo.old',
        label: 'Coupon Hunter',
        installed: false,
        at: base.subtract(const Duration(days: 2, hours: -9)).millisecondsSinceEpoch,
        exact: false,
      ),
      PackageChange(
        pkg: 'demo.trip',
        label: 'Railpass',
        installed: true,
        at: base.subtract(const Duration(days: 9, hours: -18)).millisecondsSinceEpoch,
        exact: true,
      ),
    ].where((c) => c.at >= from && c.at < to).toList();
  }
}
