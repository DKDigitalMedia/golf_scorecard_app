import 'package:flutter/material.dart';
import 'hole_entry_screen.dart';
import 'saved_rounds_screen.dart';
import 'dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import '../providers/round_provider.dart';
import '../providers/db_provider.dart';
import '../widgets/chip_group.dart';
import '../widgets/distance_slider.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Golf Scorecard')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HoleEntryScreen()),
                );
              },
              child: const Text('New Round', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedRoundsScreen()),
                );
              },
              child: const Text('Saved Rounds', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                );
              },
              child: const Text('Dashboard', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
