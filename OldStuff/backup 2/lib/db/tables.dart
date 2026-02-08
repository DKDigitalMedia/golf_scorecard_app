// @dart=3.0
import 'package:drift/drift.dart';

class Rounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
}

class Holes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roundId =>
      integer().customConstraint('REFERENCES rounds(id) NOT NULL')();
  IntColumn get holeNumber => integer()();
  IntColumn get par => integer()();
  IntColumn get score => integer()();
  IntColumn get putts => integer()();
  IntColumn get penalties => integer()();
  TextColumn get fir => text().nullable()();
  TextColumn get approachLocation => text().nullable()();
  RealColumn get approachDistance => real().withDefault(const Constant(0))();
  RealColumn get firstPuttDistance => real().withDefault(const Constant(0))();
  BoolColumn get gir => boolean().withDefault(const Constant(false))();
  BoolColumn get upAndDown => boolean().withDefault(const Constant(false))();
}
