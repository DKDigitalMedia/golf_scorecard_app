import 'package:flutter/material.dart';

import 'course_list_screen.dart';
import 'dashboard_screen.dart';
import 'main_menu_screen.dart';
import 'saved_rounds_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const MainMenuScreen(), // Play
      const SavedRoundsScreen(), // Rounds
      const CourseListScreen(), // Courses
      const DashboardScreen(), // Stats
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.golf_course),
            label: 'Play',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Rounds',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Courses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
