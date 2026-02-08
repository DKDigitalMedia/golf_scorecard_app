import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

part 'app_database.g.dart';

// ----------------------
// Enums
// ----------------------
enum ApproachLocation { Center, Left, Right, Long, Short }

// ----------------------
// Tables
// ----------------------
class Rounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

class Holes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roundId => integer()
      .customConstraint('NOT NULL REFERENCES rounds(id) ON DELETE CASCADE')();
  IntColumn get holeNumber => integer()();
  IntColumn get score => integer().nullable()();
  IntColumn get putts => integer().nullable()();
  IntColumn get penalties => integer().withDefault(const Constant(0))();
  BoolColumn get fir => boolean().withDefault(const Constant(false))();
  BoolColumn get gir => boolean().withDefault(const Constant(false))();
  BoolColumn get upAndDown => boolean().withDefault(const Constant(false))();
  IntColumn get approachDistance => integer().nullable()();
  IntColumn get firstPuttDistance => integer().nullable()();
  TextColumn get approachLocation =>
      text().nullable()(); // stored as enum string
  IntColumn get yardage => integer().nullable()();
}

// ----------------------
// Data class for Holes
// ----------------------
class Hole {
  final int id;
  final int roundId;
  final int holeNumber;
  final int? score;
  final int? putts;
  final int penalties;
  final bool fir;
  final bool gir;
  final bool upAndDown;
  final int? approachDistance;
  final int? firstPuttDistance;
  final ApproachLocation? approachLocation;
  final int? yardage;

  Hole({
    required this.id,
    required this.roundId,
    required this.holeNumber,
    this.score,
    this.putts,
    this.penalties = 0,
    this.fir = false,
    this.gir = false,
    this.upAndDown = false,
    this.approachDistance,
    this.firstPuttDistance,
    this.approachLocation,
    this.yardage,
  });
}

// ----------------------
// Drift Database
// ----------------------
@DriftDatabase(tables: [Rounds, Holes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ----------------------
  // Round Helpers
  // ----------------------
  Future<int> createRound(String name) async {
    return into(rounds).insert(RoundsCompanion(
      name: Value(name),
      date: Value(DateTime.now()),
    ));
  }

  Future<List<RoundsData>> getAllRounds() async {
    return select(rounds).get();
  }

  Future<void> markRoundCompleted(int roundId) async {
    await (update(rounds)..where((r) => r.id.equals(roundId)))
        .write(RoundsCompanion(completed: const Value(true)));
  }

  // ----------------------
  // Hole Helpers
  // ----------------------
  Future<Hole?> getHole(int roundId, int holeNumber) async {
    final row = await (select(holes)
          ..where((h) =>
              h.roundId.equals(roundId) & h.holeNumber.equals(holeNumber)))
        .getSingleOrNull();

    if (row == null) return null;

    ApproachLocation? location;
    if (row.approachLocation != null) {
      location = ApproachLocation.values.firstWhere(
          (e) => e.name == row.approachLocation!,
          orElse: () => ApproachLocation.Center);
    }

    return Hole(
      id: row.id,
      roundId: row.roundId,
      holeNumber: row.holeNumber,
      score: row.score,
      putts: row.putts,
      penalties: row.penalties,
      fir: row.fir,
      gir: row.gir,
      upAndDown: row.upAndDown,
      approachDistance: row.approachDistance,
      firstPuttDistance: row.firstPuttDistance,
      approachLocation: location,
      yardage: row.yardage,
    );
  }

  Future<void> insertHole({
    required int roundId,
    required int holeNumber,
    required int score,
    required int putts,
    required int penalties,
    required bool fir,
    required bool gir,
    required bool upAndDown,
    ApproachLocation? approachLocation,
    int? approachDistance,
    int? firstPuttDistance,
    int? yardage,
  }) async {
    await into(holes).insert(HolesCompanion(
      roundId: Value(roundId),
      holeNumber: Value(holeNumber),
      score: Value(score),
      putts: Value(putts),
      penalties: Value(penalties),
      fir: Value(fir),
      gir: Value(gir),
      upAndDown: Value(upAndDown),
      approachDistance:
          approachDistance != null ? Value(approachDistance) : Value.absent(),
      firstPuttDistance:
          firstPuttDistance != null ? Value(firstPuttDistance) : Value.absent(),
      approachLocation: approachLocation != null
          ? Value(approachLocation.name)
          : Value.absent(),
      yardage: yardage != null ? Value(yardage) : Value.absent(),
    ));
  }

  Future<void> updateHole(
    int holeId, {
    int? score,
    int? putts,
    int? penalties,
    bool? fir,
    bool? gir,
    bool? upAndDown,
    int? approachDistance,
    int? firstPuttDistance,
    ApproachLocation? approachLocation,
    int? yardage,
  }) async {
    await (update(holes)..where((h) => h.id.equals(holeId))).write(
      HolesCompanion(
        score: score != null ? Value(score) : Value.absent(),
        putts: putts != null ? Value(putts) : Value.absent(),
        penalties: penalties != null ? Value(penalties) : Value.absent(),
        fir: fir != null ? Value(fir) : Value.absent(),
        gir: gir != null ? Value(gir) : Value.absent(),
        upAndDown: upAndDown != null ? Value(upAndDown) : Value.absent(),
        approachDistance:
            approachDistance != null ? Value(approachDistance) : Value.absent(),
        firstPuttDistance: firstPuttDistance != null
            ? Value(firstPuttDistance)
            : Value.absent(),
        approachLocation: approachLocation != null
            ? Value(approachLocation.name)
            : Value.absent(),
        yardage: yardage != null ? Value(yardage) : Value.absent(),
      ),
    );
  }

  Future<List<Hole>> getHolesForRound(int roundId) async {
    final list =
        await (select(holes)..where((h) => h.roundId.equals(roundId))).get();

    return list.map((h) {
      ApproachLocation? location;
      if (h.approachLocation != null) {
        location = ApproachLocation.values.firstWhere(
            (e) => e.name == h.approachLocation!,
            orElse: () => ApproachLocation.Center);
      }

      return Hole(
        id: h.id,
        roundId: h.roundId,
        holeNumber: h.holeNumber,
        score: h.score,
        putts: h.putts,
        penalties: h.penalties,
        fir: h.fir,
        gir: h.gir,
        upAndDown: h.upAndDown,
        approachDistance: h.approachDistance,
        firstPuttDistance: h.firstPuttDistance,
        approachLocation: location,
        yardage: h.yardage,
      );
    }).toList();
  }

  Future<bool> isHoleCompleted(int roundId, int holeNumber) async {
    final hole = await getHole(roundId, holeNumber);
    if (hole == null) return false;
    return hole.score != null && hole.putts != null;
  }
}

// ----------------------
// Open connection
// ----------------------
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'golf_scorecard.sqlite'));
    return NativeDatabase(file);
  });
}
