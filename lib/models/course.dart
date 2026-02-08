class TeeBox {
  final String name;
  final int yardage;

  TeeBox({required this.name, required this.yardage});
}

class Course {
  final int id;
  final String name;
  final List<TeeBox> tees;
  final double rating;
  final int slope;

  Course({
    required this.id,
    required this.name,
    required this.tees,
    required this.rating,
    required this.slope,
  });

  Course copyWith({
    int? id,
    String? name,
    List<TeeBox>? tees,
    double? rating,
    int? slope,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      tees: tees ?? this.tees,
      rating: rating ?? this.rating,
      slope: slope ?? this.slope,
    );
  }
}
