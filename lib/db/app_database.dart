import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

@DataClassName('TeeBox')
class TeeBoxTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseId => integer().references(Courses, #id)();
  TextColumn get name => text()();
  IntColumn get yardage => integer()();
  RealColumn get rating => real()();
  IntColumn get slope => integer()();
}

class Rounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseId => integer().references(Courses, #id)();
  IntColumn get teeBoxId => integer().references(TeeBoxTable, #id)();

  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get weather => text().nullable()();
  TextColumn get notes => text().nullable()();

  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

/// Course-level hole definitions: Par + Stroke Index (same for all tees)
@DataClassName('CourseHole')
class CourseHoles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseId => integer().references(Courses, #id)();
  IntColumn get holeNumber => integer()(); // 1..18
  IntColumn get par => integer()();
  IntColumn get strokeIndex => integer().nullable()(); // 1..18 optional

  @override
  List<Set<Column>> get uniqueKeys => [
        {courseId, holeNumber},
      ];
}

/// Tee-specific yardage per hole
@DataClassName('TeeBoxHole')
class TeeBoxHoles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teeBoxId => integer().references(TeeBoxTable, #id)();
  IntColumn get holeNumber => integer()(); // 1..18
  IntColumn get yardage => integer().nullable()(); // optional until filled

  @override
  List<Set<Column>> get uniqueKeys => [
        {teeBoxId, holeNumber},
      ];
}

class Holes extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get roundId => integer().references(Rounds, #id)();
  IntColumn get holeNumber => integer()();

  // Fast-entry fields
  IntColumn get score => integer().nullable()();
  IntColumn get putts => integer().nullable()();
  IntColumn get penalties => integer().nullable()();

  // FIR: "L" | "C" | "R"
  TextColumn get fir => text().nullable()();

  // Approach Location: "L" | "C" | "R" | "LONG" | "SHORT"
  TextColumn get approachLocation => text().nullable()();

  IntColumn get approachDistance => integer().nullable()();
  IntColumn get firstPuttDistance => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {roundId, holeNumber},
      ];
}

@DriftDatabase(
    tables: [Courses, TeeBoxTable, Rounds, CourseHoles, TeeBoxHoles, Holes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v2 added hole columns
          if (from < 2) {
            await m.addColumn(holes, holes.putts);
            await m.addColumn(holes, holes.penalties);
            await m.addColumn(holes, holes.fir);
            await m.addColumn(holes, holes.approachLocation);
            await m.addColumn(holes, holes.approachDistance);
            await m.addColumn(holes, holes.firstPuttDistance);
          }

          // v3 added round metadata
          if (from < 3) {
            await m.addColumn(rounds, rounds.date);
            await m.addColumn(rounds, rounds.weather);
            await m.addColumn(rounds, rounds.notes);
          }

          // v4 adds course holes + tee box holes tables
          if (from < 4) {
            await m.createTable(courseHoles);
            await m.createTable(teeBoxHoles);
          }
        },
      );

  // ---------- Courses ----------
  Future<List<Course>> getAllCourses() => select(courses).get();

  Future<void> updateCourseName(int courseId, String name) {
    return (update(courses)..where((c) => c.id.equals(courseId))).write(
      CoursesCompanion(name: Value(name)),
    );
  }

  Future<int> countRoundsForCourse(int courseId) async {
    final q = selectOnly(rounds)
      ..addColumns([rounds.id])
      ..where(rounds.courseId.equals(courseId));
    final rows = await q.get();
    return rows.length;
  }

  Future<bool> deleteCourseIfUnused(int courseId) async {
    final roundCount = await countRoundsForCourse(courseId);
    if (roundCount > 0) return false;

    final teeBoxes = await getTeeBoxesForCourse(courseId);
    if (teeBoxes.isNotEmpty) return false;

    final deleted =
        await (delete(courses)..where((c) => c.id.equals(courseId))).go();
    return deleted > 0;
  }

  // ---------- Tee Boxes ----------
  Future<List<TeeBox>> getTeeBoxesForCourse(int courseId) {
    return (select(teeBoxTable)..where((t) => t.courseId.equals(courseId)))
        .get();
  }

  Future<void> updateTeeBox({
    required int teeBoxId,
    required String name,
    required int yardage,
    required double rating,
    required int slope,
  }) {
    return (update(teeBoxTable)..where((t) => t.id.equals(teeBoxId))).write(
      TeeBoxTableCompanion(
        name: Value(name),
        yardage: Value(yardage),
        rating: Value(rating),
        slope: Value(slope),
      ),
    );
  }

  Future<int> countRoundsForTeeBox(int teeBoxId) async {
    final q = selectOnly(rounds)
      ..addColumns([rounds.id])
      ..where(rounds.teeBoxId.equals(teeBoxId));
    final rows = await q.get();
    return rows.length;
  }

  Future<bool> deleteTeeBoxIfUnused(int teeBoxId) async {
    final count = await countRoundsForTeeBox(teeBoxId);
    if (count > 0) return false;

    final deleted =
        await (delete(teeBoxTable)..where((t) => t.id.equals(teeBoxId))).go();
    return deleted > 0;
  }

  // ---------- Rounds ----------
  Future<int> createRound({required int courseId, required int teeBoxId}) {
    return into(rounds).insert(
      RoundsCompanion.insert(courseId: courseId, teeBoxId: teeBoxId),
    );
  }

  Future<Round?> getRound(int roundId) {
    return (select(rounds)..where((r) => r.id.equals(roundId)))
        .getSingleOrNull();
  }

  Future<void> updateRoundMeta({
    required int roundId,
    DateTime? date,
    String? weather,
    String? notes,
  }) async {
    await (update(rounds)..where((r) => r.id.equals(roundId))).write(
      RoundsCompanion(
        date: date == null ? const Value.absent() : Value(date),
        weather: Value(weather),
        notes: Value(notes),
      ),
    );
  }

  Future<void> markRoundCompleted(int roundId) async {
    await (update(rounds)..where((r) => r.id.equals(roundId))).write(
      const RoundsCompanion(completed: Value(true)),
    );
  }

  Future<List<Round>> getCompletedRounds() {
    return (select(rounds)
          ..where((r) => r.completed.equals(true))
          ..orderBy([(r) => OrderingTerm.desc(r.date)]))
        .get();
  }

  Future<int> createTeeBox({
    required int courseId,
    required String name,
    required int yardage,
    required double rating,
    required int slope,
  }) {
    return into(teeBoxTable).insert(
      TeeBoxTableCompanion.insert(
        courseId: courseId,
        name: name,
        yardage: yardage,
        rating: rating,
        slope: slope,
      ),
    );
  }

  // ---------- Course hole defs ----------
  Future<List<CourseHole>> getCourseHolesForCourse(int courseId) {
    return (select(courseHoles)
          ..where((h) => h.courseId.equals(courseId))
          ..orderBy([(h) => OrderingTerm(expression: h.holeNumber)]))
        .get();
  }

  Future<void> upsertCourseHole({
    required int courseId,
    required int holeNumber,
    required int par,
    int? strokeIndex,
  }) async {
    Value<T> v<T>(T? x) => x == null ? const Value.absent() : Value(x);

    final insert = CourseHolesCompanion(
      courseId: Value(courseId),
      holeNumber: Value(holeNumber),
      par: Value(par),
      strokeIndex: v(strokeIndex),
    );

    final update = CourseHolesCompanion(
      par: Value(par),
      strokeIndex: v(strokeIndex),
    );

    await into(courseHoles).insert(
      insert,
      onConflict: DoUpdate(
        (tbl) => update,
        target: [courseHoles.courseId, courseHoles.holeNumber],
      ),
    );
  }

  // ---------- Tee yardages ----------
  Future<List<TeeBoxHole>> getTeeBoxHoles(int teeBoxId) {
    return (select(teeBoxHoles)
          ..where((h) => h.teeBoxId.equals(teeBoxId))
          ..orderBy([(h) => OrderingTerm(expression: h.holeNumber)]))
        .get();
  }

  Future<void> upsertTeeBoxHole({
    required int teeBoxId,
    required int holeNumber,
    int? yardage,
  }) async {
    Value<T> v<T>(T? x) => x == null ? const Value.absent() : Value(x);

    final insert = TeeBoxHolesCompanion(
      teeBoxId: Value(teeBoxId),
      holeNumber: Value(holeNumber),
      yardage: v(yardage),
    );

    final update = TeeBoxHolesCompanion(
      yardage: v(yardage),
    );

    await into(teeBoxHoles).insert(
      insert,
      onConflict: DoUpdate(
        (tbl) => update,
        target: [teeBoxHoles.teeBoxId, teeBoxHoles.holeNumber],
      ),
    );
  }

  // ---------- Holes (round play) ----------
  Future<Hole?> getHole(int roundId, int holeNumber) {
    return (select(holes)
          ..where((h) =>
              h.roundId.equals(roundId) & h.holeNumber.equals(holeNumber)))
        .getSingleOrNull();
  }

  Future<void> upsertHole({
    required int roundId,
    required int holeNumber,
    int? score,
    int? putts,
    int? penalties,
    String? fir,
    String? approachLocation,
    int? approachDistance,
    int? firstPuttDistance,
  }) async {
    Value<T> v<T>(T? x) => x == null ? const Value.absent() : Value(x);

    final insert = HolesCompanion(
      roundId: Value(roundId),
      holeNumber: Value(holeNumber),
      score: v(score),
      putts: v(putts),
      penalties: v(penalties),
      fir: v(fir),
      approachLocation: v(approachLocation),
      approachDistance: v(approachDistance),
      firstPuttDistance: v(firstPuttDistance),
    );

    // For update, you typically *don’t* want to rewrite roundId/holeNumber
    final update = HolesCompanion(
      score: v(score),
      putts: v(putts),
      penalties: v(penalties),
      fir: v(fir),
      approachLocation: v(approachLocation),
      approachDistance: v(approachDistance),
      firstPuttDistance: v(firstPuttDistance),
    );

    await into(holes).insert(
      insert,
      onConflict: DoUpdate(
        (tbl) => update,
        target: [holes.roundId, holes.holeNumber],
      ),
    );
  }

  Future<List<Hole>> getHolesForRoundOrdered(int roundId) {
    return (select(holes)
          ..where((h) => h.roundId.equals(roundId))
          ..orderBy([(h) => OrderingTerm.asc(h.holeNumber)]))
        .get();
  }

  Future<List<Hole>> getAllHoles() => select(holes).get();

  Future<List<Hole>> getLatestHolesForRound(int roundId, {int limit = 10}) {
    final q = select(holes)
      ..where((h) => h.roundId.equals(roundId))
      ..orderBy([
        (h) => OrderingTerm(expression: h.holeNumber, mode: OrderingMode.desc)
      ])
      ..limit(limit);
    return q.get();
  }

  Future<int?> getGrossScoreForRound(int roundId) async {
    final hs = await getHolesForRoundOrdered(roundId);
    final scores = hs.where((h) => h.score != null).toList();
    if (scores.length < 18) return null;
    return scores.fold<int>(0, (sum, h) => sum + (h.score ?? 0));
  }

  // ---------- Handicap (simple) ----------
  Future<double?> computeSimpleHandicapIndex() async {
    final completed = await getCompletedRounds();
    if (completed.isEmpty) return null;

    final diffs = <double>[];
    for (final r in completed) {
      final gross = await getGrossScoreForRound(r.id);
      if (gross == null) continue;

      final tee = await getTeeBox(r.teeBoxId);
      if (tee == null) continue;
      if (tee.slope <= 0) continue;

      final diff = (gross - tee.rating) * 113.0 / tee.slope;
      diffs.add(diff);
    }

    if (diffs.isEmpty) return null;
    final avg = diffs.reduce((a, b) => a + b) / diffs.length;
    return double.parse(avg.toStringAsFixed(1));
  }

  Future<List<Round>> getAllRounds() {
    return (select(rounds)..orderBy([(r) => OrderingTerm.desc(r.date)])).get();
  }

  Future<void> deleteRound(int roundId) async {
    await transaction(() async {
      await (delete(holes)..where((h) => h.roundId.equals(roundId))).go();
      await (delete(rounds)..where((r) => r.id.equals(roundId))).go();
    });
  }

  Future<Round?> getLatestInProgressRound() {
    return (select(rounds)
          ..where((r) => r.completed.equals(false))
          ..orderBy([(r) => OrderingTerm.desc(r.date)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<Round>> getInProgressRounds() {
    return (select(rounds)
          ..where((r) => r.completed.equals(false))
          ..orderBy([(r) => OrderingTerm.desc(r.date)]))
        .get();
  }

  Future<void> setRoundCompleted(int roundId, bool completed) async {
    await (update(rounds)..where((r) => r.id.equals(roundId))).write(
      RoundsCompanion(completed: Value(completed)),
    );
  }

  Future<int?> getLatestHoleNumberForRound(int roundId) async {
    final result = await (select(holes)
          ..where((h) => h.roundId.equals(roundId))
          ..orderBy([(h) => OrderingTerm.desc(h.holeNumber)])
          ..limit(1))
        .getSingleOrNull();

    return result?.holeNumber;
  }

  Future<Course?> getCourse(int id) {
    return (select(courses)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<TeeBox?> getTeeBox(int teeBoxId) {
    return (select(teeBoxTable)..where((t) => t.id.equals(teeBoxId)))
        .getSingleOrNull();
  }

  Future<List<Hole>> getHolesForRound(int roundId) {
    return (select(holes)..where((h) => h.roundId.equals(roundId))).get();
  }

  // Completed rounds newest-first (since you don’t have a date column)
  Future<List<Round>> getCompletedRoundsNewestFirst() {
    return (select(rounds)
          ..where((r) => r.completed.equals(true))
          ..orderBy([(r) => OrderingTerm.desc(r.date)]))
        .get();
  }

  Future<List<TeeBox>> getAllTeeBoxes() => select(teeBoxTable).get();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'golf_scorecard.sqlite'));
    return NativeDatabase(file);
  });
}
