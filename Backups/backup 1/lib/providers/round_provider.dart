import 'package:flutter_riverpod/flutter_riverpod.dart';

// Model for a single hole
class Hole {
  int holeNumber;
  int? score;
  int? putts;
  String? fir;
  String? approachLocation;
  int approachDistance;
  int firstPuttDistance;
  int penalties;

  Hole({
    required this.holeNumber,
    this.score,
    this.putts,
    this.fir,
    this.approachLocation,
    this.approachDistance = 0,
    this.firstPuttDistance = 0,
    this.penalties = 0,
  });
}

// State for a round
class RoundState {
  List<Hole> holes;
  int currentHoleIndex;

  RoundState({List<Hole>? holes, this.currentHoleIndex = 0})
      : holes =
            holes ?? List.generate(18, (index) => Hole(holeNumber: index + 1));

  Hole get currentHole => holes[currentHoleIndex];
}

// Notifier
class RoundNotifier extends StateNotifier<RoundState> {
  RoundNotifier() : super(RoundState());

  void updateHole(void Function(Hole) update) {
    update(state.currentHole);
    state = RoundState(
      holes: [...state.holes],
      currentHoleIndex: state.currentHoleIndex,
    );
  }

  void nextHole() {
    if (state.currentHoleIndex < 17) {
      state = RoundState(
        holes: state.holes,
        currentHoleIndex: state.currentHoleIndex + 1,
      );
    }
  }

  void previousHole() {
    if (state.currentHoleIndex > 0) {
      state = RoundState(
        holes: state.holes,
        currentHoleIndex: state.currentHoleIndex - 1,
      );
    }
  }

  Future<void> loadRound(List<dynamic> holesData) async {
    final loadedHoles = holesData.map((h) {
      return Hole(
        holeNumber: h.holeNumber,
        score: h.score,
        putts: h.putts,
        fir: h.fir,
        approachLocation: h.approachLocation,
        approachDistance: h.approachDistance ?? 0,
        firstPuttDistance: h.firstPuttDistance ?? 0,
        penalties: h.penalties ?? 0,
      );
    }).toList();

    state = RoundState(holes: loadedHoles, currentHoleIndex: 0);
  }

  void tryAutoAdvance() {
    if (state.currentHoleIndex < 17) nextHole();
  }
}

// Provider
final roundProvider = StateNotifierProvider<RoundNotifier, RoundState>(
  (ref) => RoundNotifier(),
);
