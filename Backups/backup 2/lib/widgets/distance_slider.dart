import 'package:flutter/material.dart';

class DistanceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const DistanceSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Slider(
      min: 0,
      max: 300,
      divisions: 30,
      value: value,
      onChanged: onChanged,
      label: value.round().toString(),
    );
  }
}
