import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import 'hole_entry_screen.dart';
import 'saved_rounds_screen.dart';

class MainMenuScreen extends ConsumerWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Main Menu')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                // Create a new round
                final roundId = await db.createRound('New Round');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        HoleEntryScreen(roundId: roundId, initialHole: 1),
                  ),
                );
              },
              child: const Text('Start New Round'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedRoundsScreen()),
                );
              },
              child: const Text('Saved Rounds'),
            ),
          ],
        ),
      ),
    );
  }
}
