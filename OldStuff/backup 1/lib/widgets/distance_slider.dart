import 'package:flutter/material.dart';

class DistanceSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final void Function(double) onChanged;

  const DistanceSlider(
      {super.key,
      required this.label,
      required this.value,
      required this.max,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(0)}'),
        Slider(
          value: value,
          min: 0,
          max: max,
          divisions: max.toInt(),
          label: value.toStringAsFixed(0),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
