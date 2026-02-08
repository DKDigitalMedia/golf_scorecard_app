import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/main_menu_screen.dart';

void main() {
  runApp(const ProviderScope(child: GolfScorecardApp()));
}

class GolfScorecardApp extends StatelessWidget {
  const GolfScorecardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Scorecard',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const MainMenuScreen(),
    );
  }
}
