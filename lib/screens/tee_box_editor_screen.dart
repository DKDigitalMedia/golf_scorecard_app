import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';

class TeeBoxEditorScreen extends ConsumerStatefulWidget {
  final int courseId;
  const TeeBoxEditorScreen({super.key, required this.courseId});

  @override
  ConsumerState<TeeBoxEditorScreen> createState() => _TeeBoxEditorScreenState();
}

class _TeeBoxEditorScreenState extends ConsumerState<TeeBoxEditorScreen> {
  List<TeeBox> teeBoxes = [];
  TeeBox? selectedTee;
  final TextEditingController teeNameController = TextEditingController();
  final TextEditingController yardageController = TextEditingController();
  final TextEditingController ratingController = TextEditingController();
  final TextEditingController slopeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTeeBoxes();
  }

  @override
  void dispose() {
    teeNameController.dispose();
    yardageController.dispose();
    ratingController.dispose();
    slopeController.dispose();
    super.dispose();
  }

  Future<void> _loadTeeBoxes() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getTeeBoxesForCourse(widget.courseId);
    if (!mounted) return;
    setState(() {
      teeBoxes = rows;
      if (selectedTee != null &&
          !teeBoxes.any((t) => t.id == selectedTee!.id)) {
        selectedTee = null;
      }
    });
  }

  Future<void> _addTeeBox() async {
    final name = teeNameController.text.trim();
    final yardage = int.tryParse(yardageController.text.trim()) ?? 0;
    final rating = double.tryParse(ratingController.text.trim()) ?? 0.0;
    final slope = int.tryParse(slopeController.text.trim()) ?? 0;

    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a tee name.')));
      return;
    }

    final db = ref.read(databaseProvider);
    await db.createTeeBox(
      courseId: widget.courseId,
      name: name,
      yardage: yardage,
      rating: rating,
      slope: slope,
    );

    if (!mounted) return;
    teeNameController.clear();
    yardageController.clear();
    ratingController.clear();
    slopeController.clear();
    await _loadTeeBoxes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tee Box Editor')),
      body: Column(
        children: [
          DropdownButton<TeeBox>(
            hint: const Text('Select Tee Box'),
            value: selectedTee,
            items: teeBoxes
                .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                .toList(),
            onChanged: (val) {
              setState(() {
                selectedTee = val;
              });
            },
          ),
          TextField(
              controller: teeNameController,
              decoration: const InputDecoration(labelText: 'Tee Name')),
          TextField(
              controller: yardageController,
              decoration: const InputDecoration(labelText: 'Yardage')),
          TextField(
              controller: ratingController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rating')),
          TextField(
              controller: slopeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Slope')),
          ElevatedButton(
              onPressed: _addTeeBox, child: const Text('Add Tee Box')),
        ],
      ),
    );
  }
}
