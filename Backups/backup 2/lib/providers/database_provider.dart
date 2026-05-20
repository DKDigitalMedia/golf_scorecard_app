import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});
