class HolePlayed {
  final int holeNumber;

  int? score;
  int? putts;
  String? fir;
  String? approachLocation;

  double approachDistance = 0;
  double firstPuttDistance = 0;

  int penalties = 0;

  HolePlayed({required this.holeNumber});

  bool get gir => approachLocation == 'Green';

  bool get upAndDown {
    if (score == null || putts == null) return false;
    return !gir && putts! <= 2;
  }
}
