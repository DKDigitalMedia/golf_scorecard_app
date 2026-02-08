import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/main_menu_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Scorecard App',
      theme: ThemeData(primarySwatch: Colors.green),
      navigatorObservers: [routeObserver],
      home: const MainMenuScreen(),
    );
  }
}
