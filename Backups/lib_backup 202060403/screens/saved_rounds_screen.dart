import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'round_summary_screen.dart';

class SavedRoundsScreen extends ConsumerStatefulWidget {
  const SavedRoundsScreen({super.key});

  @override
  ConsumerState<SavedRoundsScreen> createState() => _SavedRoundsScreenState();
}

class _SavedRoundsScreenState extends ConsumerState<SavedRoundsScreen> {
  Future<List<_SavedRoundRow>>? _future;

  String _formatDate(DateTime dt) {
    final m = dt.month;
    final d = dt.day;
    final y = dt.year;

    var hour = dt.hour;
    final minute = dt.minute;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;

    final mm = minute.toString().padLeft(2, '0');
    return '$m/$d/$y $hour:$mm $ampm';
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_SavedRoundRow>> _load() async {
    final db = ref.read(databaseProvider);

    final all = await db.getCompletedRoundsNewestFirst();
    final rounds = all.length > 200 ? all.take(200).toList() : all;
    if (rounds.isEmpty) return <_SavedRoundRow>[];

    // Resolve course + tee info (best-effort) for display.
    final rows = await Future.wait<_SavedRoundRow>(rounds.map((r) async {
      final course = await db.getCourse(r.courseId);
      final tee = await db.getTeeBox(r.teeBoxId);
      return _SavedRoundRow(round: r, course: course, tee: tee);
    }));

    return rows;
  }

  Future<void> _deleteRound(BuildContext context, int roundId) async {
    final db = ref.read(databaseProvider);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete round?'),
        content: const Text(
            'This will permanently delete the round and all hole data.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    await db.deleteRound(roundId);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Round deleted')),
    );

    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Rounds'),
      ),
      body: FutureBuilder<List<_SavedRoundRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load rounds: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rows = snapshot.data ?? <_SavedRoundRow>[];
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No saved rounds yet.'),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _load();
              });
              await _future;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = rows[i];

                final title = row.course?.name ?? 'Course';
                final teeName = row.tee?.name;

                final dateStr = _formatDate(row.round.date);

                return ListTile(
                  title: Text(title),
                  subtitle: Text(
                    teeName == null ? dateStr : '$dateStr • $teeName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'delete') {
                        await _deleteRound(context, row.round.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            RoundSummaryScreen(roundId: row.round.id),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SavedRoundRow {
  final Round round;
  final Course? course;
  final TeeBox? tee;

  const _SavedRoundRow({
    required this.round,
    required this.course,
    required this.tee,
  });
}
