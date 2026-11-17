# Anime-Planet anime import

Available in Companion 1.1.1. In **Anime → tools (⋮) → Import & export → Import backup**,
choose your Anime-Planet **anime** JSON export (plain `.json` or gzipped `.gz`).
Review the preview, then choose Merge or Replace. Imports stay entirely in Anime.
The complete export from Companion remains Anime Companion JSON; no universal format was added.

| Anime-Planet field | Anime Companion |
| --- | --- |
| `name` | Title; stable import ID based on normalized title |
| `eps` | Episodes watched |
| `status` | Watched → Completed; Watching → Watching; Want to watch → Plan to watch; Stalled → On hold; Dropped → Dropped; Won't watch → Won't watch |
| `rating` | Five-star score, preserving half stars |
| `times` | Rewatches = max(watch count − 1, 0) |
| `started`, `completed` | Start/finish dates, retaining year/month/day precision; unknown dates stay unknown |

The standard export does not provide format, total episode count or runtime. New imports
use **Unspecified** format and unknown totals/runtime; you can fill these in with Edit title.
A completed list entry does not manufacture an episode total, runtime or dated viewing history.
When merging a matching title, existing format, runtime, notes, tags and dated progress history
are kept. Episodes are never converted into movie minutes. A unique title match can connect an
AP record to an existing anime; ambiguous names remain separate for review in the preview.

Malformed, duplicate, empty/untyped, manga and mixed lists are rejected before any changes.
Imports are limited to 10 MB after decompression and 20,000 entries. Merge/Replace retains the
existing pre-import snapshot and trash recovery behavior. Replace uses only the file's data.

The supported field names follow the retained Manga Companion importer and the anime-specific
mapping in [anitransfer's converter](https://github.com/wolfborg/anitransfer/blob/master/anitransfer.py#L678-L715).
The fixture in `test/anime/fixtures/anime-planet-anime.json` is synthetic and covers all six statuses,
dates, numeric/string fields, null values and half stars. Unit/widget tests cover parsing, compression
limits, type rejection, save/reload, merge/recovery and editing without rounding imported ratings.
The Android integration check reads a fixture file on-device, opens the import preview, merges it
and verifies the saved data after reopening the store.
