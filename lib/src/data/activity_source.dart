import '../domain/models.dart';
import '../platform/activity_api.g.dart';

export '../platform/activity_api.g.dart' show PermissionState, SettingsScreen;

/// Where activity data comes from: the phone (Android collector) or a seeded demo.
abstract interface class ActivitySource {
  Future<PermissionState> permissions();
  Future<void> sync();

  /// Usage events from [usageFrom] (sessions need what came before the week), the rest in [from, to).
  Future<ActivityData> load({required int usageFrom, required int from, required int to});
  Future<void> openSettings(SettingsScreen screen);
  Future<void> wipe();
}

class PlatformActivitySource implements ActivitySource {
  PlatformActivitySource([ActivityApi? api]) : _api = api ?? ActivityApi();
  final ActivityApi _api;

  @override
  Future<PermissionState> permissions() => _api.permissions();

  @override
  Future<void> sync() => _api.syncNow();

  @override
  Future<void> openSettings(SettingsScreen screen) => _api.openSettings(screen);

  @override
  Future<void> wipe() => _api.wipe();

  @override
  Future<ActivityData> load({required int usageFrom, required int from, required int to}) async =>
      fromRaw(await _api.rawRange(usageFrom, from, to));

  static ActivityData fromRaw(RawRange r) {
    final u = r.usage;
    return ActivityData(
      usage: [
        for (var i = 0; i < u.ts.length; i++)
          UsageEvent(ts: u.ts[i], pkg: u.strings[u.pkg[i]], cls: u.strings[u.cls[i]], type: u.type[i]),
      ],
      notifications: [for (final n in r.notifications) NotificationArrival(pkg: n.pkg, postedAt: n.postedAt)],
      media: [for (final m in r.media) MediaSegment(pkg: m.pkg, start: m.start, end: m.end)],
      packageChanges: [
        for (final c in r.packageChanges)
          PackageChange(pkg: c.pkg, label: c.label, installed: c.installed, at: c.at, exact: c.exact),
      ],
      ads: [for (final a in r.ads) AdImpression(pkg: a.pkg, advertiser: a.advertiser, seenAt: a.seenAt)],
      apps: {
        for (final a in r.apps)
          a.pkg: AppMeta(pkg: a.pkg, label: a.label, category: AppCategory.fromAndroid(a.category)),
      },
      homePackages: r.homePackages.toSet(),
      usageSince: r.earliestUsageEvent,
      notificationsSince: r.notificationsSince,
      adsSince: r.adsSince,
    );
  }
}
