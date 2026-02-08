import 'package:flutter/material.dart';

enum ApproachLocation { Center, Left, Right, Long, Short }

class ApproachChip extends StatelessWidget {
  final ApproachLocation location;
  final bool selected;
  final VoidCallback onSelected;

  const ApproachChip({
    super.key,
    required this.location,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (location) {
      case ApproachLocation.Center:
        color = Colors.green;
        break;
      case ApproachLocation.Left:
      case ApproachLocation.Right:
        color = Colors.yellow;
        break;
      case ApproachLocation.Long:
      case ApproachLocation.Short:
        color = Colors.cyan;
        break;
    }

    return ChoiceChip(
      label: Text(location.name),
      selected: selected,
      selectedColor: color,
      backgroundColor: Colors.grey[300],
      onSelected: (_) => onSelected(),
    );
  }
}
