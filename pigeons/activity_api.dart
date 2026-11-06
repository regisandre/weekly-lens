// Typed contract between the Flutter UI and the Android collector.
// Regenerate with: dart run pigeon --input pigeons/activity_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/activity_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/app/weeklylens/bridge/ActivityApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.weeklylens.bridge'),
  ),
)
class PermissionState {
  PermissionState({
    required this.usageAccess,
    required this.notificationAccess,
    required this.adsAccess,
  });
  bool usageAccess;
  bool notificationAccess;
  bool adsAccess;
}

/// Usage events as parallel columns: one typed array per field and a shared string table, so a
/// week (tens of thousands of events) crosses the bridge as a few buffers instead of objects.
class UsageColumns {
  UsageColumns({
    required this.ts,
    required this.type,
    required this.pkg,
    required this.cls,
    required this.strings,
  });
  Int64List ts;
  Int32List type;

  /// Indexes into [strings].
  Int32List pkg;
  Int32List cls;
  List<String> strings;
}

class RawNotification {
  RawNotification({required this.pkg, required this.postedAt});
  String pkg;
  int postedAt;
}

class RawMediaSegment {
  RawMediaSegment({required this.pkg, required this.start, required this.end});
  String pkg;
  int start;
  int end;
}

class RawPackageChange {
  RawPackageChange({
    required this.pkg,
    required this.label,
    required this.installed,
    required this.at,
    required this.exact,
  });
  String pkg;
  String label;
  bool installed;
  int at;
  bool exact;
}

class RawAdImpression {
  RawAdImpression({
    required this.pkg,
    required this.advertiser,
    required this.seenAt,
  });
  String pkg;
  String advertiser;
  int seenAt;
}

class RawApp {
  RawApp({required this.pkg, required this.label, required this.category});
  String pkg;
  String label;

  /// android.content.pm.ApplicationInfo.category, -1 when undefined.
  int category;
}

/// Usage events from [usageFrom] (sessions need history before the week), everything else in
/// [start, end), plus what is needed to label it honestly.
class RawRange {
  RawRange({
    required this.usage,
    required this.notifications,
    required this.media,
    required this.packageChanges,
    required this.ads,
    required this.apps,
    required this.homePackages,
    required this.earliestUsageEvent,
    required this.notificationsSince,
    required this.adsSince,
  });
  UsageColumns usage;
  List<RawNotification> notifications;
  List<RawMediaSegment> media;
  List<RawPackageChange> packageChanges;
  List<RawAdImpression> ads;
  List<RawApp> apps;

  /// Launchers: time on the home screen is not "time in an app".
  List<String> homePackages;

  /// Oldest usage event the OS still had on the first run, 0 if unknown.
  int earliestUsageEvent;

  /// When the notification listener first connected, 0 if never.
  int notificationsSince;

  /// When the ads observer first connected, 0 if never.
  int adsSince;
}

enum SettingsScreen { usageAccess, notificationAccess, accessibility, appInfo }

@HostApi()
abstract class ActivityApi {
  PermissionState permissions();

  void openSettings(SettingsScreen screen);

  /// Pulls fresh data from the OS into the local store.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void syncNow();

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  RawRange rawRange(int usageFrom, int start, int end);

  /// Deletes everything collected so far.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void wipe();
}
