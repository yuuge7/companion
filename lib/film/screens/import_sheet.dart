import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../import_plan.dart';
import '../models/shelf_entry.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/sheet.dart';

Future<bool?> showImportSheet(
  BuildContext context,
  AppState state,
  ImportDocument document,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ImportPreview(state: state, document: document),
);

class ImportPreview extends StatefulWidget {
  final AppState state;
  final ImportDocument document;
  const ImportPreview({super.key, required this.state, required this.document});
  @override
  State<ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<ImportPreview> {
  late final plan = ImportPlan(widget.state.entries, widget.document.entries);
  bool replace = false;
  bool busy = false;
  String? error;

  Widget _version(String label, ShelfEntry e) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          const SizedBox(height: 8),
          Text(e.title, style: Type.title),
          Text(
            '${e.kind} · ${e.year ?? 'year unknown'}\n${e.director}\n'
            '${runtimeLong(e.runtime)}${e.isSeries ? '/episode · ${e.watched}/${e.episodes ?? '?'} episodes' : ''}\n'
            '${e.status} · ${e.rating}/5\n${e.tags.join(', ')}\n${e.note}\n'
            '${e.plays} viewings\n${e.viewingsNewestFirst.map((v) => '${watchedLabel(v.at, v.precision)}${v.location.isEmpty ? '' : ' · ${v.location}'}${v.company.isEmpty ? '' : ' · ${v.company}'}').join('\n')}\n'
            'Seasons: ${e.seasons.join(', ')}\n'
            '${e.posterUrl.isEmpty ? '' : 'Poster: ${e.posterUrl}\n'}'
            '${e.watchUrl.isEmpty ? '' : 'Watch: ${e.watchUrl}\n'}'
            '${updatedLabel(e.lastUpdated)}',
            style: Type.bodySm,
          ),
        ],
      ),
    ),
  );

  Future<void> _apply() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.applyImport(plan, replace: replace);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save the import. Your previous shelf is recoverable in Settings.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: SheetScaffold(
        title: 'Import preview',
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${plan.count(ImportChange.added)} new · ${plan.count(ImportChange.updated)} updated · '
              '${plan.count(ImportChange.unchanged)} unchanged · ${plan.count(ImportChange.conflict)} conflicts',
              style: Type.body,
            ),
            const SizedBox(height: 12),
            const Text(
              'Merge uses newer incoming versions. Older or equally dated changes stay local unless you choose the incoming version below.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Replace entire shelf'),
              subtitle: const Text(
                'Current titles go to 30-day trash. A pre-import snapshot is kept for either mode.',
              ),
              value: replace,
              onChanged: busy ? null : (v) => setState(() => replace = v),
            ),
            if (replace)
              Text(
                'Replace will install all ${widget.document.entries.length} incoming titles, including older versions.',
                style: Type.label,
              ),
            for (final row in plan.rows.where(
              (r) =>
                  r.change == ImportChange.conflict ||
                  r.change == ImportChange.updated,
            ))
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(row.incoming.title),
                subtitle: Text(
                  replace
                      ? 'Replace uses the incoming version'
                      : row.change == ImportChange.conflict
                      ? 'Conflict · local version kept by default'
                      : 'Newer incoming version',
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _version('On this phone', row.local!),
                      _version('Incoming', row.incoming),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use incoming version'),
                    value: replace || row.useIncoming,
                    onChanged: replace || busy
                        ? null
                        : (v) => setState(() => row.useIncoming = v),
                  ),
                ],
              ),
            if (widget.document.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionLabel('Skipped rows'),
              for (final issue in widget.document.issues)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Row ${issue.row}: ${issue.reason}',
                    style: Type.bodySm,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '${widget.document.issues.length} rows will not be imported. Your original file is unchanged.',
                style: Type.bodySm,
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!, style: TextStyle(color: context.tk.danger)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy || widget.document.entries.isEmpty
                  ? null
                  : _apply,
              child: Text(
                busy
                    ? 'Saving…'
                    : replace
                    ? 'Replace shelf'
                    : 'Apply merge',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
