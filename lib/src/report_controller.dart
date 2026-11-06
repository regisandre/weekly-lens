import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'data/activity_source.dart';
import 'domain/report.dart';
import 'domain/week.dart';

/// Holds the selected week and its report. Building a report walks tens of thousands of events,
/// so it runs on a background isolate and the UI thread only renders.
class ReportController extends ChangeNotifier {
  ReportController(this._source, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    week = Week.containing(_clock());
  }

  final ActivitySource _source;
  final DateTime Function() _clock;

  late Week week;
  PermissionState? permissions;
  WeeklyReport? report;
  bool loading = false;
  Object? error;
  int _generation = 0;

  bool get canGoNext => !week.next.start.isAfter(_clock());

  Future<void> refresh({bool sync = true}) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      permissions = await _source.permissions();
      if (sync) await _source.sync();
      final target = week;
      final now = _clock();
      // From the previous week (comparison) minus a day (sessions that started before it).
      final from = DateTime(target.previous.start.year, target.previous.start.month, target.previous.start.day - 1);
      final data = await _source.load(usageFrom: from.millisecondsSinceEpoch, from: target.startMs, to: target.endMs);
      final built = await Isolate.run(() => buildReport(data, target, now: now));
      if (generation != _generation) return; // a newer request won
      report = built;
    } catch (e) {
      if (generation != _generation) return;
      error = e;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void previousWeek() {
    week = week.previous;
    report = null;
    refresh(sync: false);
  }

  void nextWeek() {
    if (!canGoNext) return;
    week = week.next;
    report = null;
    refresh(sync: false);
  }

  Future<void> openSettings(SettingsScreen screen) => _source.openSettings(screen);

  Future<void> wipe() async {
    await _source.wipe();
    await refresh(sync: false);
  }
}
