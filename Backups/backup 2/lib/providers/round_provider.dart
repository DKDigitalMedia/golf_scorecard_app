import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoundNotifier extends StateNotifier<int> {
  RoundNotifier() : super(0);

  void increment() => state++;
}

final roundProvider =
    StateNotifierProvider<RoundNotifier, int>((ref) => RoundNotifier());
