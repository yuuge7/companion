import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/sheet.dart';

Future<void> showTrashSheet(
  BuildContext context,
  AppState state,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    child: SheetScaffold(
      title: 'Trash · 30 days',
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final trash = state.trash.reversed.toList();
          return ListView.builder(
            shrinkWrap: true,
            itemCount: trash.isEmpty ? 1 : trash.length,
            itemBuilder: (context, i) {
              if (trash.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Trash is empty. Deleted titles stay here for 30 days.',
                  ),
                );
              }
              final item = trash[i];
              return ListTile(
                title: Text(item.entry.title),
                subtitle: Text(
                  '${item.entry.year ?? 'Year unknown'} · ${item.daysLeft} days left',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await state.restoreTrash(item);
                    } catch (_) {
                      if (context.mounted) {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Could not restore'),
                            content: const Text(
                              'A copy may already be on your shelf, or the change could not be saved.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Restore'),
                ),
              );
            },
          );
        },
      ),
    ),
  ),
);
