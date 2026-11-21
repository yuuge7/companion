import 'package:flutter/material.dart';

import '../physical_collection.dart';

class CollectionFields extends StatelessWidget {
  const CollectionFields({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final PhysicalCollection value;
  final ValueChanged<PhysicalCollection> onChanged;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Physical collection'),
    subtitle: Text(
      value.isTracked ? value.summary : 'Ownership, shelf, loans and volumes',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    childrenPadding: const EdgeInsets.only(top: 16, bottom: 16),
    children: [
      DropdownButtonFormField<Ownership>(
        initialValue: value.ownership,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Ownership'),
        items: Ownership.values
            .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
            .toList(),
        onChanged: (v) => onChanged(value.copyWith(ownership: v)),
      ),
      const SizedBox(height: 20),
      TextFormField(
        initialValue: value.shelf,
        decoration: const InputDecoration(
          labelText: 'Shelf location',
          hintText: 'Living room · shelf 2',
        ),
        onChanged: (s) => onChanged(value.copyWith(shelf: s.trim())),
      ),
      const SizedBox(height: 20),
      TextFormField(
        initialValue: value.borrowedFrom,
        decoration: const InputDecoration(labelText: 'Borrowed from'),
        onChanged: (s) => onChanged(value.copyWith(borrowedFrom: s.trim())),
      ),
      const SizedBox(height: 20),
      TextFormField(
        initialValue: value.lentTo,
        decoration: const InputDecoration(
          labelText: 'Lent to',
          helperText: 'Clear this name when it is returned.',
          helperMaxLines: 3,
        ),
        onChanged: (s) => onChanged(value.copyWith(lentTo: s.trim())),
      ),
      const SizedBox(height: 20),
      TextFormField(
        initialValue: value.totalVolumes?.toString() ?? '',
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Total volumes'),
        validator: (s) =>
            s!.isNotEmpty &&
                (int.tryParse(s) == null ||
                    int.parse(s) < 1 ||
                    int.parse(s) > 10000)
            ? 'Enter a number between 1 and 10,000.'
            : null,
        onChanged: (s) => onChanged(
          value.copyWith(totalVolumes: int.tryParse(s), clearTotal: s.isEmpty),
        ),
      ),
      const SizedBox(height: 20),
      TextFormField(
        initialValue: value.volumes.join(', '),
        decoration: const InputDecoration(
          labelText: 'Volumes on your shelf',
          hintText: '1-4, 7, 9',
        ),
        validator: (s) {
          try {
            PhysicalCollection.parseVolumes(s!);
            return null;
          } on FormatException catch (e) {
            return e.message;
          }
        },
        onChanged: (s) {
          try {
            onChanged(
              value.copyWith(volumes: PhysicalCollection.parseVolumes(s)),
            );
          } on FormatException {
            /* Keep the last valid value until corrected. */
          }
        },
      ),
      if (value.missingVolumes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Missing volumes: ${value.missingVolumes.take(30).join(', ')}${value.missingVolumes.length > 30 ? '…' : ''}',
            ),
          ),
        ),
    ],
  );
}
