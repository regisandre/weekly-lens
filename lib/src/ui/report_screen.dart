import 'package:flutter/material.dart';

import '../domain/report.dart';
import '../report_controller.dart';
import 'format.dart';
import 'permissions_sheet.dart';
import 'widgets.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.controller});

  final ReportController controller;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with WidgetsBindingObserver {
  ReportController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings after granting an access.
    if (state == AppLifecycleState.resumed) c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final r = c.report;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: c.refresh,
            child: CustomScrollView(
              slivers: [
                SliverAppBar.medium(
                  title: Text(formatWeekRange(c.week.start, c.week.end)),
                  actions: [
                    IconButton(
                      tooltip: 'Previous week',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: c.previousWeek,
                    ),
                    IconButton(
                      tooltip: 'Next week',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: c.canGoNext ? c.nextWeek : null,
                    ),
                    IconButton(
                      tooltip: 'Access and privacy',
                      icon: const Icon(Icons.shield_outlined),
                      onPressed: () => PermissionsSheet.show(context, c),
                    ),
                  ],
                ),
                if (c.loading && r == null)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else if (c.error != null && r == null)
                  SliverFillRemaining(child: Center(child: Text('Could not build the report: ${c.error}')))
                else if (r != null)
                  SliverList.list(children: _sections(context, r)),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _sections(BuildContext context, WeeklyReport r) {
    final p = c.permissions;
    return [
      if (p != null && !p.usageAccess) _AccessBanner(onTap: () => PermissionsSheet.show(context, c)),
      _ScreenTime(r),
      _Rhythm(r),
      _TopApps(r),
      _Notifications(r, onGrant: () => PermissionsSheet.show(context, c)),
      _Media(r),
      _Installs(r),
      _Ads(r, onGrant: () => PermissionsSheet.show(context, c)),
      const _Blind(),
      const _PrivacyFooter(),
    ];
  }
}

String? _coverageNote(Coverage cov, WeeklyReport r, String what) {
  if (!cov.enabled) return null;
  if (cov.from == null) return 'No $what recorded for this week.';
  if (!cov.complete) return '$what counted since ${formatDayTime(cov.from!)}.';
  return r.inProgress ? 'Week in progress.' : null;
}

class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: scheme.primaryContainer,
      child: ListTile(
        title: const Text('Turn on usage access to see your week'),
        subtitle: const Text('Screen time, opens and unlocks need it. Nothing leaves the phone.'),
        trailing: const Icon(Icons.arrow_forward),
        onTap: onTap,
      ),
    );
  }
}

class _ScreenTime extends StatelessWidget {
  const _ScreenTime(this.r);
  final WeeklyReport r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = r.screenTimePerDay;
    final measuredDays = days.where((d) => d > Duration.zero).length;
    final average = measuredDays == 0 ? Duration.zero : r.screenTime ~/ measuredDays;
    final previous = r.previousScreenTime;
    return SectionCard(
      title: 'Screen time',
      note: _coverageNote(r.usageCoverage, r, 'Usage'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatDuration(r.screenTime), style: theme.textTheme.displaySmall),
          Text(
            [
              if (measuredDays > 0) '${formatDuration(average)} a day on average',
              if (previous != null && !r.inProgress) formatDelta(r.screenTime, previous),
            ].where((s) => s.isNotEmpty).join('. '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DayBars(
            values: [for (final d in days) d.inMinutes.toDouble()],
            labels: [for (final d in days) formatDuration(d)],
            highlightToday: r.today,
          ),
        ],
      ),
    );
  }
}

class _Rhythm extends StatelessWidget {
  const _Rhythm(this.r);
  final WeeklyReport r;

