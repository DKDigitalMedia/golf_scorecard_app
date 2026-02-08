import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/round_provider.dart';
import '../providers/db_provider.dart';
import '../widgets/chip_group.dart';
import '../widgets/distance_slider.dart';
import 'saved_rounds_screen.dart';
import 'dashboard_screen.dart';
import '../db/app_database.dart';

class HoleEntryScreen extends ConsumerWidget {
  const HoleEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(roundProvider);
    final notifier = ref.read(roundProvider.notifier);
    final hole = round.currentHole;
    final db = ref.read(dbProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Hole ${hole.holeNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedRoundsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Score', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            ChipGroup(
              options: ['3', '4', '5', '6', '7'],
              selected: hole.score?.toString(),
              onSelected: (value) {
                notifier.updateHole((h) => h.score = int.parse(value));
                notifier.tryAutoAdvance();
              },
            ),
            const SizedBox(height: 24),
            const Text('Putts', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            ChipGroup(
              options: ['0', '1', '2', '3', '4'],
              selected: hole.putts?.toString(),
              onSelected: (value) {
                notifier.updateHole((h) => h.putts = int.parse(value));
                notifier.tryAutoAdvance();
              },
            ),
            const SizedBox(height: 24),
            const Text('FIR', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            ChipGroup(
              options: ['Left', 'Center', 'Right', 'N/A'],
              selected: hole.fir,
              onSelected: (value) => notifier.updateHole((h) => h.fir = value),
            ),
            const SizedBox(height: 24),
            const Text('Approach Location', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            ChipGroup(
              options: ['Green', 'Miss Left', 'Miss Right', 'Short', 'Long'],
              selected: hole.approachLocation,
              onSelected: (value) =>
                  notifier.updateHole((h) => h.approachLocation = value),
            ),
            const SizedBox(height: 24),
            const Text('Penalties', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            ChipGroup(
              options: ['0', '1', '2', '3'],
              selected: hole.penalties.toString(),
              onSelected: (value) =>
                  notifier.updateHole((h) => h.penalties = int.parse(value)),
            ),
            const SizedBox(height: 24),
            DistanceSlider(
              label: 'Approach Distance (yds)',
              value: hole.approachDistance,
              max: 250,
              onChanged: (value) =>
                  notifier.updateHole((h) => h.approachDistance = value),
            ),
            const SizedBox(height: 24),
            DistanceSlider(
              label: 'First Putt Distance (ft)',
              value: hole.firstPuttDistance,
              max: 60,
              onChanged: (value) =>
                  notifier.updateHole((h) => h.firstPuttDistance = value),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed:
                      round.currentHoleIndex > 0 ? notifier.previousHole : null,
                  child: const Text('Back'),
                ),
                ElevatedButton(
                  onPressed:
                      round.currentHoleIndex < 17 ? notifier.nextHole : null,
                  child: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                // Insert a new round into the database
                final roundId = await db.insertRound(
                  RoundsCompanion(
                    courseId: Value(1), // <-- Fixed: remove const
                    date: Value(DateTime.now()),
                    notes: Value('My round notes'), // <-- Fixed: remove const
                  ),
                );

                // Insert all holes for this round
                for (var h in round.holes) {
                  await db.insertHole(HolesPlayedCompanion(
                    roundId: Value(roundId),
                    holeNumber: Value(h.holeNumber),
                    score: Value(h.score),
                    putts: Value(h.putts),
                    fir: Value(h.fir),
                    approachLocation: Value(h.approachLocation),
                    approachDistance: Value(h.approachDistance),
                    firstPuttDistance: Value(h.firstPuttDistance),
                    penalties: Value(h.penalties),
                  ));
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Round saved successfully!')),
                );
              },
              child: const Text('Save Round'),
            ),
          ],
        ),
      ),
    );
  }
}
