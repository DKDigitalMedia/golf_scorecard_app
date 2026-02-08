import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'package:share_plus/share_plus.dart';

class RoundSummaryScreen extends ConsumerWidget {
  final int roundId;

  const RoundSummaryScreen({super.key, required this.roundId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Round Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share round',
            onPressed: () async {
              try {
                final text = await _buildShareText(ref);
                if (text.isEmpty) return;

                final box = context.findRenderObject() as RenderBox?;
                final origin = box == null
                    ? const Rect.fromLTWH(0, 0, 1, 1)
                    : (box.localToGlobal(Offset.zero) & box.size);

                await Share.share(
                  text,
                  sharePositionOrigin: origin,
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Share failed: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<_RoundSummaryData>(
        future: _load(db, roundId),
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!;

          final frontHoles = List<int>.generate(9, (i) => i + 1);
          final backHoles = List<int>.generate(9, (i) => i + 10);

          int parOf(int holeNumber) =>
              data.courseHolesByNumber[holeNumber]?.par ?? 0;

          int? scoreOf(int holeNumber) => data.holeByNumber[holeNumber]?.score;

          int? puttsOf(int holeNumber) => data.holeByNumber[holeNumber]?.putts;

          int? pensOf(int holeNumber) =>
              data.holeByNumber[holeNumber]?.penalties;

          String? firOf(int holeNumber) => data.holeByNumber[holeNumber]?.fir;

          int sumScores(List<int> holes) =>
              holes.fold(0, (s, n) => s + (scoreOf(n) ?? 0));

          int sumPars(List<int> holes) => holes.fold(0, (s, n) => s + parOf(n));

          final frontScore = sumScores(frontHoles);
          final backScore = sumScores(backHoles);
          final totalScore = frontScore + backScore;

          final frontPar = sumPars(frontHoles);
          final backPar = sumPars(backHoles);
          final totalPar = frontPar + backPar;

          final toPar = totalScore - totalPar;

          // Simple stats
          int firOpps = 0, firHits = 0;
          int girOpps = 0, girHits = 0;
          int totalPutts = 0;
          int totalPens = 0;

          for (int n = 1; n <= 18; n++) {
            final par = parOf(n);
            final score = scoreOf(n);
            final putts = puttsOf(n);

            final p = pensOf(n);
            if (p != null) totalPens += p;

            if (putts != null) totalPutts += putts;

            // FIR only on par 4/5
            if (par == 4 || par == 5) {
              firOpps++;
              if (firOf(n) == 'C') firHits++;
            }

            // GIR if strokes-to-green <= par - 2
            if (par != 0 && score != null && putts != null) {
              girOpps++;
              final strokesToGreen = score - putts;
              final gir = strokesToGreen <= (par - 2);
              if (gir) girHits++;
            }
          }

          double? pct(int hits, int opps) =>
              opps == 0 ? null : (hits / opps) * 100.0;

          final firPct = pct(firHits, firOpps);
          final girPct = pct(girHits, girOpps);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(
                courseName: data.courseName,
                teeName: data.teeName,
                totalScore: totalScore,
                totalPar: totalPar,
                toPar: toPar,
                frontScore: frontScore,
                frontPar: frontPar,
                backScore: backScore,
                backPar: backPar,
                firPct: firPct,
                girPct: girPct,
                totalPutts: totalPutts,
                totalPenalties: totalPens,
              ),
              const SizedBox(height: 16),
              _ScorecardCard(
                title: 'Front 9',
                holes: frontHoles,
                parOf: parOf,
                scoreOf: scoreOf,
              ),
              const SizedBox(height: 16),
              _ScorecardCard(
                title: 'Back 9',
                holes: backHoles,
                parOf: parOf,
                scoreOf: scoreOf,
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<_RoundSummaryData> _load(AppDatabase db, int roundId) async {
    final round = await db.getRound(roundId);
    if (round == null) {
      throw Exception('Round not found');
    }

    final course = await db.getCourse(round.courseId);
    final tee = await db.getTeeBox(round.teeBoxId);

    final courseHoles = await db.getCourseHolesForCourse(round.courseId);
    final courseHolesByNumber = <int, CourseHole>{
      for (final h in courseHoles) h.holeNumber: h
    };

    final holes = await db.getHolesForRound(roundId);
    final holeByNumber = <int, Hole>{for (final h in holes) h.holeNumber: h};

    return _RoundSummaryData(
      courseName: course?.name ?? 'Course',
      teeName: tee?.name ?? 'Tee',
      courseHolesByNumber: courseHolesByNumber,
      holeByNumber: holeByNumber,
    );
  }

  Future<String> _buildShareText(WidgetRef ref) async {
    final db = ref.read(databaseProvider);

    final round = await db.getRound(roundId);
    if (round == null) return '';

    final course = await db.getCourse(round.courseId);
    final tee = await db.getTeeBox(round.teeBoxId);
    final holes = await db.getHolesForRoundOrdered(round.id);
    final courseHoles = await db.getCourseHolesForCourse(round.courseId);

    final score = holes.fold<int>(0, (s, h) => s + (h.score ?? 0));
    final par = courseHoles.fold<int>(0, (s, h) => s + h.par);
    final toPar = score - par;

    final date = round.date.toLocal();
    final dateStr = '${date.month}/${date.day}/${date.year}';
    final toParStr = toPar == 0 ? 'E' : (toPar > 0 ? '+$toPar' : '$toPar');

    return '🏌️ Golf Round\n'
        '${course?.name ?? 'Course'} (${tee?.name ?? 'Tee'})\n'
        '$dateStr\n\n'
        'Score: $score ($toParStr)\n'
        'Holes played: ${holes.length}/18';
  }
}

class _RoundSummaryData {
  final String courseName;
  final String teeName;
  final Map<int, CourseHole> courseHolesByNumber;
  final Map<int, Hole> holeByNumber;

  _RoundSummaryData({
    required this.courseName,
    required this.teeName,
    required this.courseHolesByNumber,
    required this.holeByNumber,
  });
}

class _HeaderCard extends StatelessWidget {
  final String courseName;
  final String teeName;

  final int totalScore;
  final int totalPar;
  final int toPar;

  final int frontScore;
  final int frontPar;
  final int backScore;
  final int backPar;

  final double? firPct;
  final double? girPct;
  final int totalPutts;
  final int totalPenalties;

  const _HeaderCard({
    required this.courseName,
    required this.teeName,
    required this.totalScore,
    required this.totalPar,
    required this.toPar,
    required this.frontScore,
    required this.frontPar,
    required this.backScore,
    required this.backPar,
    required this.firPct,
    required this.girPct,
    required this.totalPutts,
    required this.totalPenalties,
  });

  String _fmtToPar(int v) {
    if (v == 0) return 'E';
    return v > 0 ? '+$v' : '$v';
  }

  String _fmtPct(double? v) => v == null ? '-' : '${v.toStringAsFixed(0)}%';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$courseName — $teeName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _bigStat(
                    label: 'Total',
                    value: '$totalScore (${_fmtToPar(toPar)})',
                    sub: 'Par $totalPar',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _bigStat(
                    label: 'Front / Back',
                    value: '$frontScore / $backScore',
                    sub: 'Par $frontPar / $backPar',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _pill('FIR', _fmtPct(firPct)),
                _pill('GIR', _fmtPct(girPct)),
                _pill('Putts', totalPutts.toString()),
                _pill('Penalties', totalPenalties.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigStat({
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ScorecardCard extends StatelessWidget {
  final String title;
  final List<int> holes;

  final int Function(int holeNumber) parOf;
  final int? Function(int holeNumber) scoreOf;

  const _ScorecardCard({
    required this.title,
    required this.holes,
    required this.parOf,
    required this.scoreOf,
  });

  @override
  Widget build(BuildContext context) {
    final totalPar = holes.fold(0, (s, n) => s + parOf(n));
    final totalScore = holes.fold(0, (s, n) => s + (scoreOf(n) ?? 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(60),
                1: FixedColumnWidth(60),
                2: FixedColumnWidth(80),
              },
              children: [
                const TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child:
                          Text('Hole', style: TextStyle(color: Colors.black54)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child:
                          Text('Par', style: TextStyle(color: Colors.black54)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Score',
                          style: TextStyle(color: Colors.black54)),
                    ),
                  ],
                ),
                for (final n in holes)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(n.toString()),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(parOf(n) == 0 ? '-' : parOf(n).toString()),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(scoreOf(n)?.toString() ?? '-'),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal (Par $totalPar)',
                    style: const TextStyle(color: Colors.black54)),
                Text(
                  totalScore.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
