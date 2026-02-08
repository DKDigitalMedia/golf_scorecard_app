import 'package:flutter/material.dart';

class ChipGroup extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final void Function(String) onSelected;

  const ChipGroup(
      {super.key,
      required this.options,
      this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: options.map((o) {
        final isSelected = o == selected;
        return ChoiceChip(
          label: Text(o),
          selected: isSelected,
          onSelected: (_) => onSelected(o),
        );
      }).toList(),
    );
  }
}
