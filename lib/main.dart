import 'core/companion_data.dart';
import 'core/companion_backup.dart';
import 'core/companion_backup_screen.dart';
import 'core/companion_hub.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anime/anime_library.dart';
import 'core/app_frame.dart';
import 'core/library.dart';
import 'books/library_controller.dart';
import 'manga/library_controller.dart';
import 'film/library_controller.dart';
import 'anime/library_controller.dart';
import 'books/screens/settings_screen.dart';
import 'books/services/library_model.dart';
import 'books/services/storage_service.dart';
import 'books/services/theme_notifier.dart';
import 'core/backup_type.dart';
import 'film/android_services.dart';
import 'film/app_state.dart' as film_state;
import 'film/diagnostics.dart';
import 'film/storage.dart';
import 'manga/app_state.dart' as manga_state;
import 'manga/home_widget.dart';
import 'manga/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Diagnostics.initialize();
  runApp(const CompanionStartup());
}

class CompanionDependencies {
  const CompanionDependencies({
    required this.books,
    required this.settings,
    required this.manga,
    required this.film,
    required this.anime,
    required this.preferences,
  });
  final LibraryModel books;
  final ThemeNotifier settings;
  final manga_state.AppState manga;
  final film_state.AppState film;
  final AnimeLibrary anime;
  final SharedPreferences preferences;

  static Future<CompanionDependencies> load() async {
    final preferences = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final bookStorage = StorageService(
      directory: Directory('${documents.path}/books'),
    );
    final books = LibraryModel(storage: bookStorage);
    final settings = ThemeNotifier(storage: bookStorage);
    final anime = AnimeLibrary(Directory('${support.path}/anime'));
    final mangaState = manga_state.AppState(
      MangaStore(preferences),
      onSaved: () => unawaited(refreshHomeWidget()),
    );
    final filmStore = await ShelfStore.open(
      directory: Directory('${support.path}/film'),
    );
    final filmState = film_state.AppState(filmStore);
    await Future.wait([books.load(), settings.load(), anime.load()]);
    if (!filmState.loadFailed &&
        (filmStore.needsMigration || filmStore.recovered)) {
      try {
        await filmStore.save(filmState.entries);
      } catch (error, stack) {
        Diagnostics.record(error, stack, source: 'film migration');
      }
    }
    final companion = CompanionData(
      books: books,
      settings: settings,
      mangaLibrary: mangaState,
      filmLibrary: filmState,
      anime: anime,
      preferences: preferences,
    );
    try {
      await CompanionBackup(companion).recoverInterruptedRestore();
    } finally {
      companion.dispose();
    }
    return CompanionDependencies(
      books: books,
      settings: settings,
      manga: mangaState,
      film: filmState,
      anime: anime,
      preferences: preferences,
    );
  }

  void dispose() {
    books.dispose();
    settings.dispose();
    manga.dispose();
    film.dispose();
    anime.dispose();
  }
}

class CompanionStartup extends StatefulWidget {
  const CompanionStartup({super.key});
  @override
  State<CompanionStartup> createState() => _CompanionStartupState();
}

class _CompanionStartupState extends State<CompanionStartup> {
  late Future<CompanionDependencies> _load = CompanionDependencies.load();
  CompanionDependencies? _dependencies;
  @override
  void dispose() {
    _dependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CompanionDependencies>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        _dependencies = snapshot.data;
        return CompanionApp(dependencies: snapshot.data!);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Companion',
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Companion could not open its local storage.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => setState(
                            () => _load = CompanionDependencies.load(),
                          ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, required this.dependencies});
  final CompanionDependencies dependencies;
  @override
  Widget build(BuildContext context) => CompanionFrame(
    library: dependencies.books,
    settings: dependencies.settings,
    home: CompanionShell(dependencies: dependencies),
  );
}

class CompanionShell extends StatefulWidget {
  const CompanionShell({super.key, required this.dependencies});
  final CompanionDependencies dependencies;
  @override
  State<CompanionShell> createState() => _CompanionShellState();
}

