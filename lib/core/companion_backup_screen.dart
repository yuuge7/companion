import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import 'automatic_backup.dart';
import 'companion_backup.dart';
import 'companion_data.dart';

class CompanionBackupScreen extends StatefulWidget {
  const CompanionBackupScreen({super.key, required this.data});
  final CompanionData data;
  @override
  State<CompanionBackupScreen> createState() => _CompanionBackupScreenState();
}

class _CompanionBackupScreenState extends State<CompanionBackupScreen>
    with WidgetsBindingObserver {
  late final _backup = CompanionBackup(widget.data);
  bool _busy = false;
  String? _message;
  CompanionBackupPreview? _preview;
  Map<String, dynamic>? _automatic;
  Timer? _statusTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAutomatic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAutomatic();
  }

  Future<void> _refreshAutomatic() async {
    try {
      final status = await AutomaticBackup.status();
      if (mounted) {
        setState(() => _automatic = status);
        _statusTimer?.cancel();
        if (status['running'] == true) {
          _statusTimer = Timer(const Duration(seconds: 2), _refreshAutomatic);
        }
      }
    } on MissingPluginException {
      // The scheduling controls are Android-only; manual backups work elsewhere.
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not read automatic backup status. Reopen this screen to try again.',
        );
      }
    }
  }

  Future<void> _automaticAction(Future<void> Function() action) =>
      _run(() async {
        try {
          await action();
        } on PlatformException catch (e) {
          throw FormatException(
            e.message ?? 'Could not update automatic backups.',
          );
        } finally {
          await _refreshAutomatic();
        }
      });
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is FormatException
              ? e.message
              : 'Could not finish. Check available storage and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final bytes = await _backup.create();
    final name =
        'Companion-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.companion';
    final path = await FilePicker.platform.saveFile(
      fileName: name,
      bytes: bytes,
    );
    if (path != null && !Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (path != null && mounted) {
      setState(() => _message = 'Complete backup saved.');
    }
  });
  Future<void> _import({bool recovery = false}) => _run(() async {
    setState(() => _preview = null);
    Uint8List bytes;
    if (recovery) {
      bytes = await _backup.recoveryBytes();
    } else {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      if (picked == null) return;
      final item = picked.files.single;
      if (item.size > CompanionBackup.maxBytes) {
        throw const FormatException('Backup exceeds 150 MB.');
      }
      if (item.path != null) {
        final file = File(item.path!);
        if (await file.length() > CompanionBackup.maxBytes) {
          throw const FormatException('Backup exceeds 150 MB.');
        }
        bytes = await file.readAsBytes();
      } else if (item.bytes != null) {
        bytes = item.bytes!;
      } else {
        throw const FormatException(
          'That file could not be read. Choose a local backup.',
        );
      }
    }
    final preview = _backup.decode(bytes);
    if (mounted) setState(() => _preview = preview);
  });
  Future<void> _restore() => _run(() async {
    await _backup.restore(_preview!);
    if (mounted) {
      setState(() {
        _preview = null;
        _message = 'All four libraries and shared settings restored.';
      });
    }
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Complete backup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.inventory_2_outlined, size: 48),
          const SizedBox(height: 20),
          Text(
            'One file. Every shelf.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Save books, manga, film and anime together, including book cover files, reading and viewing history, ratings, notes, physical collection details, trash, recovery snapshots and shared settings. Manga and poster image links are preserved.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep the .companion file somewhere you can access if you lose this device.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Save complete backup'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _import(),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Choose backup to restore'),
          ),
          FutureBuilder<bool>(
            future: _backup.hasRecovery(),
            builder: (context, snapshot) => snapshot.data == true
                ? TextButton.icon(
                    onPressed: _busy ? null : () => _import(recovery: true),
                    icon: const Icon(Icons.restore),
                    label: const Text('Review previous libraries'),
                  )
                : const SizedBox.shrink(),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
          if (_automatic case final status?) ...[
            const Divider(height: 40),
            Text(
              'Automatic complete backups',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Save all four libraries and book covers to a folder you choose. Android runs backups around the chosen interval, including when Companion is closed. The latest 3 automatic backups are kept.',
            ),
            const SizedBox(height: 12),
            if (status['enabled'] == true) ...[
              Text('Folder: ${status['folder']}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(status['hours']),
                initialValue: status['hours'] as int? ?? 168,
                decoration: const InputDecoration(labelText: 'Back up'),
                items: const [
                  DropdownMenuItem(value: 24, child: Text('Daily')),
                  DropdownMenuItem(value: 168, child: Text('Weekly')),
                ],
                onChanged: _busy || status['running'] == true
                    ? null
                    : (hours) => _automaticAction(
                        () => AutomaticBackup.setFrequency(hours!),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                (status['lastBackup'] as int? ?? 0) == 0
                    ? 'No successful automatic backup yet.'
                    : 'Last successful backup: ${DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(status['lastBackup'] as int))}',
              ),
              if (status['scheduled'] == false)
                const Text(
                  'Automatic scheduling needs attention. Choose the backup folder again.',
                ),
              if ((status['error'] as String? ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      status['error'] as String,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy || status['running'] == true
                    ? null
                    : () => _automaticAction(() async {
                        await AutomaticBackup.backupNow();
                        if (mounted) {
                          setState(
                            () => _message = 'Complete automatic backup saved.',
                          );
                        }
                      }),
                icon: const Icon(Icons.backup_outlined),
                label: Text(
                  status['running'] == true
                      ? 'Backup in progress'
                      : 'Back up now',
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: _busy || status['running'] == true
                  ? null
                  : () => _automaticAction(() async {
                      if (await AutomaticBackup.chooseFolder()) {
                        await AutomaticBackup.backupNow();
                        if (mounted) {
                          setState(
                            () => _message = 'Automatic backups enabled. First complete backup saved.',
                          );
                        }
                      }
                    }),
              icon: const Icon(Icons.folder_outlined),
              label: Text(
                status['enabled'] == true
                    ? 'Change backup folder'
                    : 'Choose automatic backup folder',
              ),
            ),
            if (status['enabled'] == true)
              TextButton(
                onPressed: _busy || status['running'] == true
                    ? null
                    : () => _automaticAction(AutomaticBackup.disable),
                child: const Text('Turn off automatic backups'),
              ),
          ],
          if (_preview case final preview?) ...[
            const Divider(height: 40),
            Text(
              'Review before restoring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Created ${DateFormat.yMMMd().add_jm().format(preview.createdAt.toLocal())}',
            ),
            for (final count in preview.counts.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(count.key),
                trailing: Text('${count.value} entries'),
              ),
            const Text(
              'Restoring replaces all four current libraries and shared settings, including privacy settings. A recovery copy of your current libraries is saved on this device first. Older trash may have expired.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore),
              label: const Text('Replace libraries and restore'),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _preview = null),
              child: const Text('Cancel restore'),
            ),
          ],
        ],
      ),
    ),
  );
}
