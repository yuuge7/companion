import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../android_services.dart';
import '../diagnostics.dart';
import 'import_sheet.dart';
import 'trash_sheet.dart';
import '../../core/file_export.dart';
import '../format.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/sheet.dart';

Future<void> showSettingsSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(state: state),
  );
}

class _SettingsSheet extends StatefulWidget {
  final AppState state;
  const _SettingsSheet({required this.state});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  /// 'export' or 'import' while that job is running; null when idle. Both
  /// rows lock during either, since both touch the same list.
  String? _busy;
  String? _feedback;

  AppState get state => widget.state;

  void _snack(String msg) {
    if (!mounted) return;
    setState(() => _feedback = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export({bool csv = false}) async {
    setState(() => _busy = 'export');
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await saveTextFile(
        fileName: 'screen-companion-$date.${csv ? 'csv' : 'json'}',
        content: csv ? ShelfStore.toCsv(state.entries) : state.exportJson(),
        mimeType: csv ? 'text/csv' : 'application/json',
      );
      if (saved == null) return; // picker dismissed
      _snack('Saved $saved');
    } on PlatformException {
      // Never show the platform's own message: it names Android internals.
      _snack(
        'Could not write the file. Pick a different folder and try '
        'again.',
      );
    } catch (_) {
      _snack(
        'Could not write the file. Pick a different folder and try '
        'again.',
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Map<String, dynamic> _backup = {};

  @override
  void initState() {
    super.initState();
    state.addListener(_changed);
    _refreshBackup();
  }

  @override
  void dispose() {
    state.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshBackup() async {
    try {
      final status = await AndroidServices.backupStatus();
      if (mounted) setState(() => _backup = status);
    } catch (_) {
      /* The shelf remains usable on platforms without Android. */
    }
  }

  Future<void> _deviceAction(Future<void> Function() action) async {
    setState(() => _busy = 'device');
    try {
      await action();
    } on PlatformException catch (e) {
      _snack(
        e.code == 'unsupported'
            ? 'Add the widget using the widget picker on your home screen.'
            : 'Could not access the backup folder. Choose it again or free some space.',
      );
    } catch (error, stack) {
      Diagnostics.record(error, stack, source: 'device settings');
      _snack('Could not complete that action. Try again.');
    } finally {
      await _refreshBackup();
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = 'import');
    try {
      final picked = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'JSON backup',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
          const XTypeGroup(label: 'Any file'),
        ],
      );
      if (picked == null) return;
      if (await picked.length() > ShelfStore.maxImportBytes) {
        _snack('That file exceeds the 10 MB backup limit.');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > ShelfStore.maxImportBytes) {
        _snack('That file exceeds the 10 MB backup limit.');
        return;
      }
      final document = await ShelfStore.parseInBackground(utf8.decode(bytes));
      if (!document.valid) {
        _snack(document.error!);
        return;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final applied = await showImportSheet(context, state, document);
      if (applied == true) {
        if (mounted) Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Import saved. ${document.issues.length} rows skipped.',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                try {
                  await state.restoreSnapshot();
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not restore. Try again in Settings.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        );
        if (mounted) setState(() {});
      }
    } catch (error, stack) {
      Diagnostics.record(error, stack, source: 'import');
      _snack('Could not read that backup. Check the file and try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required String id,
    required VoidCallback onTap,
  }) {
    final t = context.tk;
    final running = _busy == id;
    final locked = _busy != null;
    return Semantics(
      button: true,
      enabled: !locked,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: locked ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: locked ? t.inkGhost : t.inkMuted),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Type.label.copyWith(
                        fontSize: 14,
                        color: locked ? t.inkFaint : t.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      running ? 'Working…' : subtitle,
                      style: Type.bodySm.copyWith(color: t.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 18,
                height: 18,
                child: running
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.inkMuted,
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: locked ? t.inkGhost : t.inkFaint,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SheetScaffold(
        title: 'Settings',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: SectionLabel('Your data'),
              ),
              if (_feedback != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    _feedback!,
                    style: Type.bodySm.copyWith(color: t.ink),
                  ),
                ),
              _row(
                icon: Icons.file_download_outlined,
                title: 'Export a backup',
                subtitle: 'Write your shelf to a JSON file',
                id: 'export',
                onTap: () => _export(),
              ),
              _row(
                icon: Icons.file_upload_outlined,
                title: 'Import a backup',
                subtitle: 'Read a JSON file back in',
                id: 'import',
                onTap: _import,
              ),
              _row(
                icon: Icons.table_view_outlined,
                title: 'Export CSV',
                subtitle: 'Open your shelf in a spreadsheet',
                id: 'export',
                onTap: () => _export(csv: true),
              ),
              _row(
                icon: Icons.delete_outline,
                title: 'Trash',
                subtitle:
                    '${state.trash.length} titles \u00b7 kept for 30 days',
                id: 'trash',
                onTap: () => showTrashSheet(context, state),
              ),
              if (state.hasSnapshot)
                _row(
                  icon: Icons.restore,
                  title: 'Restore pre-import snapshot',
                  subtitle: 'Put back the shelf from before your last import',
                  id: 'snapshot',
                  onTap: () => _deviceAction(() async {
                    await state.restoreSnapshot();
                    _snack(
                      'Previous shelf restored. Tap restore again to switch back.',
                    );
                  }),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: SectionLabel('Weekly backups'),
              ),
              _row(
                icon: Icons.create_new_folder_outlined,
                title: _backup['enabled'] == true
                    ? 'Change backup folder'
                    : 'Choose backup folder',
                subtitle: _backup['enabled'] == true
                    ? '${_backup['folder']} · weekly · latest 3 retained'
                    : 'Choose a local folder once. Keep the latest 3 saves.',
                id: 'device',
                onTap: () => _deviceAction(() async {
                  if (await AndroidServices.chooseBackupFolder()) {
                    await AndroidServices.backupNow();
                    _snack('Weekly backups enabled. First backup saved.');
                  }
                }),
              ),
              if (_backup['enabled'] == true) ...[
                _row(
                  icon: Icons.save_outlined,
                  title: 'Back up now',
                  subtitle: (_backup['lastBackup'] as int? ?? 0) == 0
                      ? 'No successful backup yet'
                      : 'Last saved ${watchedLabel(_backup['lastBackup'] as int, 'day')}',
                  id: 'device',
                  onTap: () => _deviceAction(() async {
                    await AndroidServices.backupNow();
                    _snack('Backup saved. Latest 3 retained.');
                  }),
                ),
                _row(
                  icon: Icons.pause_circle_outline,
                  title: 'Turn off weekly backups',
                  subtitle: 'Existing exported files stay in your folder',
                  id: 'device',
                  onTap: () => _deviceAction(AndroidServices.disableBackup),
                ),
              ],
              if ((_backup['error'] as String? ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _backup['error'] as String,
                    style: TextStyle(color: t.danger),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: SectionLabel('On this phone'),
              ),
              _row(
                icon: Icons.widgets_outlined,
                title: 'Add home-screen widget',
                subtitle: 'Shortest sitting, with the next episode up',
                id: 'device',
                onTap: () => _deviceAction(AndroidServices.pinWidget),
              ),
              _row(
                icon: Icons.copy_outlined,
                title: 'Copy diagnostics',
                subtitle: 'Small local error log · no titles, notes or links',
                id: 'diagnostics',
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: await Diagnostics.copyReport()),
                  );
                  _snack('Diagnostics copied.');
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Text(
                  '${titleCount(state.entries.length)} · '
                  '${spanOfTime(state.minutesWatched)} watched, kept on this '
                  'phone only.',
                  style: Type.meta.copyWith(color: t.inkFaint, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
