import 'package:flutter/material.dart';

import '../data/activity_source.dart';
import '../report_controller.dart';

/// The report works in tiers: each access the user grants adds metrics, none is required.
class PermissionsSheet extends StatelessWidget {
  const PermissionsSheet({super.key, required this.controller});

  final ReportController controller;

  static Future<void> show(BuildContext context, ReportController controller) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PermissionsSheet(controller: controller),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.permissions;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('What the report can see', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Each access adds to the report. Everything stays on this phone: the app has no internet permission.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              const _Tier(
                title: 'Always on',
                body: 'Apps installed this week (and removed, from the first day the app runs).',
                granted: true,
              ),
              _Tier(
                title: 'Usage access',
                body:
                    'Time in each app, how often you open them, unlocks. Android keeps about a week '
                    'of history, so last week shows up right away.',
                granted: p?.usageAccess ?? false,
                onGrant: () => controller.openSettings(SettingsScreen.usageAccess),
              ),
              _Tier(
                title: 'Notification access',
                body:
                    'How many notifications you received and from which apps, and time spent '
                    'watching or listening to media. Counted from the moment you turn it on. '
                    'Notification text is never read or stored.',
                granted: p?.notificationAccess ?? false,
                onGrant: () => controller.openSettings(SettingsScreen.notificationAccess),
              ),
              _Tier(
                title: 'Ads seen (optional, experimental)',
                body:
                    'An accessibility service that spots "Sponsored" labels in Instagram, Facebook, '
                    'YouTube, LinkedIn, X and TikTok. Only the advertiser name and the time are kept. '
                    'It sees nothing in other apps. If Android blocks it, allow restricted settings '
                    'in App info first.',
                granted: p?.adsAccess ?? false,
                onGrant: () => controller.openSettings(SettingsScreen.accessibility),
                secondary: TextButton(
                  onPressed: () => controller.openSettings(SettingsScreen.appInfo),
                  child: const Text('App info'),
                ),
              ),
              const Divider(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete everything collected'),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: () => _confirmWipe(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all collected data?'),
        content: const Text(
          'Usage, notification, media and ad records on this phone are erased. '
          'Usage history Android still keeps will come back at the next sync.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await controller.wipe();
  }
}

class _Tier extends StatelessWidget {
  const _Tier({required this.title, required this.body, required this.granted, this.onGrant, this.secondary});

  final String title;
  final String body;
  final bool granted;
  final VoidCallback? onGrant;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
                if (!granted && onGrant != null)
                  Row(
                    children: [
                      FilledButton.tonal(onPressed: onGrant, child: const Text('Turn on')),
                      const SizedBox(width: 8),
                      ?secondary,
                    ],
                  ),
                if (granted && onGrant != null) TextButton(onPressed: onGrant, child: const Text('Manage')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