  @override
  Widget build(BuildContext context) {
    final firsts = r.firstUnlockPerDay.whereType<DateTime>().map((t) => t.hour * 60 + t.minute).toList()..sort();
    String? firstPickup;
    if (firsts.isNotEmpty) {
      final median = firsts[firsts.length ~/ 2];
      firstPickup = 'first one around ${formatClock(DateTime(2000, 1, 1, median ~/ 60, median % 60))}';
    }
    final days = r.unlocksPerDay.where((u) => u > 0).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: StatTile(
                value: '${r.unlocks}',
                label: 'Unlocks',
                detail: days == 0 ? null : ['${(r.unlocks / days).round()} a day', ?firstPickup].join(', '),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                value: '${r.opens}',
                label: 'App opens',
                detail: r.apps.isEmpty ? null : '${r.apps.length} different apps',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopApps extends StatefulWidget {
  const _TopApps(this.r);
  final WeeklyReport r;

  @override
  State<_TopApps> createState() => _TopAppsState();
}

class _TopAppsState extends State<_TopApps> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final apps = widget.r.apps.where((a) => a.time >= const Duration(minutes: 1)).toList();
    final shown = _all ? apps : apps.take(6).toList();
    final top = apps.isEmpty ? Duration.zero : apps.first.time;
    return SectionCard(
      title: 'Most used apps',
      child: apps.isEmpty
          ? const EmptyLine('No app usage recorded for this week.')
          : Column(
              children: [
                for (final a in shown)
                  RankRow(
                    label: a.label,
                    value: formatDuration(a.time),
                    detail: a.opens == 1 ? 'opened once' : 'opened ${a.opens} times',
                    fraction: top.inSeconds == 0 ? 0 : a.time.inSeconds / top.inSeconds,
                  ),
                if (apps.length > 6)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(_all ? 'Show fewer' : 'Show all ${apps.length} apps'),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Notifications extends StatelessWidget {
  const _Notifications(this.r, {required this.onGrant});
  final WeeklyReport r;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final cov = r.notificationCoverage;
    if (!cov.enabled) {
      return SectionCard(
        title: 'Notifications',
        child: Row(
          children: [
            const Expanded(child: EmptyLine('Turn on notification access to count them from now on.')),
            TextButton(onPressed: onGrant, child: const Text('Turn on')),
          ],
        ),
      );
    }
    final top = r.notificationsByApp.take(5).toList();
    final max = top.isEmpty ? 1 : top.first.count;
    return SectionCard(
      title: 'Notifications',
      note: _coverageNote(cov, r, 'Notifications'),
      trailing: Text('${r.notifications}', style: Theme.of(context).textTheme.titleLarge),
      child: top.isEmpty
          ? const EmptyLine('None received.')
          : Column(
              children: [for (final a in top) RankRow(label: a.label, value: '${a.count}', fraction: a.count / max)],
            ),
    );
  }
}

class _Media extends StatelessWidget {
  const _Media(this.r);
  final WeeklyReport r;

  @override
  Widget build(BuildContext context) {
    if (!r.notificationCoverage.enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Watched and listened', style: Theme.of(context).textTheme.titleMedium),
          ),
          Row(
            children: [
              Expanded(
                child: StatTile(value: formatDuration(r.videoTime), label: 'Video'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(value: formatDuration(r.audioTime), label: 'Music, podcasts'),
              ),
            ],
          ),
          if (r.otherMediaTime > Duration.zero)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: EmptyLine('Plus ${formatDuration(r.otherMediaTime)} from apps that do not say what they play.'),
            ),
        ],
      ),
    );
  }
}

class _Installs extends StatelessWidget {
  const _Installs(this.r);
  final WeeklyReport r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [...r.installed, ...r.removed]..sort((a, b) => a.at.compareTo(b.at));
    return SectionCard(
      title: 'Apps installed and removed',
      child: items.isEmpty
          ? const EmptyLine('No change this week.')
          : Column(
              children: [
                for (final ch in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      ch.installed ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: ch.installed ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    title: Text(ch.label),
                    subtitle: Text(
                      '${ch.installed ? 'Installed' : 'Removed'} '
                      '${ch.exact ? '' : 'by '}${formatDayTime(DateTime.fromMillisecondsSinceEpoch(ch.at))}',
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Ads extends StatelessWidget {
  const _Ads(this.r, {required this.onGrant});
  final WeeklyReport r;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final cov = r.adCoverage;
    if (!cov.enabled) {
      return SectionCard(
        title: 'Ads you saw',
        note: 'Optional and experimental.',
        child: Row(
          children: [
            const Expanded(child: EmptyLine('Count the sponsored posts you scroll past, by advertiser.')),
            TextButton(onPressed: onGrant, child: const Text('Learn more')),
          ],
        ),
      );
    }
    final top = r.topAdvertisers.take(5).toList();
    final max = top.isEmpty ? 1 : top.first.count;
    return SectionCard(
      title: 'Ads you saw',
      note: _coverageNote(cov, r, 'Ads'),
      trailing: Text('${r.adImpressions}', style: Theme.of(context).textTheme.titleLarge),
      child: top.isEmpty
          ? const EmptyLine('No sponsored post spotted.')
          : Column(
              children: [
                for (final a in top)
                  RankRow(
                    label: a.name,
                    value: '${a.count}',
                    detail: 'in ${a.appLabels.join(', ')}',
                    fraction: a.count / max,
                  ),
              ],
            ),
    );
  }
}

class _Blind extends StatelessWidget {
  const _Blind();

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: 'What this report cannot see',
    child: EmptyLine(
      'Game high scores: games keep them to themselves, and there is no shared Android API for them. '
      'What happens inside apps (posts, videos, messages) is never read, except the optional ad labels.',
    ),
  );
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
    child: Row(
      children: [
        Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        const Expanded(child: EmptyLine('Collected and kept on this phone only. The app cannot use the internet.')),
      ],
    ),
  );
}
