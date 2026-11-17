# One Companion interface

Every section uses the same library screen, item row, search field, shelf selector,
sort/filter toolbar, primary add button, action menu and statistics summary.
Layouts and controls do not vary by media type. Labels and available fields do.

The shared palette is slate green with wine progress marks, inherited from Books:
light ground `#E9ECE5`, dark ground `#1E2622`, primary ink `#141A18` / `#E8EBE7`,
progress `#95293C` / `#B4485C`. Typography is bundled IBM Plex Sans for names and
prose, IBM Plex Mono for measured progress. There are no section-specific themes.

All navigation and supporting forms inherit one Material theme, including optional
Material You colors. Existing feature token APIs adapt to that palette so detailed
book, manga, film and anime screens stay visually consistent.

Progress remains typed: book pages/audio, manga chapters, film viewings/series
episodes, anime episodes/movie minutes. The common row is a presentation model;
it never serializes, converts, imports or combines the underlying records.
