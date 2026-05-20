import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import 'hole_entry_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: FutureBuilder<List<RoundsData>>(
        future: db.getAllRounds(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final rounds = snapshot.data!;

          return ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (_, index) {
              final round = rounds[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: ListTile(
                  title: Text(round.name),
                  subtitle: FutureBuilder<List<Hole>>(
                    future: db.getHolesForRound(round.id),
                    builder: (context, holeSnap) {
                      if (!holeSnap.hasData) return const SizedBox.shrink();
                      final holes = holeSnap.data!;
                      return Wrap(
                        spacing: 4,
                        children: holes.map((h) {
                          final completed = h.score != null && h.putts != null;
                          return CircleAvatar(
                            radius: 12,
                            backgroundColor:
                                completed ? Colors.green : Colors.grey,
                            child: Text('${h.holeNumber}',
                                style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            HoleEntryScreen(roundId: round.id, initialHole: 1),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
