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
  /// true = only completed, false = all (completed + in-progress)
  bool _completedOnly = true;

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year}';
  }

  String _vsParStr(int? vsPar) {
    if (vsPar == null) return '-';
    if (vsPar == 0) return 'E';
    return vsPar > 0 ? '+$vsPar' : '$vsPar';
  }

  Future<_RoundListRow> _buildRowData(AppDatabase db, Round r) async {
    // Course + tee names handled outside; here we compute score / par / vs-par.
    final holes = await db.getHolesForRoundOrdered(r.id);

    // Only compute gross if all 18 scores exist
    int scoreCount = 0;
    int totalScore = 0;
    for (final h in holes) {
      if (h.score != null) {
        scoreCount++;
        totalScore += h.score!;
      }
    }
    final gross = (scoreCount == 18) ? totalScore : null;

    // Round par comes from course holes.
    // If your schema guarantees 18 holes exist, this should always work.
    final courseHoles = await db.getCourseHolesForCourse(r.courseId);

    int parCount = 0;
    int totalPar = 0;
    for (final ch in courseHoles) {
      // expecting holeNumber 1..18
      parCount++;
      totalPar += ch.par;
    }
    final par = (parCount == 18) ? totalPar : null;

    final vsPar = (gross != null && par != null) ? (gross - par) : null;

    // Putts + penalties (optional)
    int puttsTotal = 0;
    int puttsCount = 0;
    int penTotal = 0;
    int penCount = 0;

    for (final h in holes) {
      if (h.putts != null) {
        puttsTotal += h.putts!;
        puttsCount++;
      }
      if (h.penalties != null) {
        penTotal += h.penalties!;
        penCount++;
      }
    }

    return _RoundListRow(
      gross: gross,
      par: par,
      vsPar: vsPar,
      putts: puttsCount == 0 ? null : puttsTotal,
      penalties: penCount == 0 ? null : penTotal,
      holesEntered: holes.length,
    );
  }

  Future<void> _confirmDelete(AppDatabase db, Round r, String titleLine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete round?'),
        content: Text(
          'This will permanently delete the round and all hole entries:\n\n$titleLine',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await db.deleteRound(r.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Round deleted.')),
    );
    setState(() {}); // refresh list
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Rounds'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                const Text('Completed'),
                Switch(
                  value: _completedOnly,
                  onChanged: (v) => setState(() => _completedOnly = v),
                ),
              ],
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          _completedOnly ? db.getCompletedRounds() : db.getAllRounds(),
          db.getAllCourses(),
          db.select(db.teeBoxTable).get(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rounds = snapshot.data![0] as List<Round>;
          final courses = snapshot.data![1] as List<Course>;
          final tees = snapshot.data![2] as List<TeeBox>;

          final courseById = {for (final c in courses) c.id: c};
          final teeById = {for (final t in tees) t.id: t};

          if (rounds.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _completedOnly
                      ? 'No completed rounds yet.\nFinish a round to see it here.'
                      : 'No rounds yet.\nStart a round from the main menu.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Sort newest first (defensive)
          rounds.sort((a, b) => b.date.compareTo(a.date));

          return ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (context, i) {
              final r = rounds[i];

              final courseName =
                  courseById[r.courseId]?.name ?? 'Unknown course';
              final teeName = teeById[r.teeBoxId]?.name ?? 'Unknown tee';
              final dateStr = _fmtDate(r.date);

              final statusChip = r.completed
                  ? const Chip(label: Text('Completed'))
                  : const Chip(label: Text('In progress'));

              final titleLine = '$courseName • $teeName • $dateStr';

              return Card(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoundSummaryScreen(roundId: r.id),
                      ),
                    );
                  },
                  onLongPress: () => _confirmDelete(db, r, titleLine),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                courseName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            statusChip,
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$teeName • $dateStr',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 10),

                        // Totals line (gross, par, vs par, putts, pens)
                        FutureBuilder<_RoundListRow>(
                          future: _buildRowData(db, r),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const LinearProgressIndicator(
                                  minHeight: 2);
                            }
                            final row = snap.data!;

                            final grossStr = row.gross?.toString() ?? '-';
                            final parStr = row.par?.toString() ?? '-';
                            final vsParStr = _vsParStr(row.vsPar);
                            final puttsStr = row.putts?.toString() ?? '-';
                            final pensStr = row.penalties?.toString() ?? '-';

                            return Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _pill('Score', grossStr),
                                _pill('Par', parStr),
                                _pill('Vs', vsParStr),
                                _pill('Putts', puttsStr),
                                _pill('Pen', pensStr),
                                _pill('Holes', '${row.holesEntered}/18'),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _RoundListRow {
  final int? gross;
  final int? par;
  final int? vsPar;
  final int? putts;
  final int? penalties;
  final int holesEntered;

  _RoundListRow({
    required this.gross,
    required this.par,
    required this.vsPar,
    required this.putts,
    required this.penalties,
    required this.holesEntered,
  });
}
