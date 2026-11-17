# Verification — 2026-11-17

Version 1.1.0+2, verified locally on Windows with Flutter 3.47.0 / Dart 3.13.0.

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| Dart formatting (`lib`, `test`, `integration_test`) | Clean |
| `flutter test` | 204 tests passed |
| Android integration test | Passed on Android 17 / API 37 emulator |
| `flutter build apk --release` | Passed |
| APK signature verification | Passed, APK Signature Scheme v2 |
| Release install and launch | Passed; all four sections inspected |

The unit/widget suite includes the retained Book, Manga and Film suites plus anime round-trips,
foreign-type rejection, history, save failure/recovery, merge/replace, snapshots, trash,
route preservation, shared settings, narrow layouts and large text. Shared interface tests
verify the same screen, row, theme, search, data actions, statistics and editor controls in all
four sections, plus independent page/chapter/viewing progress actions.
Windows visual baselines cover all four sections in light and dark, their editors and the
existing Film sheets.

The Android test uses temporary on-device libraries and an isolated manga preference key.
It checks episode progress, independent book/manga/film fields, persistence after reopening,
typed backup rejection, navigation and native channel registration.
The final release was installed separately and cold-opened in Anime, then switched through
Film, Manga and Books using the native navigation channel.

The release is a universal APK for arm64-v8a, armeabi-v7a and x86_64, with minimum API 24,
target API 36 and compile SDK 37. It uses local development signing.
Checksums are in `dist/SHA256SUMS.txt` beside the delivered APK and source archive.

Physical-device authentication and completing the Android system file-picker dialogs were not
automated. The existing implementations are retained. No GitHub publication or cloud deployment
was performed.
