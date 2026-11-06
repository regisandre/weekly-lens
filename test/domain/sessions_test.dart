import 'package:flutter_test/flutter_test.dart';
import 'package:weekly_lens/src/domain/models.dart';
import 'package:weekly_lens/src/domain/sessions.dart';

const resumed = UsageEventType.resumed;
const paused = UsageEventType.paused;
const stopped = UsageEventType.stopped;
const screenOff = UsageEventType.screenOff;
const shutdown = UsageEventType.shutdown;
const startup = UsageEventType.startup;

UsageEvent e(int s, String pkg, int type, [String cls = 'Main']) =>
    UsageEvent(ts: s * 1000, pkg: pkg, cls: cls, type: type);

UsageEvent sys(int s, int type) => UsageEvent(ts: s * 1000, pkg: 'android', cls: '', type: type);

/// (package, start s, end s)
typedef S = (String, int, int);

void main() {
  test('usage events become one session per continuous stretch of an app in the foreground', () {
    final cases = <({String name, List<UsageEvent> events, int until, List<S> expected})>[
      (
        name: 'resume then pause',
        events: [e(10, 'chat', resumed), e(70, 'chat', paused)],
        until: 1000,
        expected: [('chat', 10, 70)],
      ),
      (
        name: 'stopped closes like paused',
        events: [e(10, 'chat', resumed), e(40, 'chat', stopped)],
        until: 1000,
        expected: [('chat', 10, 40)],
      ),
      (
        name: 'two overlapping activities of one app are one session, not double time',
        events: [
          e(10, 'chat', resumed, 'List'),
          e(20, 'chat', resumed, 'Thread'),
          e(30, 'chat', paused, 'List'),
          e(90, 'chat', paused, 'Thread'),
        ],
        until: 1000,
        expected: [('chat', 10, 90)],
      ),
      (
        name: 'moving between screens of one app (short gap) is still one open',
        events: [
          e(10, 'chat', resumed, 'List'),
          e(30, 'chat', paused, 'List'),
          e(31, 'chat', resumed, 'Thread'),
          e(60, 'chat', paused, 'Thread'),
        ],
        until: 1000,
        expected: [('chat', 10, 60)],
      ),
      (
        name: 'coming back after another app is a new open',
        events: [
          e(10, 'chat', resumed),
          e(20, 'chat', paused),
          e(20, 'maps', resumed),
          e(21, 'maps', paused),
          e(21, 'chat', resumed),
          e(30, 'chat', paused),
        ],
        until: 1000,
        expected: [('chat', 10, 20), ('maps', 20, 21), ('chat', 21, 30)],
      ),
      (
        name: 'screen off ends the session even without a pause, and the next one is a new open',
        events: [e(10, 'chat', resumed), sys(50, screenOff), e(51, 'chat', resumed), e(60, 'chat', paused)],
        until: 1000,
        expected: [('chat', 10, 50), ('chat', 51, 60)],
      ),
      (name: 'a pause without a resume is ignored', events: [e(10, 'chat', paused)], until: 1000, expected: []),
      (
        name: 'shutdown ends what was open at the shutdown time',
        events: [e(10, 'chat', resumed), sys(40, shutdown), sys(100, startup)],
        until: 1000,
        expected: [('chat', 10, 40)],
      ),
      (
        name: 'something opened between shutdown and startup has no known end and is dropped',
        events: [
          sys(40, shutdown),
          e(50, 'chat', resumed),
          sys(100, startup),
          e(110, 'maps', resumed),
          e(120, 'maps', paused),
        ],
        until: 1000,
        expected: [('maps', 110, 120)],
      ),
      (
        name: 'an app still in the foreground is counted up to now',
        events: [e(10, 'chat', resumed)],
        until: 25,
        expected: [('chat', 10, 25)],
      ),
    ];

    for (final c in cases) {
      final got = appSessions(
        c.events,
        until: c.until * 1000,
      ).map((s) => (s.pkg, s.start ~/ 1000, s.end ~/ 1000)).toList();
      expect(got, c.expected, reason: c.name);
    }
  });
}
