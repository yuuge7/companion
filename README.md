# Companion

One Flutter Android app with four separate companions: **Books, Manga, Film and Anime**.
Switch sections using the bottom bar (or the side rail on a wide screen).
Each section remembers its navigation, search and filters while you switch.

## What is shared

- One app installation, startup, navigation and last-used section.
- One light/dark/system preference and one app lock, including recent-app preview protection.
- Common rating controls, bottom-sheet chrome, atomic file writes, diagnostics and text-file saving.
- The same library screen, rows, search, shelf controls, sort/filter toolbar, add/edit actions, statistics summary and backup screen in every section.
- The existing book, manga and film features remain in their own modules. Common plumbing does not turn their records into a generic media model.

All sections use one palette, typography, form controls and navigation theme. Material You, when enabled, applies across all sections. The shared interface is documented in [the UI contract](docs/ui-contract.md).

## What stays separate

| Section | Progress and history | Import | Export |
| --- | --- | --- | --- |
| Books | Pages, audiobook listening time, editions, reads/rereads, quotes and reading sessions | Existing `.bcbackup`, legacy/schema-2 book JSON, Goodreads CSV | `.bcbackup` with covers, book JSON, CSV, HTML, PDF |
| Manga | Chapters, rereads and reading events | Existing manga JSON, MyAnimeList **manga** XML, Anime-Planet **manga** JSON, Mihon/Tachiyomi backups | Existing manga JSON array, manga CSV |
| Film | Movie minutes, series episodes/seasons and viewing logs | Existing Screen Companion schema-2 JSON and legacy film arrays | Existing film JSON, film CSV |
| Anime | TV/OVA/ONA/special episodes, anime-movie minutes, studio/release season, rewatches and progress history | Anime Companion schema-1 JSON, Anime-Planet **anime** JSON, MyAnimeList **anime** XML, including gzip | Anime JSON, anime CSV |

CSV is a report for Manga, Film and Anime; use their JSON for a complete reimportable backup.
Books' complete backup also includes cover image bytes.
Anime JSON preserves notes, tags, ratings, release metadata, URLs, date precision and progress events.
MyAnimeList's 0–10 score is mapped to the shared five-star scale on anime import.
Anime ratings retain half stars. Anime-Planet's six anime statuses, watched episodes,
watch counts and date precision are preserved. Format, episode totals and runtime stay
unspecified when absent from its export. See [Anime-Planet import](docs/anime-planet-import.md).

There is **no universal import/export format, cross-type library, combined progress total or automatic conversion between sections**.
Recognizable foreign records and backup envelopes are rejected before importing.
Unlabelled legacy records containing only generic fields, such as a title, cannot prove their original type; import legacy files in their original section.

## Move from the old apps

1. In Book Companion, export a complete `.bcbackup` to include covers.
2. In Manga Companion, export its JSON backup.
3. In Screen Companion, export its JSON backup.
4. Install Companion, then import each file from the matching section's settings/tools.
5. Check each library before removing any old app.

Companion uses a new Android ID, `io.github.yuuge7.companion`, and installs alongside the three old apps.
Android keeps each app's private files separate, so existing libraries move through exports rather than by reading another app's storage.

Books and Film retain their existing import previews and recovery features.
Anime previews new/newer/retained entries, supports merge or replace, saves a pre-import snapshot, and keeps deleted anime in trash for 30 days.
Anime merge keeps the local ID and accepts only newer incoming changes; ties retain the local copy.
Imported episode totals do not manufacture dated viewing events or an unknown runtime.

The Current book, Manga reading and What fits tonight Android widgets are retained.
They open their own section and hide title details when the shared app lock is enabled.
Film's automatic folder backup remains **film-only**.

## Build and verify

Use Flutter **3.47.0**, Dart **3.13**, JDK 17+ and Android compile SDK 37.
Minimum Android API: 24. The lockfile is committed.

```sh
flutter pub get
flutter analyze
dart format --output=none --set-exit-if-changed lib test integration_test
flutter test
flutter build apk --release
```

The APK is produced at `build/app/outputs/flutter-apk/app-release.apk`.
Local builds use development signing unless `android/key.properties` supplies a release key.
Keep using the same signing key for future updates to this new app.

On a disposable Android emulator:

```sh
flutter test integration_test/companion_test.dart -d emulator-5554
```

The integration test uses temporary libraries and an isolated manga preference key.
It checks section navigation, real file persistence, anime progress, typed backup rejection and all native channels.
The three upstream unit/widget suites are retained under `test/books`, `test/manga` and `test/film`.
New tests cover anime persistence/recovery, every pair of foreign backup types, retained routes, shared settings, narrow screens and large text.
Visual baselines are captured on Windows with the pinned Flutter version.

## Source layout

```text
lib/main.dart        one startup and adaptive app shell
lib/core/            shared infrastructure and controls
lib/books/           Book Companion features and book-only data model
lib/manga/           Manga Companion features and manga-only data model
lib/film/            Screen Companion features and film/series model
lib/anime/           independent anime model, backup codec, store and UI
```

`lib/core/library.dart` supplies the shared interface. Each section's
`library_controller.dart` connects it to that section's existing models and operations.
These presentation adapters do not combine storage or change backup schemas.

The three supplied repos are the starting point; exact imported commits are recorded in
[Books](docs/books-source.md), [Manga](docs/manga-source.md) and [Film](docs/film-source.md).
Bundled font license texts are retained in `assets/fonts`.
