import 'package:flutter/material.dart';

class ChipGroup extends StatelessWidget {
  const ChipGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.0,
      children: const [
        Chip(label: Text('Option 1')),
        Chip(label: Text('Option 2')),
        Chip(label: Text('Option 3')),
      ],
    );
  }
}
