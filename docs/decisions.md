# Decisions

> Status: current for the submitted version.
> Last checked: 2026-11-06

Each decision, the main alternative, and why.

| Decision | Alternative | Why |
|---|---|---|
| Android first, iOS as a separate design | Same features on both | iOS only exposes Screen Time to a sandboxed extension that cannot return data to the app. A port would hide that difference instead of designing for it. |
| Flutter UI, Kotlin collectors | Native Compose only | The system APIs are Kotlin either way. Flutter keeps the report screen reusable for an iOS host and matches my strongest stack. |
| Pigeon for the bridge | Hand-written `MethodChannel` | Typed contract, generated on both sides, background task queue for heavy calls. String keys break silently. |
| Kotlin stores raw facts, Dart computes | Aggregate in Kotlin | Rules in pure Dart are testable without a device, and the rules can change without losing history. |
| Own copy of usage events, every 2 hours | Query the OS when the report opens | Android keeps about 9 days on the test phone. Without a copy, the previous week disappears. 2 hours is far inside that window and cheap on battery. |
| WorkManager, no foreground service | Foreground service polling the current app | A permanent notification and battery cost for no gain: the OS already records usage events. |
| Session = foreground stretch of a package, overlapping activities merged | Sum each activity's resumed time | Two activities of one app can be resumed together; summing them double-counts. |
| Screen off and shutdown close open sessions; resumes between shutdown and startup are dropped | Trust every resumed/paused pair | Android documents that events after a shutdown have no reliable end. |
| An "open" merges same-app sessions less than 2 s apart | Count every resume | Moving between screens of an app is not opening it again. |
| Week built from calendar dates | `start + Duration(days: 7)` | Clock changes make weeks of 167 h and 169 h. |
| First pickup ignores unlocks before 04:00 | First unlock after midnight | Late-night use belongs to the evening before, not to the morning. |
| Notifications: new keys only, skip ongoing, foreground-service and group summaries | Count every `onNotificationPosted` | Updates re-post the same key; progress and media notifications would dominate the count. |
| Video time from MediaSession states | Accessibility on video players | Same notification access, no screen reading. Misses inline feed videos, which is acknowledged. |
| Ads via opt-in accessibility, six apps, label heuristic, names only | Not at all, or screenshots and OCR | It is the only way to answer "what did I see", which is Aurendor's subject. Kept as narrow as possible and off by default. |
| `<queries>` for launcher apps | `QUERY_ALL_PACKAGES` | Play restricts the broad permission; launchable apps are what a user calls "installed". |
| Removals from broadcast plus snapshot diff | Broadcast only | The broadcast misses removals while the app is stopped or before it first ran a snapshot; the diff catches them, flagged as approximate. |
| Usage events cross the bridge as typed arrays and one string table | One Pigeon object per event | About 35,000 events per report. With the type filter and week-only ranges for the other tables, loading went from about 340 ms to 200 ms on the first open and 70 to 120 ms after, with no change to the Dart rules. |
| Delete restarts each live source from now | Clear the cursors too | Clearing them made the next sync re-import the week Android still keeps, and showed sources that were still recording as switched off. |
| No `INTERNET` permission, enforced with `tools:node="remove"` | Promise not to send data | A missing permission is a guarantee the OS enforces; a promise is not. |
| No high scores | Guess from notifications or game names | There is no source. Saying so is more honest than a fake number. |
| EUPL-1.2 licence | MIT | European open-source licence, consistent with a sovereignty-minded product. |
