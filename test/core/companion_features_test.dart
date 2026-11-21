import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_library.dart';
import 'package:companion/books/models/book.dart';
import 'package:companion/books/models/reading_session.dart';
import 'package:companion/books/services/book_lookup.dart';
import 'package:companion/books/services/library_model.dart';
import 'package:companion/books/services/storage_service.dart';
import 'package:companion/books/services/theme_notifier.dart';
import 'package:companion/core/companion_backup.dart';
import 'package:companion/core/automatic_backup.dart';
import 'package:companion/core/companion_data.dart';
import 'package:companion/core/physical_collection.dart';
import 'package:companion/film/app_state.dart' as film;
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/models/viewing.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/manga/app_state.dart' as manga;
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends ThemeNotifier {
  _Settings({required super.storage});
  @override
  Future<void> applyPrivacy() async {}
}

class _Anime extends AnimeLibrary {
  _Anime(super.directory);
  bool failNextRestore = false;
  @override
  Future<void> restoreCompanion(Map<String, dynamic> state) async {
    if (failNextRestore) {
      failNextRestore = false;
      throw const FileSystemException('Disk unavailable');
    }
    await super.restoreCompanion(state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CompanionData data;
  late CompanionBackup backup;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LibraryModel.platform, (_) async => null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('companion-features-');
    final storage = StorageService(
      directory: Directory('${directory.path}/books'),
    );
    final books = LibraryModel(storage: storage)..autoSnapshots = false;
    final settings = _Settings(storage: storage);
    await books.load();
    await settings.load();
    data = CompanionData(
      books: books,
      settings: settings,
      mangaLibrary: manga.AppState(MangaStore(prefs)),
      filmLibrary: film.AppState(await ShelfStore.open(memoryOnly: true)),
      anime: _Anime(Directory('${directory.path}/anime')),
      preferences: prefs,
    );
    backup = CompanionBackup(data);
  });
  tearDown(() async {
    data.dispose();
    data.books.dispose();
    data.settings.dispose();
    data.mangaLibrary.dispose();
    data.filmLibrary.dispose();
    data.anime.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> seed() async {
    final cover = await data.books.storage.storeCover(
      Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 12))),
    );
    await data.books.addBook(
      Book(
        id: 'book',
        title: 'A Wizard of Earthsea',
        coverImagePath: cover,
        collection: const PhysicalCollection(
          ownership: Ownership.owned,
          shelf: 'Study',
          lentTo: 'Ana',
        ),
        quotes: const [BookQuote(id: 'q', text: 'A remembered passage')],
        sessions: [
          ReadingSession(
            id: 's',
            startDate: DateTime(2025, 1, 1),
            endDate: DateTime(2025, 1, 3),
            rating: 5,
          ),
        ],
      ),
    );
    await data.books.addBook(
      Book(
        id: 'deleted-book',
        title: 'Book in trash',
        deletedAt: DateTime.now(),
      ),
    );
    await data.mangaLibrary.add(
      MangaEntry(
        id: 'manga',
        title: 'Witch Hat Atelier',
        addedAt: 1,
        lastUpdated: 1,
        collection: const PhysicalCollection(
          ownership: Ownership.owned,
          totalVolumes: 5,
          volumes: [1, 2, 4],
        ),
        history: const [ReadEvent(at: 1735776000000, from: 0, to: 3)],
      ),
    );
    final movie = ShelfEntry.blank()
      ..title = 'Arrival'
      ..runtime = 116;
    movie.addViewing(
      Viewing(
        at: DateTime(2025, 1, 2).millisecondsSinceEpoch,
        precision: 'day',
      ),
    );
    await data.filmLibrary.add(movie);
    final removed = ShelfEntry.blank()..title = 'Film in trash';
    await data.filmLibrary.add(removed);
    await data.filmLibrary.remove(removed.id);
    await data.anime.save(
      AnimeEntry(id: 'anime', title: 'Frieren', totalEpisodes: 28),
    );
    await data.anime.importEntries([
      AnimeEntry(id: 'anime', title: 'Frieren', totalEpisodes: 28),
    ], replace: true);
    await data.anime.save(
      AnimeEntry(id: 'deleted-anime', title: 'Anime in trash'),
    );
    await data.anime.remove('deleted-anime');
    await data.settings.update({'theme': 'dark', 'goalTarget': 24});
    await data.mangaLibrary.restoreSort(manga.SortMode.title);
  }

  test('complete backup round-trips all libraries, covers, collection, trash, settings and snapshots', () async {
    await seed();
    await data.books.storage.snapshot(data.books.allBooks);
    final bytes = await backup.create();
    final preview = backup.decode(bytes);
    expect(preview.bookSnapshots, hasLength(1));
    expect(preview.counts, {'Books': 2, 'Manga': 1, 'Film': 1, 'Anime': 1});
    expect(preview.books.covers, isNotEmpty);
    expect(preview.filmState['trash'], hasLength(1));
    expect(preview.animeState['trash'], hasLength(2));
    expect(preview.animeState['snapshot'], isNotNull);
    await data.books.restoreCompanion(ImportData([]));
    await data.mangaLibrary.restoreCompanion([]);
    await data.filmLibrary.restoreCompanion({
      'entries': [],
      'trash': [],
      'snapshot': null,
      'snapshotAt': null,
    });
    await data.anime.importEntries([], replace: true);
    await data.settings.update({'theme': 'light', 'goalTarget': 2});
    await backup.restore(preview);
    expect(data.books.allBooks, hasLength(2));
    expect(
      await File(data.books.books.single.coverImagePath!).exists(),
      isTrue,
    );
    expect(data.books.books.single.collection.lentTo, 'Ana');
    expect(data.books.books.single.quotes.single.text, 'A remembered passage');
    expect(data.mangaLibrary.entries.single.collection.missingVolumes, [3, 5]);
    expect(data.filmLibrary.entries.single.plays, 1);
    expect(data.filmLibrary.trash, hasLength(1));
    expect(data.anime.entries.single.title, 'Frieren');
    expect(data.anime.hasSnapshot, isTrue);
    expect(data.settings.mode.name, 'dark');
    expect(data.settings.goalTarget, 24);
    expect(data.mangaLibrary.sortMode, manga.SortMode.title);
    expect(await backup.hasRecovery(), isTrue);
    expect(await data.books.storage.snapshots(), hasLength(1));
    await data.books.load();
    await data.anime.load();
    await data.mangaLibrary.reloadFromDisk();
    expect(data.books.books.single.collection.shelf, 'Study');
    expect(data.anime.entries.single.title, 'Frieren');
    expect(data.mangaLibrary.entries.single.collection.volumes, [1, 2, 4]);
  });

  test(
    'tampered and unsafe complete backups are rejected before mutation',
    () async {
      await seed();
      final bytes = await backup.create();
      final archive = ZipDecoder().decodeBytes(bytes);
      final modified = Archive();
      for (final file in archive.files) {
        final content = file.name == 'manga.json'
            ? utf8.encode('[]')
            : file.content;
        modified.addFile(ArchiveFile(file.name, content.length, content));
      }
      expect(
        () => backup.decode(Uint8List.fromList(ZipEncoder().encode(modified))),
        throwsFormatException,
      );
      modified.addFile(ArchiveFile('../outside.json', 2, utf8.encode('{}')));
      expect(
        () => backup.decode(Uint8List.fromList(ZipEncoder().encode(modified))),
        throwsFormatException,
      );
      expect(data.mangaLibrary.entries.single.title, 'Witch Hat Atelier');
      expect(
        () => backup.decode(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    },
  );

  test('automatic preparation includes all four libraries and covers and restores unchanged', () async {
    await seed();
    await data.books.storage.snapshot(data.books.allBooks);
    final target = File('${directory.path}/automatic/ready.companion');
    await AutomaticBackup.prepare(data, target.path);
    final preview = backup.decode(await target.readAsBytes());
    expect(preview.counts, {'Books': 2, 'Manga': 1, 'Film': 1, 'Anime': 1});
    expect(preview.books.covers, isNotEmpty);
    expect(preview.bookSnapshots, isNotEmpty);
    await data.mangaLibrary.restoreCompanion([]);
    await backup.restore(preview);
    expect(data.mangaLibrary.entries.single.title, 'Witch Hat Atelier');
    expect(data.books.books.single.collection.lentTo, 'Ana');
    expect(data.anime.entries.single.title, 'Frieren');
  });

  test(
    'failed automatic preparation preserves an existing good archive',
    () async {
      await seed();
      final target = File('${directory.path}/ready.companion');
      await AutomaticBackup.prepare(data, target.path);
      final before = await target.readAsBytes();
      data.books.saveError = 'Disk full';
      await expectLater(
        AutomaticBackup.prepare(data, target.path),
        throwsFormatException,
      );
      expect(await target.readAsBytes(), before);
      data.books.saveError = null;
    },
  );

  test('a later restore failure rolls every earlier library back', () async {
    await seed();
    final preview = backup.decode(await backup.create());
    await data.books.addBook(Book(id: 'new', title: 'Keep this book'));
    await data.mangaLibrary.restoreCompanion([]);
    await data.settings.update({'theme': 'light'});
    (data.anime as _Anime).failNextRestore = true;
    await expectLater(backup.restore(preview), throwsFormatException);
    expect(data.books.books.map((b) => b.title), contains('Keep this book'));
    expect(data.mangaLibrary.entries, isEmpty);
    expect(data.settings.mode.name, 'light');
    expect(
      await (await data.books.storage.file('companion-restore-pending.json'))
          .exists(),
      isFalse,
    );
  });

  test(
    'an interrupted restore recovers the durable previous libraries',
    () async {
      await seed();
      final bytes = await backup.create();
      await (await data.books.storage.file(
        'companion-before-restore.companion',
      )).writeAsBytes(bytes, flush: true);
      await (await data.books.storage.file('companion-restore-pending.json'))
          .writeAsString('{"pending":true}', flush: true);
      await data.books.restoreCompanion(ImportData([]));
      await data.mangaLibrary.restoreCompanion([]);
      await backup.recoverInterruptedRestore();
      expect(data.books.books.single.title, 'A Wizard of Earthsea');
      expect(data.mangaLibrary.entries.single.title, 'Witch Hat Atelier');
    },
  );

  test('complete restore can recover an unreadable library', () async {
    await seed();
    final preview = backup.decode(await backup.create());
    await (await data.books.storage.file('books.json'))
        .writeAsString('damaged');
    data.books.loadFailed = true;
    await expectLater(backup.create(), throwsFormatException);
    await backup.restore(preview);
    expect(data.books.loadFailed, isFalse);
    expect(data.books.books.single.title, 'A Wizard of Earthsea');
    final files = await (await data.books.storage.directory).list().toList();
    expect(files.any((f) => f.path.contains('.damaged-')), isTrue);
  });

  test('diary combines explicit progress while preserving coarse and unknown dates', () async {
    await data.books.addBook(
      Book(
        id: 'b',
        title: 'Reading',
        sessions: [
          ReadingSession(
            id: 's',
            startDate: DateTime(2025, 5, 2),
            precision: DatePrecision.approximate,
            endDate: DateTime(2025, 5, 8),
            progress: [
              ProgressEntry(date: DateTime(2025, 5, 3), page: 40, fromPage: 20),
              ProgressEntry(date: DateTime(2025, 5, 3), page: 35, fromPage: 40),
            ],
          ),
        ],
      ),
    );
    final movie = ShelfEntry.blank()..title = 'Coarsely remembered';
    movie.addViewing(
      Viewing(at: DateTime(2025).millisecondsSinceEpoch, precision: 'year'),
    );
    movie.addViewing(Viewing.undated());
    await data.filmLibrary.add(movie);
    await data.anime.save(
      AnimeEntry(id: 'a', title: 'Year only', finishedDate: '2025'),
    );
    final events = data.diary();
    expect(
      events
          .where((e) => e.hasDay)
          .map((e) => e.amount)
          .reduce((a, b) => a + b),
      15,
    );
    expect(events.where((e) => e.precision == 'month'), hasLength(2));
    expect(events.where((e) => e.precision == 'year'), hasLength(2));
    expect(events.where((e) => e.date == null), hasLength(1));
    expect(events.where((e) => e.title == 'Year only').single.hasDay, isFalse);
  });

  test('series episode steps persist in the diary and backup', () async {
    final series = ShelfEntry.blank()
      ..title = 'A series'
      ..kind = 'series'
      ..episodes = 3;
    await data.filmLibrary.add(series);
    await data.filmLibrary.advanceEpisode(series, 1);
    await data.filmLibrary.advanceEpisode(series, 1);
    await data.filmLibrary.advanceEpisode(series, -1);
    expect(
      data
          .diary()
          .where((e) => e.unit == 'episodes')
          .fold(0, (int sum, e) => sum + e.amount),
      1,
    );
    final preview = backup.decode(await backup.create());
    expect(
      (preview.filmState['entries'] as List).single['episodeHistory'],
      hasLength(3),
    );
  });

  test('rediscovery explains old, nearly finished and paused entries, excluding recent and completed ones', () async {
    final now = DateTime(2026, 11, 20);
    final old = DateTime(2024, 11, 1);
    await data.books.addBook(
      Book(
        id: 'paused',
        title: 'Paused book',
        status: BookStatus.onHold,
        totalPages: 100,
        createdAt: old,
        updatedAt: old,
        sessions: [ReadingSession(id: 's', startDate: old, currentPage: 80)],
      ),
    );
    await data.anime.save(
      AnimeEntry(
        id: 'close',
        title: 'Almost done',
        totalEpisodes: 12,
        currentEpisode: 10,
        status: AnimeStatus.watching,
        addedAt: old.millisecondsSinceEpoch,
        updatedAt: old.millisecondsSinceEpoch,
      ),
    );
    await data.anime.save(
      AnimeEntry(
        id: 'recent',
        title: 'Recent',
        totalEpisodes: 12,
        currentEpisode: 10,
        status: AnimeStatus.watching,
        addedAt: old.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      ),
    );
    await data.anime.save(
      AnimeEntry(
        id: 'done',
        title: 'Done',
        status: AnimeStatus.completed,
        addedAt: old.millisecondsSinceEpoch,
        updatedAt: old.millisecondsSinceEpoch,
      ),
    );
    final items = data.rediscover(now: now);
    expect(items.map((e) => e.id).toSet(), {'paused', 'close'});
    expect(
      items.firstWhere((e) => e.id == 'paused').reasons,
      contains('You paused this at 80%'),
    );
    expect(
      items.firstWhere((e) => e.id == 'close').reasons,
      contains('Only 2 episodes left'),
    );
  });

  test(
    'collection ranges, missing volumes, loans and legacy defaults round-trip',
    () {
      expect(PhysicalCollection.parseVolumes('1-3, 3, 5'), [1, 2, 3, 5]);
      expect(
        () => PhysicalCollection.parseVolumes('8-2'),
        throwsFormatException,
      );
      expect(
        () => PhysicalCollection.parseVolumes('1-99999999'),
        throwsFormatException,
      );
      final collection = PhysicalCollection.fromJson(
        const PhysicalCollection(
          ownership: Ownership.borrowed,
          borrowedFrom: 'Mira',
          shelf: 'Desk',
          totalVolumes: 5,
          volumes: [1, 3, 5],
        ).toJson(),
      );
      expect(collection.missingVolumes, [2, 4]);
      expect(collection.borrowedFrom, 'Mira');
      expect(
        Book.fromJson({'id': 'old', 'title': 'Legacy'}).collection.isTracked,
        isFalse,
      );
      expect(
        MangaEntry.fromJson({'title': 'Legacy'}).collection.isTracked,
        isFalse,
      );
    },
  );

  test(
    'ISBN checks validate both formats and normalize scanned values',
    () async {
      expect(BookLookup.validIsbn('978-0-14-032872-1'), isTrue);
      expect(BookLookup.validIsbn('0-8044-2957-X'), isTrue);
      expect(BookLookup.validIsbn('9780140328722'), isFalse);
      expect(BookLookup.validIsbn('1234567890128'), isFalse);
      final channel = const MethodChannel('io.github.yuuge7.companion/isbn');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => '9780140328721');
      expect(await BookLookup().scanIsbn(), '9780140328721');
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await BookLookup().scanIsbn(), isNull);
      messenger.setMockMethodCallHandler(channel, (_) async => '123');
      await expectLater(BookLookup().scanIsbn(), throwsFormatException);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  test('numeric titles use title search and ISBN metadata uses the selected edition', () async {
    final requests = <Uri>[];
    final lookup = BookLookup(
      fetch: (uri) async {
        requests.add(uri);
        return Uint8List.fromList(
          utf8.encode(
            jsonEncode(
              uri.path == '/search.json'
                  ? {
                      'docs': [
                        {
                          'title': '1984',
                          'author_name': ['George Orwell'],
                          'edition_key': ['OL1M'],
                        },
                      ],
                    }
                  : {
                      'ISBN:9780140328721': {
                        'title': 'Fantastic Mr. Fox',
                        'authors': [
                          {'name': 'Roald Dahl'},
                        ],
                        'identifiers': {
                          'isbn_13': ['9780140328721'],
                        },
                        'publishers': [
                          {'name': 'Puffin'},
                        ],
                        'publish_date': 'October 1, 1988',
                        'number_of_pages': 96,
                        'cover': {
                          'large':
                              'https://covers.openlibrary.org/b/id/1-L.jpg',
                        },
                      },
                    },
            ),
          ),
        );
      },
    );
    expect((await lookup.search('1984')).single.title, '1984');
    expect(requests.single.queryParameters['title'], '1984');
    final edition = (await lookup.search('978-0-14-032872-1')).single;
    expect(edition.author, 'Roald Dahl');
    expect(edition.isbn, '9780140328721');
    expect(edition.pages, 96);
    expect(edition.year, 1988);
    expect(edition.publisher, 'Puffin');
    expect(edition.coverUrl, 'https://covers.openlibrary.org/b/id/1-L.jpg');
    await expectLater(lookup.search('9780140328722'), throwsFormatException);
    expect(requests, hasLength(2));
  });
}
