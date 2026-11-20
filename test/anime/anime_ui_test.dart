import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_screen.dart';
import 'package:companion/core/library.dart';
import 'package:companion/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Editing imported anime keeps half stars and the Won\'t watch shelf',
    (tester) async {
      AnimeEntry? result;
      final entry = AnimeEntry(
        title: 'Imported',
        animeFormat: AnimeFormat.unknown,
        status: AnimeStatus.wontWatch,
        rating: 4.5,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildCompanionTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await openLibraryPage<AnimeEntry>(
                    context,
                    AnimeEditor(initial: entry),
                  );
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text("Won't watch"), findsOneWidget);
      expect(find.text('Unspecified'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Rating'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
      await tester.tap(find.text('Save').first);
      await tester.pumpAndSettle();
      expect(result?.rating, 4.5);
      expect(result?.status, AnimeStatus.wontWatch);
      expect(result?.animeFormat, AnimeFormat.unknown);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large import previews fit narrow screens with keyboard and enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimeImportPreview(
            incoming: List.generate(
              530,
              (i) => AnimeEntry(id: '$i', title: 'Imported anime $i'),
            ),
            existing: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Merge anime library'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
