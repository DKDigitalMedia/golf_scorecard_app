import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import 'round_summary_screen.dart';

class HoleEntryScreen extends ConsumerStatefulWidget {
  final int roundId;
  final int initialHole;
  const HoleEntryScreen(
      {super.key, required this.roundId, this.initialHole = 1});

  @override
  ConsumerState<HoleEntryScreen> createState() => _HoleEntryScreenState();
}

class _HoleEntryScreenState extends ConsumerState<HoleEntryScreen> {
  int currentHole = 1;
  int score = 0;
  int putts = 0;
  int penalties = 0;
  bool fir = false;
  bool gir = false;
  bool upAndDown = false;

  ApproachLocation selectedApproachLocation = ApproachLocation.Center;
  int approachDistance = 0;
  int firstPuttDistance = 0;
  int yardage = 0;

  int maxApproachDistance = 175;
  int maxPuttDistance = 50;

  @override
  void initState() {
    super.initState();
    currentHole = widget.initialHole;
    _loadCurrentHole();
  }

  Future<void> _loadCurrentHole() async {
    final db = ref.read(databaseProvider);
    final hole = await db.getHole(widget.roundId, currentHole);

    setState(() {
      if (hole != null) {
        score = hole.score ?? 0;
        putts = hole.putts ?? 0;
        penalties = hole.penalties;
        fir = hole.fir;
        gir = hole.gir;
        upAndDown = hole.upAndDown;
        selectedApproachLocation =
            hole.approachLocation ?? ApproachLocation.Center;
        approachDistance = hole.approachDistance ?? 0;
        firstPuttDistance = hole.firstPuttDistance ?? 0;
        yardage = hole.yardage ?? 175;
      }
      maxApproachDistance = _computeMaxApproachDistance();
      maxPuttDistance = (yardage / 4).clamp(10, 50).toInt();
      if (approachDistance > maxApproachDistance)
        approachDistance = maxApproachDistance;
      if (firstPuttDistance > maxPuttDistance)
        firstPuttDistance = maxPuttDistance;
    });
  }

  int _computeMaxApproachDistance() {
    switch (selectedApproachLocation) {
      case ApproachLocation.Long:
        return (yardage * 1.1).toInt();
      case ApproachLocation.Short:
        return (yardage * 0.8).toInt();
      default:
        return yardage;
    }
  }

  Future<void> _saveCurrentHole() async {
    final db = ref.read(databaseProvider);
    final existing = await db.getHole(widget.roundId, currentHole);

    if (existing == null) {
      await db.insertHole(
        roundId: widget.roundId,
        holeNumber: currentHole,
        score: score,
        putts: putts,
        penalties: penalties,
        fir: fir,
        gir: gir,
        upAndDown: upAndDown,
        approachDistance: approachDistance,
        firstPuttDistance: firstPuttDistance,
        approachLocation: selectedApproachLocation,
        yardage: yardage,
      );
    } else {
      await db.updateHole(
        existing.id,
        score: score,
        putts: putts,
        penalties: penalties,
        fir: fir,
        gir: gir,
        upAndDown: upAndDown,
        approachDistance: approachDistance,
        firstPuttDistance: firstPuttDistance,
        approachLocation: selectedApproachLocation,
        yardage: yardage,
      );
    }
  }

  void _goToNextHole() async {
    await _saveCurrentHole();
    if (currentHole < 18) {
      setState(() => currentHole++);
      await _loadCurrentHole();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoundSummaryScreen(roundId: widget.roundId),
        ),
      );
    }
  }

  void _goToPreviousHole() async {
    await _saveCurrentHole();
    if (currentHole > 1) {
      setState(() => currentHole--);
      await _loadCurrentHole();
    }
  }

  String get nextButtonLabel => currentHole == 18 ? 'Round Summary' : 'Next';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hole $currentHole')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score
            TextField(
              decoration: const InputDecoration(labelText: 'Score'),
              keyboardType: TextInputType.number,
              onChanged: (val) =>
                  setState(() => score = int.tryParse(val) ?? 0),
              controller: TextEditingController(text: '$score'),
            ),
            const SizedBox(height: 16),
            // Putts
            TextField(
              decoration: const InputDecoration(labelText: 'Putts'),
              keyboardType: TextInputType.number,
              onChanged: (val) =>
                  setState(() => putts = int.tryParse(val) ?? 0),
              controller: TextEditingController(text: '$putts'),
            ),
            const SizedBox(height: 16),
            // Approach location chips
            Wrap(
              spacing: 8,
              children: ApproachLocation.values.map((loc) {
                final isSelected = selectedApproachLocation == loc;
                Color color;
                switch (loc) {
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
                  label: Text(loc.name),
                  selected: isSelected,
                  selectedColor: color,
                  backgroundColor: Colors.grey[300],
                  onSelected: (_) {
                    setState(() {
                      selectedApproachLocation = loc;
                      maxApproachDistance = _computeMaxApproachDistance();
                      if (approachDistance > maxApproachDistance)
                        approachDistance = maxApproachDistance;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Approach distance slider
            Text('Approach Distance: $approachDistance yds'),
            Slider(
              value: approachDistance.toDouble(),
              min: 0,
              max: maxApproachDistance.toDouble(),
              divisions: maxApproachDistance,
              onChanged: (val) =>
                  setState(() => approachDistance = val.toInt()),
            ),
            const SizedBox(height: 16),
            // Putt distance slider
            Text('First Putt Distance: $firstPuttDistance ft'),
            Slider(
              value: firstPuttDistance.toDouble(),
              min: 0,
              max: maxPuttDistance.toDouble(),
              divisions: maxPuttDistance,
              onChanged: (val) =>
                  setState(() => firstPuttDistance = val.toInt()),
            ),
            const SizedBox(height: 32),
            // Navigation buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: currentHole > 1 ? _goToPreviousHole : null,
                  child: const Text('Back'),
                ),
                ElevatedButton(
                  onPressed: _goToNextHole,
                  child: Text(nextButtonLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
