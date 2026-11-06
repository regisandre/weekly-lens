/// Raw facts as collected on the phone. Times are milliseconds since the epoch.
library;

const ownPackage = 'app.weeklylens';

/// The subset of android.app.usage.UsageEvents.Event types the collector keeps.
abstract final class UsageEventType {
  static const resumed = 1;
  static const paused = 2;
  static const screenOn = 15;
  static const screenOff = 16;
  static const keyguardShown = 17;
  static const keyguardHidden = 18;
  static const stopped = 23;
  static const shutdown = 26;
  static const startup = 27;
}

class UsageEvent {
  const UsageEvent({required this.ts, required this.pkg, required this.cls, required this.type});
  final int ts;
  final String pkg;
  final String cls;
  final int type;
}

/// android.content.pm.ApplicationInfo.category, as declared by each app (often undefined).
enum AppCategory {
  undefined,
  game,
  audio,
  video,
  image,
  social,
  news,
  maps,
  productivity,
  accessibility;

  static AppCategory fromAndroid(int value) =>
      value >= 0 && value + 1 < AppCategory.values.length ? AppCategory.values[value + 1] : undefined;
}

class AppMeta {
  const AppMeta({required this.pkg, required this.label, required this.category});
  final String pkg;
  final String label;
  final AppCategory category;
}

class NotificationArrival {
  const NotificationArrival({required this.pkg, required this.postedAt});
  final String pkg;
  final int postedAt;
}

class MediaSegment {
  const MediaSegment({required this.pkg, required this.start, required this.end});
  final String pkg;
  final int start;
  final int end;
}

class PackageChange {
  const PackageChange({
    required this.pkg,
    required this.label,
    required this.installed,
    required this.at,
    required this.exact,
  });
  final String pkg;
  final String label;
  final bool installed;
  final int at;

  /// False when the time is only "noticed at the next snapshot".
  final bool exact;
}

class AdImpression {
  const AdImpression({required this.pkg, required this.advertiser, required this.seenAt});
  final String pkg;
  final String advertiser;
  final int seenAt;
}

/// Everything collected over a time range, plus when each source started measuring.
class ActivityData {
  const ActivityData({
    required this.usage,
    required this.notifications,
    required this.media,
    required this.packageChanges,
    required this.ads,
    required this.apps,
    required this.homePackages,
    required this.usageSince,
    required this.notificationsSince,
    required this.adsSince,
  });

  final List<UsageEvent> usage;
  final List<NotificationArrival> notifications;
  final List<MediaSegment> media;
  final List<PackageChange> packageChanges;
  final List<AdImpression> ads;
  final Map<String, AppMeta> apps;
  final Set<String> homePackages;

  /// Start of each source's history, 0 when the source was never enabled.
  final int usageSince;
  final int notificationsSince;
  final int adsSince;

  String labelOf(String pkg) => apps[pkg]?.label ?? pkg;
}
