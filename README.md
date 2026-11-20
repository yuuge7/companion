# Companion

A local Android library for books, manga, films and anime, built with Flutter.
Companion brings four independent collections into one app with shared navigation,
search, filters, ratings and backup tools.

[Download releases](https://github.com/yuuge7/companion/releases) ·
[Report an issue](https://github.com/yuuge7/companion/issues) ·
[MIT license](LICENSE)

## Features

- **Books:** reading progress, audiobook listening time, editions, rereads, quotes
  and reading sessions. Complete backups include cover images.
- **Manga:** chapter progress, rereads and reading history, with imports from
  MyAnimeList, Anime-Planet and Mihon/Tachiyomi.
- **Film:** movie and series libraries, viewing logs, episode/season progress,
  statistics and optional folder backups.
- **Anime:** episode and movie progress, rewatches, release metadata, half-star
  ratings, import previews and recovery snapshots.
- **Across your libraries:** an activity diary with a tappable calendar heatmap,
  combined year in review, and backlog rediscovery with reasons to return.
- **Faster book adding:** search Open Library by title or ISBN, or scan an ISBN on
  Android. Review the edition, cover and metadata before filling the book editor.
- **Physical collection:** owned and borrowed books and manga, shelf locations,
  loan recipients, volume lists and missing volumes.
- **Complete Companion backup:** one `.companion` file for all four libraries,
  book cover files, histories, collection details, trash, recovery snapshots and
  shared settings. Restore previews, checksums and a durable recovery copy protect
  the restore flow.
- **Shared experience:** light/dark/system themes, optional Material You colors,
  app lock, recent-app preview protection, large-text support and adaptive navigation.
- **Home-screen widgets:** Current book, Manga reading and What fits tonight.

The four libraries retain separate data models, storage and backup formats.
Switching sections preserves each library's navigation, search and filters.
Library data stays on the device; poster and cover images can be fetched online.
Manga entries show their last edit date on the shelf and in details. Film **Recent**
sorts by the latest recorded viewing, with undated entries last; **Last edited**
and **Date added** are separate sort choices.
The calendar button in any library opens Activity, Rediscover and Collection.
Shared Settings also links to these tools and Complete Companion backup.

The diary uses recorded progress, reading sessions and viewing dates. Approximate
and year-only dates stay outside the daily heatmap; the year review includes them
only at their recorded precision. Imported undated progress is never assigned to
an invented day. Series episode steps are logged from this version onward.
Rediscovery excludes recently active, finished and dropped entries.

Open a book or manga editor and expand **Physical collection** to record ownership,
a shelf, who lent it to you or who you lent it to, and volume ranges such as
`1-4, 7, 9`. The Collection view can filter loans and missing volumes.

Book lookup uses the [Open Library APIs](https://openlibrary.org/developers/api).
Android ISBN scanning uses the [Google code scanner](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner)
and requires Google Play services. Manual title and ISBN entry remain available.

### Import and export

| Library | Import | Export |
| --- | --- | --- |
| Books | `.bcbackup`, legacy/schema-2 book JSON, Goodreads CSV | Complete `.bcbackup`, JSON, CSV, HTML, PDF |
| Manga | Manga JSON, MyAnimeList manga XML, Anime-Planet manga JSON/HTML, Mihon/Tachiyomi backups | Manga JSON, CSV |
| Film | Screen Companion schema-2 JSON and legacy film arrays | Film JSON, CSV |
| Anime | Anime Companion schema-1 JSON, Anime-Planet anime JSON/HTML, MyAnimeList anime XML; gzip supported | Anime JSON, CSV |

For an all-library round trip, open **Settings → Complete Companion backup**.
Choose **Save complete backup** to export a `.companion` archive. To restore,
choose a file, review the counts and then select **Replace libraries and restore**.
This replaces all four libraries and shared settings, including privacy settings.
The prior libraries are saved locally and can be reviewed from the same screen;
an interrupted restore recovers them on the next startup. Keep an exported copy
off the device. Backups include book cover files; manga and poster image URLs are
preserved. Complete archives are limited to 150 MB; per-library exports remain
available for larger collections. Trash keeps its existing 30-day retention.

Use each library's backup format for an individual round trip. CSV is a report for
Manga, Film and Anime. The Manga and Anime import pickers accept files regardless of their extension or
Android MIME label, including `export-manga-username.json` and
`export-anime-username.json` saved as `.html`. HTML-wrapped JSON and export tables
with named title, status and chapter/episode columns are read as data; saved login
pages are rejected. Import previews stay within the library that opened them.

Import a backup in its matching section; Companion rejects
recognizable backups belonging to another library.

## Install

Download `Companion-vX.Y.apk` from [Releases](https://github.com/yuuge7/companion/releases)
and open it on an Android device. Allow installation from your browser or file
manager when Android prompts. Android 7.0 (API 24) or newer is required. The universal
APK supports arm64-v8a, armeabi-v7a and x86_64.

Releases from `main` are stable releases. Pull request builds are marked as
prereleases. Each release includes an APK, `CHANGELOG.md` generated from commit
messages, and `SHA256SUMS.txt`.

Updates signed with the same key preserve the installed app's data. Older local
builds used development signing and cannot be updated in place with this new
release identity. Export all four libraries before replacing an installation with
a different signing certificate.

### Move from the original apps

Export a complete `.bcbackup` from Book Companion and JSON backups from Manga
Companion and Screen Companion. Install Companion and import each backup in the
corresponding section. Verify the imported libraries before removing the old apps.
Companion's application ID is `io.github.yuuge7.companion`, so it installs alongside
the original apps.

## Development setup

### Requirements

| Tool | Version |
| --- | --- |
| Flutter | **3.47.0**, stable |
| Dart | **3.13**, bundled with Flutter |
| JDK | **17** or newer; CI uses 17 |
| Android SDK | Platform **37**, Build Tools **36.0.0**, platform-tools and Flutter's required NDK |
| Node.js | **22** for release helpers and their tests |
| Python | **3.10+** for signing helpers; no third-party packages required |
| Git | A current installation |

Install Flutter and Android Studio with the Android SDK. Put `flutter`, `dart`,
`java`, `keytool`, `node` and `python` on your path. Then clone the repository:

```sh
git clone https://github.com/yuuge7/companion.git
cd companion
flutter doctor
flutter doctor --android-licenses
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id>
```

If Flutter selects the wrong Java or Android SDK installation, configure them:

```sh
flutter config --jdk-dir="<path-to-jdk>"
flutter config --android-sdk="<path-to-android-sdk>"
```

Use the SDK Manager to install Android platform 37 and Build Tools 36.0.0. Flutter
and Gradle resolve the NDK version declared by the pinned Flutter SDK. The committed
`pubspec.lock` keeps package resolution consistent across machines.

### Verify changes

```sh
flutter analyze
dart format --output=none --set-exit-if-changed lib test integration_test
flutter test --reporter expanded
node --test scripts/release.test.cjs
python -m unittest discover -s scripts -p "test_*.py"
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Without local
signing configuration, a contributor's release build uses development signing.
Contributors can build and test without the maintainer's private key.

Golden images are captured on Windows with the pinned Flutter version. Use Windows
for pixel comparisons; Linux and macOS may render text differently. Update goldens
only when a visual change is intentional and inspect the resulting images.

On a disposable Android emulator, run the integration suite:

```sh
flutter test integration_test/companion_test.dart -d emulator-5554
```

The suite covers section navigation, persistence, typed imports and native
channels. Use an emulator or test device without valuable library data.

### Project layout

```text
lib/main.dart       App startup and adaptive shell
lib/core/           Shared UI, persistence helpers, diagnostics and app lock
lib/books/          Book library, reading progress and backups
lib/manga/          Manga library and importers
lib/film/           Film/series library and viewing history
lib/anime/          Anime library, import previews and recovery
android/            Android app, widgets and platform channels
test/               Unit, widget, regression and Windows golden tests
integration_test/   On-device integration tests
scripts/            Release planning, publishing, signing and helper tests
.github/workflows/  Build checks and release publication
```

### Contribute

Create a feature branch, keep changes focused and run the checks above before
opening a pull request against `main`. Include a description of the behavior change
and relevant screenshots for UI work. Cover meaningful changes to persistence,
imports, backups or native channels with regression tests.

Keep the four libraries' schemas separate. Shared presentation belongs in
`lib/core`; library-specific behavior belongs in its own module. Preserve existing
backup compatibility and app-lock privacy behavior. Use clear commit subjects such
as `fix: preserve anime import dates` or `feat: add manga shelf filters` because
commit subjects become the release changelog.

## Automatic GitHub releases

`Companion CI` runs for every push to `main`, every opened/reopened/updated PR
targeting `main`, and manual runs. It checks the app on Windows, assigns the version
and builds an unsigned release APK on Linux. After a successful run, `Companion
release` verifies the APK's application ID and version, signs it with the permanent
key, and publishes a new release named **Companion vX.Y**.

PR source is built without secrets. The signing workflow runs helpers from the
default branch and treats the downloaded APK as data. Fork PRs follow the same path;
GitHub may require a maintainer to approve their CI run first. Both workflow files
must be present on the repository's default branch (`main`) to enable publication.

### Versioning and release history

The local starting version is **1.2.0+4**. `scripts/release.cjs` allocates versions
from the CI workflow's unique run number: run 1 is `Companion v1.2` with Android
version `1.2.0+4`, run 2 is `Companion v1.3` / `1.3.0+5`, and so on. If the existing
workflow already has runs, numbering continues from its current run number.

Each push or PR update receives a new version. Failed runs can leave gaps. A rerun
keeps the original version; a published release is left unchanged. Tags are never
force-moved and published assets are never replaced. CI updates `pubspec.yaml` in
its workspace and does not create version-bump commits in the repository.

Keep the `SERIES` offsets in `scripts/release.cjs` fixed. Do not delete/recreate the
CI workflow to reset its run counter. To start a new major series, increase
`SERIES.major` and update the local pubspec version; keep the build-number offset
so Android version codes continue increasing.

The changelog lists commit subjects and links since the previous stable release.
PR changelogs list commits relative to `main`; the first stable release includes
the existing history. Releases are published only after the APK, changelog and
checksums have all uploaded. An interrupted draft can be completed by a rerun
when its existing assets match; differing assets cause a failure instead of an
overwrite.

### Repository configuration

In **Settings → Secrets and variables → Actions**, create these repository secrets:

| Secret | Local source |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Entire contents of `companion-release.jks.base64` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` in `signing-secrets.properties` |
| `ANDROID_KEY_ALIAS` | `keyAlias` in `signing-secrets.properties` (`companion`) |
| `ANDROID_KEY_PASSWORD` | `keyPassword` in `signing-secrets.properties` |

Copy only each property's value, without the `keyPassword=` / `storePassword=`
prefix or surrounding quotes. The store and private-key passwords are separate
and can differ. `python scripts/signing.py configure` checks both passwords before
refreshing the local configuration and base64 export.

If signing fails with `UnrecoverableKeyException` or `Cannot recover key`, update
`ANDROID_KEY_PASSWORD` from the original file's `keyPassword` value, then rerun the
failed **Companion release** workflow. Exporting the certificate can succeed with
the store password even when the private-key password is wrong. Signing failures
include the failed tool operation and diagnostics with the signing secrets redacted.

Enable GitHub Actions and allow the actions used by the workflows. The publishing
workflow requests `contents: write` for releases/tags and `actions: read` for the
build artifact; no personal token is needed for ordinary code changes.

For releases of PRs that modify `.github/workflows`, GitHub also requires permission
to write workflows when tagging that source commit. Add an optional `RELEASE_TOKEN`
secret containing a repository-scoped fine-grained token with **Contents: read and
write** and **Workflows: read and write**. The publisher uses it only for release
publication; it is never supplied to PR builds.

## Preserve the signing identity

This checkout's permanent RSA signing key is **`companion-release.jks` in the
project root**, with alias `companion`. Its certificate SHA-256 is:

```text
83091746f0f31e1889dafccad47b14c15d9ec40e3d332c5e640852ddaa296d6a
```

The passwords are in `signing-secrets.properties`. Local Gradle configuration is
in `android/key.properties`; a base64 export for GitHub is in
`companion-release.jks.base64`. All four files are ignored by Git. The keystore and
password file are the essential backup: keep encrypted copies in at least two
secure locations. Never attach them to issues, PRs or releases. Losing the signing
key prevents future updates from matching this app's existing signature.

### Move maintainer signing to another machine

1. Complete the development setup and clone the repository on the new machine.
2. Transfer **`companion-release.jks` and `signing-secrets.properties`** securely
   into the new checkout's root directory.
3. Run `python scripts/signing.py configure`. It checks the key, recreates
   `android/key.properties` and the base64 export, and prints the certificate
   fingerprint. Confirm it matches the fingerprint above.
4. Run `flutter build apk --release` to produce an APK signed with the same key.

The configuration uses a path relative to the project root, so moving between
Windows, macOS and Linux does not require editing the keystore path. Set
`ANDROID_HOME` to your Android SDK if using the standalone CI signing helper.
Repository secrets remain configured in GitHub and do not need to be recreated
when you change computers.

`python scripts/signing.py generate` creates a new identity only when none of the
signing files exist. It is for a new app identity, not for restoring this app on
another machine. Restore the original files for every future Companion release.

## License

Companion is distributed under the [MIT license](LICENSE). Bundled fonts retain
their individual license notices in `assets/fonts`.