class _CompanionShellState extends State<CompanionShell> {
  static const _navigation = MethodChannel(
    'io.github.yuuge7.companion/navigation',
  );
  static const _icons = [
    Icons.menu_book_outlined,
    Icons.auto_stories_outlined,
    Icons.movie_outlined,
    Icons.live_tv_outlined,
    Icons.settings_outlined,
  ];
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final _visited = <int>{};
  late final List<LibraryController> _libraries;
  late final CompanionData _companion;
  late int _index;
  AppLifecycleListener? _lifecycle;
  CompanionDependencies get deps => widget.dependencies;
  @override
  void initState() {
    super.initState();
    _companion = CompanionData(
      books: deps.books,
      settings: deps.settings,
      mangaLibrary: deps.manga,
      filmLibrary: deps.film,
      anime: deps.anime,
      preferences: deps.preferences,
    );
    _libraries = [
      BookLibraryController(deps.books, deps.settings),
      MangaLibraryController(deps.manga),
      FilmLibraryController(deps.film),
      AnimeLibraryController(deps.anime),
    ];
    _index = CompanionMode.values.indexWhere(
      (mode) => mode.name == deps.preferences.getString('companion-mode-v1'),
    );
    if (_index < 0) _index = 0;
    _visited.add(_index);
    listenForWidgetChanges(() => unawaited(deps.manga.reloadFromDisk()));
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(deps.manga.reloadFromDisk()),
    );
    _navigation.setMethodCallHandler((call) async {
      if (call.method == 'openMode') _openMode(call.arguments as String?);
    });
    unawaited(_initialMode());
    unawaited(AndroidServices.refreshWidget());
  }

  Future<void> _initialMode() async {
    try {
      _openMode(await _navigation.invokeMethod<String>('initialMode'));
    } on MissingPluginException {
      /* Unit tests and desktop. */
    }
  }

  void _openMode(String? name) {
    final index = CompanionMode.values.indexWhere((mode) => mode.name == name);
    if (mounted && index >= 0) _select(index);
  }

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == 4) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (settingsContext) => SettingsScreen(
            includeBookSettings: false,
            libraryLinks: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Across your libraries',
                  style: Theme.of(settingsContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Activity diary & year in review'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLibraryPage(
                    settingsContext,
                    CompanionHub(data: _companion, libraries: _libraries),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Rediscover your backlog'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLibraryPage(
                    settingsContext,
                    CompanionHub(
                      data: _companion,
                      libraries: _libraries,
                      initialTab: 1,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shelves),
                  title: const Text('Physical collection'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLibraryPage(
                    settingsContext,
                    CompanionHub(
                      data: _companion,
                      libraries: _libraries,
                      initialTab: 2,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Complete Companion backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLibraryPage(
                    settingsContext,
                    CompanionBackupScreen(data: _companion),
                  ),
                ),
                const SizedBox(height: 20),
                ...CompanionMode.values.map(
                  (mode) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_icons[mode.index]),
                    title: Text('Open ${mode.label}'),
                    subtitle: Text(
                      '${mode.description}. Imports and exports stay in this section.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(settingsContext);
                      _select(mode.index);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _index = index;
      _visited.add(index);
    });
    unawaited(
      deps.preferences.setString(
        'companion-mode-v1',
        CompanionMode.values[index].name,
      ),
    );
  }

  @override
  void dispose() {
    for (final library in _libraries) {
      library.dispose();
    }
    _companion.dispose();
    _lifecycle?.dispose();
    _navigation.setMethodCallHandler(null);
    super.dispose();
  }

  Widget _branch(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    return ExcludeFocus(
      excluding: index != _index,
      child: HeroMode(
        enabled: index == _index,
        child: TickerMode(
          enabled: index == _index,
          child: ScaffoldMessenger(
            child: NavigatorPopHandler<Object?>(
              enabled: index == _index,
              onPopWithResult: (result) {
                // Disabled handlers still receive a blocked root pop. Leave
                // hidden libraries and each navigator's first route intact.
                if (index == _index) {
                  _navigators[index].currentState?.maybePop(result);
                }
              },
              child: Navigator(
                key: _navigators[index],
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => LibraryScreen(
                    controller: _libraries[index],
                    onCompanion: (context) => openLibraryPage(
                      context,
                      CompanionHub(data: _companion, libraries: _libraries),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = IndexedStack(
      index: _index,
      children: List.generate(4, (i) => _branch(i)),
    );
    final labels = [
      ...CompanionMode.values.map((mode) => mode.label),
      'Settings',
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    5,
                    (i) => NavigationRailDestination(
                      icon: Icon(_icons[i]),
                      label: Text(labels[i]),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: List.generate(
              5,
              (i) => NavigationDestination(
                icon: Icon(_icons[i]),
                label: labels[i],
                tooltip: i == 4
                    ? 'Shared appearance and privacy'
                    : CompanionMode.values[i].description,
              ),
            ),
          ),
        );
      },
    );
  }
}
