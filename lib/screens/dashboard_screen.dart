import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'round_summary_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: FutureBuilder<_DashboardData>(
        future: _load(db),
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!;
          if (data.rounds.isEmpty) {
            return const Center(
              child: Text(
                'No completed rounds yet.\nFinish a round to see stats.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatsCard(data.stats),
              const SizedBox(height: 12),
              if (data.rounds.length >= 3) ...[
                _RecentFormCard(data.recentForm),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 700;

                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TeeShotsBox(
                                left: _fmtPctStatic(data.stats.firLeftPct),
                                center: _fmtPctStatic(data.stats.firCenterPct),
                                right: _fmtPctStatic(data.stats.firRightPct),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ApproachShotsBox(
                                left: _fmtPctStatic(data.stats.approachLeftPct),
                                center: _fmtPctStatic(
                                  data.stats.approachCenterPct,
                                ),
                                right: _fmtPctStatic(
                                  data.stats.approachRightPct,
                                ),
                                long: _fmtPctStatic(data.stats.approachLongPct),
                                short: _fmtPctStatic(
                                  data.stats.approachShortPct,
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TeeShotsBox(
                            left: _fmtPctStatic(data.stats.firLeftPct),
                            center: _fmtPctStatic(data.stats.firCenterPct),
                            right: _fmtPctStatic(data.stats.firRightPct),
                          ),
                          const SizedBox(height: 16),
                          ApproachShotsBox(
                            left: _fmtPctStatic(data.stats.approachLeftPct),
                            center: _fmtPctStatic(data.stats.approachCenterPct),
                            right: _fmtPctStatic(data.stats.approachRightPct),
                            long: _fmtPctStatic(data.stats.approachLongPct),
                            short: _fmtPctStatic(data.stats.approachShortPct),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ParBreakdownCard(data.parBreakdown),
              const SizedBox(height: 16),
              const Text(
                'Recent Completed Rounds',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...data.rounds.map((r) {
                final courseName = data.courseNameById[r.courseId] ?? 'Course';
                final teeName = data.teeNameById[r.teeBoxId] ?? 'Tee';

                final total = data.totalScoreByRoundId[r.id] ?? 0;
                final par = data.totalParByRoundId[r.id] ?? 0;
                final toPar = total - par;
                final putts = data.totalPuttsByRoundId[r.id] ?? 0;
                final girPct = data.girPctByRoundId[r.id];

                String fmtToPar(int v) {
                  if (v == 0) return 'E';
                  return v > 0 ? '+$v' : '$v';
                }

                Color toParColor(int v) {
                  if (v < 0) return Colors.green.shade700;
                  if (v > 0) return Colors.red.shade700;
                  return Colors.black87;
                }

                String fmtPct(double? v) =>
                    v == null ? '-' : '${v.toStringAsFixed(0)}%';

                final dateStr = MaterialLocalizations.of(
                  context,
                ).formatShortDate(r.date);

                return Card(
                  child: ListTile(
                    title: Text('$courseName — $teeName'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$dateStr  •  Par $par'),
                        const SizedBox(height: 2),
                        Text(
                          'Putts $putts  •  GIR ${fmtPct(girPct)}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          fmtToPar(toPar),
                          style: TextStyle(
                            color: toParColor(toPar),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RoundSummaryScreen(roundId: r.id),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  static String _fmtPctStatic(double? v) =>
      v == null ? '-' : '${v.toStringAsFixed(0)}%';

  static Future<_DashboardData> _load(AppDatabase db) async {
    // Completed rounds, newest first
    final rounds = await db.getCompletedRoundsNewestFirst();
    if (rounds.isEmpty) return _DashboardData.empty();

    // Names lookup
    final courses = await db.getAllCourses();
    final tees = await db.getAllTeeBoxes();

    final courseNameById = <int, String>{for (final c in courses) c.id: c.name};
    final teeNameById = <int, String>{for (final t in tees) t.id: t.name};

    // Aggregate stats across all completed rounds
    int roundsCount = 0;

    int sumScore = 0;
    int sumPar = 0;

    int firOpps = 0;
    int firHits = 0;
    int firLeft = 0;
    int firCenter = 0;
    int firRight = 0;
    int girOpps = 0;
    int girHits = 0;
    int approachOpps = 0;
    int approachLeft = 0;
    int approachCenter = 0;
    int approachRight = 0;
    int approachLong = 0;
    int approachShort = 0;

    int totalPutts = 0;
    int puttHoleCount = 0;

    int totalPenalties = 0;

    int sandOpps = 0;
    int sandSaves = 0;

    int? bestScore;
    int? bestToPar;
    final recentRoundScores = <int>[];
    final allRoundScores = <int>[];

    // Breakdown by par (3/4/5)
    final parScoreSum = <int, int>{3: 0, 4: 0, 5: 0};
    final parHoleCount = <int, int>{3: 0, 4: 0, 5: 0};

    final parGirOpps = <int, int>{3: 0, 4: 0, 5: 0};
    final parGirHits = <int, int>{3: 0, 4: 0, 5: 0};

    final parPuttSum = <int, int>{3: 0, 4: 0, 5: 0};
    final parPuttCount = <int, int>{3: 0, 4: 0, 5: 0};

    final parPenaltySum = <int, int>{3: 0, 4: 0, 5: 0};
    final parPenaltyCount = <int, int>{3: 0, 4: 0, 5: 0};
    final parParSum = <int, int>{3: 0, 4: 0, 5: 0};

    final totalScoreByRoundId = <int, int>{};
    final totalParByRoundId = <int, int>{};
    final totalPuttsByRoundId = <int, int>{};
    final girPctByRoundId = <int, double>{};

    for (final r in rounds) {
      roundsCount++;

      final holes = await db.getHolesForRoundOrdered(r.id);

      // Par map for this round (from the course)
      final courseHoles = await db.getCourseHolesForCourse(r.courseId);
      final parByHole = <int, int>{
        for (final ch in courseHoles) ch.holeNumber: ch.par,
      };

      int roundScore = 0;
      int roundPar = 0;
      int roundPutts = 0;
      int roundGirOpps = 0;
      int roundGirHits = 0;

      for (final h in holes) {
        final par = parByHole[h.holeNumber] ?? 0;
        roundPar += par;

        if (par == 3 || par == 4 || par == 5) {
          parHoleCount[par] = (parHoleCount[par] ?? 0) + 1;
          parScoreSum[par] = (parScoreSum[par] ?? 0) + (h.score ?? 0);
          parParSum[par] = (parParSum[par] ?? 0) + par;

          if (h.penalties != null) {
            parPenaltySum[par] = (parPenaltySum[par] ?? 0) + h.penalties!;
            parPenaltyCount[par] = (parPenaltyCount[par] ?? 0) + 1;
          }

          if (h.putts != null) {
            parPuttSum[par] = (parPuttSum[par] ?? 0) + h.putts!;
            parPuttCount[par] = (parPuttCount[par] ?? 0) + 1;
          }
        }

        roundScore += (h.score ?? 0);

        // FIR: only meaningful on par 4/5
        if (par == 4 || par == 5) {
          firOpps++;
          if (h.fir == 'L') firLeft++;
          if (h.fir == 'C') {
            firCenter++;
            firHits++;
          }
          if (h.fir == 'R') firRight++;
        }

        if (h.approachLocation != null) {
          approachOpps++;
          if (h.approachLocation == 'L') approachLeft++;
          if (h.approachLocation == 'C') approachCenter++;
          if (h.approachLocation == 'R') approachRight++;
          if (h.approachLocation == 'LONG') approachLong++;
          if (h.approachLocation == 'SHORT') approachShort++;
        }

        // GIR: requires score + putts + par
        if (par != 0 && h.score != null && h.putts != null) {
          girOpps++;
          final strokesToGreen = h.score! - h.putts!;
          final gir = strokesToGreen <= (par - 2);
          roundGirOpps++;
          if (gir) {
            girHits++;
            roundGirHits++;
          }
          if (par == 3 || par == 4 || par == 5) {
            parGirOpps[par] = (parGirOpps[par] ?? 0) + 1;
            if (gir) {
              parGirHits[par] = (parGirHits[par] ?? 0) + 1;
            }
          }

          // Sand save: bunker + missed GIR + par/better
          if (h.greensideBunker == true) {
            sandOpps++;
            if (!gir && h.score! <= par) sandSaves++;
          }
        }

        if (h.putts != null) {
          totalPutts += h.putts!;
          puttHoleCount++;
          roundPutts += h.putts!;
        }
        if (h.penalties != null) {
          totalPenalties += h.penalties!;
        }
      }

      sumScore += roundScore;
      sumPar += roundPar;

      totalScoreByRoundId[r.id] = roundScore;
      totalParByRoundId[r.id] = roundPar;

      totalPuttsByRoundId[r.id] = roundPutts;
      if (roundGirOpps > 0) {
        girPctByRoundId[r.id] = (roundGirHits / roundGirOpps) * 100.0;
      }

      final roundToPar = roundScore - roundPar;
      bestScore = bestScore == null
          ? roundScore
          : (roundScore < bestScore! ? roundScore : bestScore);
      bestToPar = bestToPar == null
          ? roundToPar
          : (roundToPar < bestToPar! ? roundToPar : bestToPar);
      if (recentRoundScores.length < 3) {
        recentRoundScores.add(roundScore);
      }
      allRoundScores.add(roundScore);
    }

    double? pct(int hits, int opps) => opps == 0 ? null : (hits / opps) * 100.0;

    final stats = _DashboardStats(
      roundsCount: roundsCount,
      avgScore: roundsCount == 0 ? null : (sumScore / roundsCount),
      avgToPar: roundsCount == 0 ? null : ((sumScore - sumPar) / roundsCount),
      bestScore: bestScore,
      bestToPar: bestToPar,
      last3AvgScore: recentRoundScores.isEmpty
          ? null
          : (recentRoundScores.reduce((a, b) => a + b) /
                recentRoundScores.length),
      firPct: pct(firHits, firOpps),
      girPct: pct(girHits, girOpps),
      avgPuttsPerHole: puttHoleCount == 0 ? null : (totalPutts / puttHoleCount),
      avgPenaltiesPerRound: roundsCount == 0
          ? null
          : (totalPenalties / roundsCount),
      sandSavePct: pct(sandSaves, sandOpps),
      firLeftPct: pct(firLeft, firOpps),
      firCenterPct: pct(firCenter, firOpps),
      firRightPct: pct(firRight, firOpps),
      approachLeftPct: pct(approachLeft, approachOpps),
      approachCenterPct: pct(approachCenter, approachOpps),
      approachRightPct: pct(approachRight, approachOpps),
      approachLongPct: pct(approachLong, approachOpps),
      approachShortPct: pct(approachShort, approachOpps),
    );

    double? pctByPar(int par, Map<int, int> hits, Map<int, int> opps) {
      final o = opps[par] ?? 0;
      if (o == 0) return null;
      return ((hits[par] ?? 0) / o) * 100.0;
    }

    double? avgByPar(int par, Map<int, int> sum, Map<int, int> count) {
      final c = count[par] ?? 0;
      if (c == 0) return null;
      return (sum[par] ?? 0) / c;
    }

    final parBreakdown = _ParBreakdown(
      par3: _ParLine(
        holes: parHoleCount[3] ?? 0,
        avgScore: avgByPar(3, parScoreSum, parHoleCount),
        avgToPar: (avgByPar(3, parScoreSum, parHoleCount) ?? 0) - 3,
        girPct: pctByPar(3, parGirHits, parGirOpps),
        avgPutts: avgByPar(3, parPuttSum, parPuttCount),
        avgPenalties: avgByPar(3, parPenaltySum, parPenaltyCount),
      ),
      par4: _ParLine(
        holes: parHoleCount[4] ?? 0,
        avgScore: avgByPar(4, parScoreSum, parHoleCount),
        avgToPar: (avgByPar(4, parScoreSum, parHoleCount) ?? 0) - 4,
        girPct: pctByPar(4, parGirHits, parGirOpps),
        avgPutts: avgByPar(4, parPuttSum, parPuttCount),
        avgPenalties: avgByPar(4, parPenaltySum, parPenaltyCount),
      ),
      par5: _ParLine(
        holes: parHoleCount[5] ?? 0,
        avgScore: avgByPar(5, parScoreSum, parHoleCount),
        avgToPar: (avgByPar(5, parScoreSum, parHoleCount) ?? 0) - 5,
        girPct: pctByPar(5, parGirHits, parGirOpps),
        avgPutts: avgByPar(5, parPuttSum, parPuttCount),
        avgPenalties: avgByPar(5, parPenaltySum, parPenaltyCount),
      ),
    );

    double? avgList(List<int> values) {
      if (values.isEmpty) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    final last3 = allRoundScores.take(3).toList();
    final last5 = allRoundScores.take(5).toList();
    final previous3 = allRoundScores.skip(3).take(3).toList();

    final recentForm = _RecentForm(
      last3Avg: avgList(last3),
      last5Avg: avgList(last5),
      previous3Avg: avgList(previous3),
      bestRecent: last3.isEmpty ? null : last3.reduce((a, b) => a < b ? a : b),
      worstRecent: last3.isEmpty ? null : last3.reduce((a, b) => a > b ? a : b),
      trend: (avgList(last3) != null && avgList(previous3) != null)
          ? avgList(previous3)! - avgList(last3)!
          : null,
    );

    return _DashboardData(
      rounds: rounds,
      stats: stats,
      parBreakdown: parBreakdown,
      courseNameById: courseNameById,
      teeNameById: teeNameById,
      totalScoreByRoundId: totalScoreByRoundId,
      totalParByRoundId: totalParByRoundId,
      totalPuttsByRoundId: totalPuttsByRoundId,
      girPctByRoundId: girPctByRoundId,
      recentForm: recentForm,
    );
  }
}

class _DashboardData {
  final List<Round> rounds;
  final _DashboardStats stats;
  final _ParBreakdown parBreakdown;
  final _RecentForm recentForm;

  final Map<int, String> courseNameById;
  final Map<int, String> teeNameById;

  final Map<int, int> totalScoreByRoundId;
  final Map<int, int> totalParByRoundId;

  final Map<int, int> totalPuttsByRoundId;
  final Map<int, double> girPctByRoundId;

  _DashboardData({
    required this.rounds,
    required this.stats,
    required this.parBreakdown,
    required this.courseNameById,
    required this.teeNameById,
    required this.totalScoreByRoundId,
    required this.totalParByRoundId,
    required this.totalPuttsByRoundId,
    required this.girPctByRoundId,
    required this.recentForm,
  });

  factory _DashboardData.empty() => _DashboardData(
    rounds: const [],
    stats: _DashboardStats.empty(),
    parBreakdown: _ParBreakdown.empty(),
    recentForm: _RecentForm.empty(),
    courseNameById: const {},
    teeNameById: const {},
    totalScoreByRoundId: const {},
    totalParByRoundId: const {},
    totalPuttsByRoundId: const {},
    girPctByRoundId: const {},
  );
}

class _RecentForm {
  final double? last3Avg;
  final double? last5Avg;
  final double? previous3Avg;
  final int? bestRecent;
  final int? worstRecent;
  final double? trend;

  const _RecentForm({
    required this.last3Avg,
    required this.last5Avg,
    required this.previous3Avg,
    required this.bestRecent,
    required this.worstRecent,
    required this.trend,
  });

  factory _RecentForm.empty() => const _RecentForm(
    last3Avg: null,
    last5Avg: null,
    previous3Avg: null,
    bestRecent: null,
    worstRecent: null,
    trend: null,
  );
}

class _DashboardStats {
  final int roundsCount;
  final double? avgScore;
  final double? avgToPar;
  final int? bestScore;
  final int? bestToPar;
  final double? last3AvgScore;
  final double? firPct;
  final double? girPct;
  final double? avgPuttsPerHole;
  final double? avgPenaltiesPerRound;
  final double? sandSavePct;
  final double? firLeftPct;
  final double? firCenterPct;
  final double? firRightPct;
  final double? approachLeftPct;
  final double? approachCenterPct;
  final double? approachRightPct;
  final double? approachLongPct;
  final double? approachShortPct;

  _DashboardStats({
    required this.roundsCount,
    required this.avgScore,
    required this.avgToPar,
    required this.bestScore,
    required this.bestToPar,
    required this.last3AvgScore,
    required this.firPct,
    required this.girPct,
    required this.avgPuttsPerHole,
    required this.avgPenaltiesPerRound,
    required this.sandSavePct,
    required this.firLeftPct,
    required this.firCenterPct,
    required this.firRightPct,
    required this.approachLeftPct,
    required this.approachCenterPct,
    required this.approachRightPct,
    required this.approachLongPct,
    required this.approachShortPct,
  });

  factory _DashboardStats.empty() => _DashboardStats(
    roundsCount: 0,
    avgScore: null,
    avgToPar: null,
    bestScore: null,
    bestToPar: null,
    last3AvgScore: null,
    firPct: null,
    girPct: null,
    avgPuttsPerHole: null,
    avgPenaltiesPerRound: null,
    sandSavePct: null,
    firLeftPct: null,
    firCenterPct: null,
    firRightPct: null,
    approachLeftPct: null,
    approachCenterPct: null,
    approachRightPct: null,
    approachLongPct: null,
    approachShortPct: null,
  );
}

class _StatsCard extends StatelessWidget {
  final _DashboardStats s;

  const _StatsCard(this.s);

  String _fmt(double? v, {int digits = 1}) =>
      v == null ? '-' : v.toStringAsFixed(digits);

  String _fmtPct(double? v) => v == null ? '-' : '${v.toStringAsFixed(0)}%';

  String _fmtIntToPar(int? v) {
    if (v == null) return '-';
    if (v == 0) return 'E';
    return v > 0 ? '+$v' : '$v';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stats Overview (${s.roundsCount} completed rounds)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _section('Scoring', [
              _pill('Avg Score', _fmt(s.avgScore)),
              _pill('Avg To Par', _fmt(s.avgToPar)),
              _pill('Best Score', s.bestScore?.toString() ?? '-'),
              _pill('Best To Par', _fmtIntToPar(s.bestToPar)),
              _pill('Last 3 Avg', _fmt(s.last3AvgScore)),
            ]),
            const SizedBox(height: 16),
            _section('Ball Striking', [
              _pill('FIR', _fmtPct(s.firPct)),
              _pill('GIR', _fmtPct(s.girPct)),
            ]),
            const SizedBox(height: 16),
            _section('Short Game', [
              _pill('Sand Saves', _fmtPct(s.sandSavePct)),
              _pill('Putts/Hole', _fmt(s.avgPuttsPerHole)),
              _pill('Pen/Round', _fmt(s.avgPenaltiesPerRound)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: children),
      ],
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.06),
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

class _RecentFormCard extends StatelessWidget {
  final _RecentForm f;

  const _RecentFormCard(this.f);

  String _fmt(double? v, {int digits = 1}) =>
      v == null ? '-' : v.toStringAsFixed(digits);

  String _fmtTrend(double? v) {
    if (v == null) return '-';
    if (v == 0) return 'Even';
    return v > 0
        ? 'Improving by ${v.toStringAsFixed(1)}'
        : 'Worse by ${(-v).toStringAsFixed(1)}';
  }

  String _trendArrow(double? v) {
    if (v == null || v == 0) return '•';
    return v > 0 ? '▲' : '▼';
  }

  Color _trendColor(double? v) {
    if (v == null || v == 0) return Colors.black87;
    return v > 0 ? Colors.green.shade700 : Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Trend',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _pill('Last 3 Avg', _fmt(f.last3Avg)),
                _pill('Last 5 Avg', _fmt(f.last5Avg)),
                _pill('Previous 3 Avg', _fmt(f.previous3Avg)),
                _pill('Best Recent', f.bestRecent?.toString() ?? '-'),
                _pill('Worst Recent', f.worstRecent?.toString() ?? '-'),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Trend: ',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        '${_trendArrow(f.trend)} ${_fmtTrend(f.trend)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _trendColor(f.trend),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.06),
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

class _ParLine {
  final int holes;
  final double? avgScore;
  final double? avgToPar;
  final double? girPct;
  final double? avgPutts;
  final double? avgPenalties;

  const _ParLine({
    required this.holes,
    required this.avgScore,
    required this.avgToPar,
    required this.girPct,
    required this.avgPutts,
    required this.avgPenalties,
  });

  factory _ParLine.empty() => const _ParLine(
    holes: 0,
    avgScore: null,
    avgToPar: null,
    girPct: null,
    avgPutts: null,
    avgPenalties: null,
  );
}

class _ParBreakdown {
  final _ParLine par3;
  final _ParLine par4;
  final _ParLine par5;

  const _ParBreakdown({
    required this.par3,
    required this.par4,
    required this.par5,
  });

  factory _ParBreakdown.empty() => _ParBreakdown(
    par3: _ParLine.empty(),
    par4: _ParLine.empty(),
    par5: _ParLine.empty(),
  );
}

class _ParBreakdownCard extends StatelessWidget {
  Color _toParColor(double? v) {
    if (v == null) return Colors.black87;
    if (v < 0) return Colors.green.shade700;
    if (v > 0) return Colors.red.shade700;
    return Colors.black87;
  }

  final _ParBreakdown b;

  const _ParBreakdownCard(this.b);

  String _fmt(double? v, {int digits = 1}) =>
      v == null ? '-' : v.toStringAsFixed(digits);

  String _fmtPct(double? v) => v == null ? '-' : '${v.toStringAsFixed(0)}%';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Breakdown by Par',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            /*
            const SizedBox(height: 4),
            Text(
              'Based on ${b.par3.holes} par-3s, ${b.par4.holes} par-4s, and ${b.par5.holes} par-5s.',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            */
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // Header row
                const TableRow(
                  children: [
                    SizedBox(),
                    Center(
                      child: Text(
                        'Par 3',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Par 4',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Par 5',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),

                _statRow(
                  'Holes',
                  '${b.par3.holes}',
                  '${b.par4.holes}',
                  '${b.par5.holes}',
                ),
                _statRow(
                  'Avg Score',
                  _fmt(b.par3.avgScore),
                  _fmt(b.par4.avgScore),
                  _fmt(b.par5.avgScore),
                ),
                _statRow(
                  'Avg To Par',
                  _fmt(b.par3.avgToPar),
                  _fmt(b.par4.avgToPar),
                  _fmt(b.par5.avgToPar),
                  valueColors: [
                    _toParColor(b.par3.avgToPar),
                    _toParColor(b.par4.avgToPar),
                    _toParColor(b.par5.avgToPar),
                  ],
                  boldValues: true,
                ),
                _statRow(
                  'GIR',
                  _fmtPct(b.par3.girPct),
                  _fmtPct(b.par4.girPct),
                  _fmtPct(b.par5.girPct),
                ),
                _statRow(
                  'Avg Putts',
                  _fmt(b.par3.avgPutts),
                  _fmt(b.par4.avgPutts),
                  _fmt(b.par5.avgPutts),
                ),
                _statRow(
                  'Avg Penalties',
                  _fmt(b.par3.avgPenalties),
                  _fmt(b.par4.avgPenalties),
                  _fmt(b.par5.avgPenalties),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static TableRow _statRow(
    String label,
    String v3,
    String v4,
    String v5, {
    List<Color?>? valueColors,
    bool boldValues = false,
  }) {
    Widget cell(String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          v,
          style: TextStyle(
            color: color,
            fontWeight: boldValues ? FontWeight.w700 : null,
          ),
        ),
      ),
    );

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label),
        ),
        cell(v3, color: valueColors != null ? valueColors[0] : null),
        cell(v4, color: valueColors != null ? valueColors[1] : null),
        cell(v5, color: valueColors != null ? valueColors[2] : null),
      ],
    );
  }
}
