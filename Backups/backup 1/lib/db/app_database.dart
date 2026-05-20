import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'app_database.g.dart';

class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get teesPlayed => text()();
  RealColumn get rating => real()();
  IntColumn get slope => integer()();
  IntColumn get par => integer()();
}

class Rounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get courseId => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get notes => text().nullable()();
}

class HolesPlayed extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roundId => integer()();
  IntColumn get holeNumber => integer()();
  IntColumn get score => integer().nullable()();
  IntColumn get putts => integer().nullable()();
  TextColumn get fir => text().nullable()();
  TextColumn get approachLocation => text().nullable()();
  IntColumn get approachDistance => integer().nullable()();
  IntColumn get firstPuttDistance => integer().nullable()();
  IntColumn get penalties => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [Courses, Rounds, HolesPlayed])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<List<RoundsData>> getAllRounds() => select(rounds).get();

  Future<List<HolesPlayedData>> getHolesForRound(int roundId) {
    return (select(holesPlayed)..where((tbl) => tbl.roundId.equals(roundId)))
        .get();
  }

  Future<int> insertRound(RoundsCompanion round) => into(rounds).insert(round);

  Future<int> insertHole(HolesPlayedCompanion hole) =>
      into(holesPlayed).insert(hole);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));
    return NativeDatabase(file);
  });
}
