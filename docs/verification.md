# Verification — 2026-11-17

Version 1.1.1+3, verified locally on Windows with Flutter 3.47.0 / Dart 3.13.0.

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| Dart formatting (`lib`, `test`, `integration_test`) | Clean |
| `flutter test` | 214 tests passed |
| Android integration test | Passed on Android 17 / API 37 emulator |
| `flutter build apk --release` | Passed |
| APK signature verification | Passed, APK Signature Scheme v2 |
| Release install and launch | Passed; all four sections inspected |

The unit/widget suite includes the retained Book, Manga and Film suites plus anime round-trips,
foreign-type rejection, history, save failure/recovery, merge/replace, snapshots, trash,
route preservation, shared settings, narrow layouts and large text. Shared interface tests
verify the same screen, row, theme, search, data actions, statistics and editor controls in all
four sections, plus independent page/chapter/viewing progress actions.
Anime-Planet coverage includes six statuses, fractional ratings, dates, gzip/BOM, input limits,
malformed/mixed list rejection, persistent import, metadata-preserving merge and snapshot recovery.
Windows visual baselines cover all four sections in light and dark, their editors and the
existing Film sheets.

The cleanup audit removed 11 superseded Manga/Film screen, widget and forwarding files
(3,262 Dart lines), plus the unused PlexSerif and Grotesk font bundles (673,852 bytes).
All 79 remaining Dart files in `lib` are reachable from the app entry point.
Manga/Film interaction and large-library tests now exercise the shared library screen.
The current library/editor visual baselines are unchanged; Film sheet baselines
now show the shared library behind them. All 214 unit/widget tests still pass.

The Android test uses temporary on-device libraries and an isolated manga preference key.
It checks episode progress, independent book/manga/film fields, persistence after reopening,
typed backup rejection, navigation and native channel registration.
It also imports an Anime-Planet anime fixture from a real device file through the preview/merge
flow and checks episodes, half stars, rewatches and date precision after reopening the store.
The final release was installed separately and cold-opened in Anime, then switched through
Film, Manga and Books using the native navigation channel.

The release is a universal APK for arm64-v8a, armeabi-v7a and x86_64, with minimum API 24,
target API 36 and compile SDK 37. It uses local development signing.
Checksums are in `dist/SHA256SUMS.txt` beside the delivered APK and source archive.

Physical-device authentication and completing the Android system file-picker dialogs were not
automated. The existing implementations are retained. No GitHub publication or cloud deployment
was performed.
