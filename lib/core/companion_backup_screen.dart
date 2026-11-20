import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'companion_backup.dart';
import 'companion_data.dart';

class CompanionBackupScreen extends StatefulWidget {
  const CompanionBackupScreen({super.key, required this.data});
  final CompanionData data;
  @override
  State<CompanionBackupScreen> createState() => _CompanionBackupScreenState();
}

class _CompanionBackupScreenState extends State<CompanionBackupScreen> {
  late final _backup = CompanionBackup(widget.data);
  bool _busy = false;
  String? _message;
  CompanionBackupPreview? _preview;
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
