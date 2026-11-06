import 'package:flutter/material.dart';

import 'src/data/activity_source.dart';
import 'src/data/demo_activity_source.dart';
import 'src/report_controller.dart';
import 'src/ui/report_screen.dart';

/// `flutter run --dart-define=DEMO=true` shows seeded, fictional data (any platform).
const _demo = bool.fromEnvironment('DEMO');

void main() {
  final ActivitySource source = _demo ? DemoActivitySource() : PlatformActivitySource();
  runApp(WeeklyLensApp(controller: ReportController(source)));
}

class WeeklyLensApp extends StatelessWidget {
  const WeeklyLensApp({super.key, required this.controller});

  final ReportController controller;

  static const _seed = Color(0xFF2E5E6B);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Weekly Lens',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.light),
    darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
    home: ReportScreen(controller: controller),
  );
}
