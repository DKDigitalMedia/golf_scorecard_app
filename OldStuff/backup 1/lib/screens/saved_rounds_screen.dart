import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/db_provider.dart';
import '../providers/round_provider.dart';
import 'hole_entry_screen.dart';
import '../db/app_database.dart';
import '../widgets/chip_group.dart';
import '../widgets/distance_slider.dart';

class SavedRoundsScreen extends ConsumerWidget {
  const SavedRoundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Rounds')),
      body: FutureBuilder(
        future: db.getAllRounds(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No saved rounds yet.'));
          }

          final rounds = snapshot.data!;

          return ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (context, index) {
              final round = rounds[index];
              final dateStr = round.date.toLocal().toString().split(' ')[0];

              return ListTile(
                title: Text('Round ${round.id} · $dateStr'),
                subtitle: Text(round.notes ?? ''),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () async {
                  // Load holes for this round
                  final holesData = await db.getHolesForRound(round.id);

                  // Update provider state
                  final notifier = ref.read(roundProvider.notifier);
                  await notifier.loadRound(holesData);

                  // Navigate to hole entry screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HoleEntryScreen()),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
