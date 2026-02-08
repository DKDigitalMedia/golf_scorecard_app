import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'hole_entry_screen.dart';
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
          final hasCompleted = data.rounds.isNotEmpty;

          if (!hasCompleted && data.inProgressRound == null) {
            return const Center(
              child: Text(
                'No completed rounds yet.\nFinish a round to see stats.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final dateFormatter = MaterialLocalizations.of(context);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.inProgressRound != null) ...[
                _ResumeRoundCard(
                  courseName: data.inProgressCourseName ?? 'Course',
                  teeName: data.inProgressTeeName ?? 'Tee',
                  lastHole: data.inProgressLastHole,
                  resumeHole: data.inProgressResumeHole,
                  onResume: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HoleEntryScreen(
                          roundId: data.inProgressRound!.id,
                          initialHole: data.inProgressResumeHole ?? 1,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (hasCompleted) ...[
                _StatsCard(data.stats),
                const SizedBox(height: 16),
                const Text(
                  'Recent Completed Rounds',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...data.rounds.map((r) {
                  final courseName =
                      data.courseNameById[r.courseId] ?? 'Course';
                  final teeName = data.teeNameById[r.teeBoxId] ?? 'Tee';

                  final total = data.totalScoreByRoundId[r.id] ?? 0;
                  final par = data.totalParByRoundId[r.id] ?? 0;
                  final toPar = total - par;

                  String fmtToPar(int v) {
                    if (v == 0) return 'E';
                    return v > 0 ? '+$v' : '$v';
                  }

                  final dateStr = dateFormatter.formatShortDate(r.date);

                  return Card(
                    child: ListTile(
                      title: Text('$courseName — $teeName'),
                      subtitle: Text(
                        '$dateStr  •  Score: $total (${fmtToPar(toPar)})  •  Par $par',
                      ),
                      trailing: const Icon(Icons.chevron_right),
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
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text(
                      'No completed rounds yet.\nFinish a round to see stats.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Future<_DashboardData> _load(AppDatabase db) async {
    final inProgress = await db.getLatestInProgressRound();
    final rounds = await db.getCompletedRoundsNewestFirst();

    if (rounds.isEmpty && inProgress == null) return _DashboardData.empty();

    String? inProgressCourseName;
    String? inProgressTeeName;
    int? inProgressLastHole;
    int? inProgressResumeHole;

    // Names lookup
    final Map<int, String> courseNameById;
    final Map<int, String> teeNameById;

    if (rounds.isEmpty) {
      // Keep this path light: just fetch the names we need for the resume card.
      if (inProgress != null) {
        final c = await db.getCourse(inProgress.courseId);
        final t = await db.getTeeBox(inProgress.teeBoxId);
        inProgressCourseName = c?.name;
        inProgressTeeName = t?.name;

        final last = await db.getLatestHoleNumberForRound(inProgress.id);
        inProgressLastHole = last;

        if (last == null) {
          inProgressResumeHole = 1;
        } else {
          final lastHole = await db.getHole(inProgress.id, last);
          final next = (lastHole?.score != null) ? (last + 1) : last;
          inProgressResumeHole = next.clamp(1, 18);
        }
      }
      courseNameById = const {};
      teeNameById = const {};
    } else {
      final courses = await db.getAllCourses();
      final tees = await db.getAllTeeBoxes();

      courseNameById = <int, String>{
        for (final c in courses) c.id: c.name,
      };
      teeNameById = <int, String>{
        for (final t in tees) t.id: t.name,
      };

      if (inProgress != null) {
        inProgressCourseName = courseNameById[inProgress.courseId];
        inProgressTeeName = teeNameById[inProgress.teeBoxId];

        final last = await db.getLatestHoleNumberForRound(inProgress.id);
        inProgressLastHole = last;

        if (last == null) {
          inProgressResumeHole = 1;
        } else {
          final lastHole = await db.getHole(inProgress.id, last);
          final next = (lastHole?.score != null) ? (last + 1) : last;
          inProgressResumeHole = next.clamp(1, 18);
        }
      }
    }

    // Aggregate stats across all completed rounds
    int roundsCount = 0;

    int sumScore = 0;
    int sumPar = 0;

    int firOpps = 0;
    int firHits = 0;

    int girOpps = 0;
    int girHits = 0;

    int totalPutts = 0;
    int puttHoleCount = 0;

    int totalPenalties = 0;

    // Par type accumulators (score)
    int par3ScoreSum = 0, par3Count = 0;
    int par4ScoreSum = 0, par4Count = 0;
    int par5ScoreSum = 0, par5Count = 0;

    // Par type accumulators (GIR)
    int par3GirOpps = 0, par3GirHits = 0;
    int par4GirOpps = 0, par4GirHits = 0;
    int par5GirOpps = 0, par5GirHits = 0;

    // Par type accumulators (FIR - only 4/5)
    int par4FirOpps = 0, par4FirHits = 0;
    int par5FirOpps = 0, par5FirHits = 0;

    // Par type accumulators (putts)
    int par3PuttsSum = 0, par3PuttsCount = 0;
    int par4PuttsSum = 0, par4PuttsCount = 0;
    int par5PuttsSum = 0, par5PuttsCount = 0;

    // Par type accumulators (penalties)
    int par3PenSum = 0, par3PenCount = 0;
    int par4PenSum = 0, par4PenCount = 0;
    int par5PenSum = 0, par5PenCount = 0;

    final totalScoreByRoundId = <int, int>{};
    final totalParByRoundId = <int, int>{};

    for (final r in rounds) {
      roundsCount++;

      final holes = await db.getHolesForRoundOrdered(r.id);

      // Par map for this round (from the course)
      final courseHoles = await db.getCourseHolesForCourse(r.courseId);
      final parByHole = <int, int>{
        for (final ch in courseHoles) ch.holeNumber: ch.par
      };

      int roundScore = 0;
      int roundPar = 0;

      for (final h in holes) {
        final par = parByHole[h.holeNumber] ?? 0;
        roundPar += par;

        final score = h.score ?? 0;
        roundScore += score;

        // Score by par (only if a score exists)
        if (h.score != null) {
          if (par == 3) {
            par3ScoreSum += score;
            par3Count++;
          } else if (par == 4) {
            par4ScoreSum += score;
            par4Count++;
          } else if (par == 5) {
            par5ScoreSum += score;
            par5Count++;
          }
        }

        // FIR: only meaningful on par 4/5
        if (par == 4 || par == 5) {
          firOpps++;
          if (h.fir == 'C') firHits++;

          if (par == 4) {
            par4FirOpps++;
            if (h.fir == 'C') par4FirHits++;
          } else {
            par5FirOpps++;
            if (h.fir == 'C') par5FirHits++;
          }
        }

        // GIR: requires score + putts + par
        if (par != 0 && h.score != null && h.putts != null) {
          girOpps++;
          final strokesToGreen = h.score! - h.putts!;
          final isGir = strokesToGreen <= (par - 2);
          if (isGir) girHits++;

          if (par == 3) {
            par3GirOpps++;
            if (isGir) par3GirHits++;
          } else if (par == 4) {
            par4GirOpps++;
            if (isGir) par4GirHits++;
          } else if (par == 5) {
            par5GirOpps++;
            if (isGir) par5GirHits++;
          }
        }

        // Putts
        if (h.putts != null) {
          totalPutts += h.putts!;
          puttHoleCount++;

          if (par == 3) {
            par3PuttsSum += h.putts!;
            par3PuttsCount++;
          } else if (par == 4) {
            par4PuttsSum += h.putts!;
            par4PuttsCount++;
          } else if (par == 5) {
            par5PuttsSum += h.putts!;
            par5PuttsCount++;
          }
        }

        // Penalties
        if (h.penalties != null) {
          totalPenalties += h.penalties!;

          if (par == 3) {
            par3PenSum += h.penalties!;
            par3PenCount++;
          } else if (par == 4) {
            par4PenSum += h.penalties!;
            par4PenCount++;
          } else if (par == 5) {
            par5PenSum += h.penalties!;
            par5PenCount++;
          }
        }
      }

      sumScore += roundScore;
      sumPar += roundPar;

      totalScoreByRoundId[r.id] = roundScore;
      totalParByRoundId[r.id] = roundPar;
    }

    double? pct(int hits, int opps) => opps == 0 ? null : (hits / opps) * 100.0;
    double? avg(int sum, int count) => count == 0 ? null : (sum / count);

    _ParTypeStats buildParStats({
      required int par,
      required int scoreSum,
      required int scoreCount,
      required int girOpps,
      required int girHits,
      int? firOpps,
      int? firHits,
      required int puttsSum,
      required int puttsCount,
      required int penSum,
      required int penCount,
    }) {
      final avgScore = avg(scoreSum, scoreCount);
      final avgToPar = (avgScore == null) ? null : (avgScore - par);
      return _ParTypeStats(
        par: par,
        holesWithScore: scoreCount,
        avgScore: avgScore,
        avgToPar: avgToPar,
        girPct: pct(girHits, girOpps),
        firPct:
            (firOpps == null || firHits == null) ? null : pct(firHits, firOpps),
        avgPutts: avg(puttsSum, puttsCount),
        avgPenalties: avg(penSum, penCount),
      );
    }

    final par3Stats = buildParStats(
      par: 3,
      scoreSum: par3ScoreSum,
      scoreCount: par3Count,
      girOpps: par3GirOpps,
      girHits: par3GirHits,
      puttsSum: par3PuttsSum,
      puttsCount: par3PuttsCount,
      penSum: par3PenSum,
      penCount: par3PenCount,
    );

    final par4Stats = buildParStats(
      par: 4,
      scoreSum: par4ScoreSum,
      scoreCount: par4Count,
      girOpps: par4GirOpps,
      girHits: par4GirHits,
      firOpps: par4FirOpps,
      firHits: par4FirHits,
      puttsSum: par4PuttsSum,
      puttsCount: par4PuttsCount,
      penSum: par4PenSum,
      penCount: par4PenCount,
    );

    final par5Stats = buildParStats(
      par: 5,
      scoreSum: par5ScoreSum,
      scoreCount: par5Count,
      girOpps: par5GirOpps,
      girHits: par5GirHits,
      firOpps: par5FirOpps,
      firHits: par5FirHits,
      puttsSum: par5PuttsSum,
      puttsCount: par5PuttsCount,
      penSum: par5PenSum,
      penCount: par5PenCount,
    );

    final stats = _DashboardStats(
      roundsCount: roundsCount,
      avgScore: roundsCount == 0 ? null : (sumScore / roundsCount),
      avgToPar: roundsCount == 0 ? null : ((sumScore - sumPar) / roundsCount),
      firPct: pct(firHits, firOpps),
      girPct: pct(girHits, girOpps),
      avgPuttsPerHole: puttHoleCount == 0 ? null : (totalPutts / puttHoleCount),
      avgPenaltiesPerRound:
          roundsCount == 0 ? null : (totalPenalties / roundsCount),
      par3: par3Stats,
      par4: par4Stats,
      par5: par5Stats,
    );

    return _DashboardData(
      rounds: rounds,
      inProgressRound: inProgress,
      inProgressCourseName: inProgressCourseName,
      inProgressTeeName: inProgressTeeName,
      inProgressLastHole: inProgressLastHole,
      inProgressResumeHole: inProgressResumeHole,
      stats: stats,
      courseNameById: courseNameById,
      teeNameById: teeNameById,
      totalScoreByRoundId: totalScoreByRoundId,
      totalParByRoundId: totalParByRoundId,
    );
  }
}

class _DashboardData {
  final List<Round> rounds;
  final Round? inProgressRound;
  final String? inProgressCourseName;
  final String? inProgressTeeName;

  final int? inProgressLastHole;
  final int? inProgressResumeHole;

  final _DashboardStats stats;

  final Map<int, String> courseNameById;
  final Map<int, String> teeNameById;

  final Map<int, int> totalScoreByRoundId;
  final Map<int, int> totalParByRoundId;

  _DashboardData({
    required this.rounds,
    required this.inProgressRound,
    required this.inProgressCourseName,
    required this.inProgressTeeName,
    required this.inProgressLastHole,
    required this.inProgressResumeHole,
    required this.stats,
    required this.courseNameById,
    required this.teeNameById,
    required this.totalScoreByRoundId,
    required this.totalParByRoundId,
  });

  factory _DashboardData.empty() => _DashboardData(
        rounds: const [],
        inProgressRound: null,
        inProgressCourseName: null,
        inProgressTeeName: null,
        inProgressLastHole: null,
        inProgressResumeHole: null,
        stats: _DashboardStats.empty(),
        courseNameById: const {},
        teeNameById: const {},
        totalScoreByRoundId: const {},
        totalParByRoundId: const {},
      );
}

class _ResumeRoundCard extends StatelessWidget {
  final String courseName;
  final String teeName;
  final int? lastHole;
  final int? resumeHole;
  final VoidCallback onResume;

  const _ResumeRoundCard({
    required this.courseName,
    required this.teeName,
    required this.lastHole,
    required this.resumeHole,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final resume = resumeHole ?? 1;
    final last = lastHole;

    final subtitleParts = <String>[
      '$courseName — $teeName',
      if (last != null) 'Last hole: $last',
      'Resume at hole: $resume',
    ];

    return Card(
      child: ListTile(
        title: const Text(
          'Resume Round',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitleParts.join('  •  ')),
        trailing: const Icon(Icons.play_arrow),
        onTap: onResume,
      ),
    );
  }
}

class _ParTypeStats {
  final int par;
  final int holesWithScore;
  final double? avgScore;
  final double? avgToPar;
  final double? girPct;
  final double? firPct; // null for par 3
  final double? avgPutts;
  final double? avgPenalties;

  const _ParTypeStats({
    required this.par,
    required this.holesWithScore,
    required this.avgScore,
    required this.avgToPar,
    required this.girPct,
    required this.firPct,
    required this.avgPutts,
    required this.avgPenalties,
  });
}

class _DashboardStats {
  final int roundsCount;
  final double? avgScore;
  final double? avgToPar;
  final double? firPct;
  final double? girPct;
  final double? avgPuttsPerHole;
  final double? avgPenaltiesPerRound;

  final _ParTypeStats par3;
  final _ParTypeStats par4;
  final _ParTypeStats par5;

  _DashboardStats({
    required this.roundsCount,
    required this.avgScore,
    required this.avgToPar,
    required this.firPct,
    required this.girPct,
    required this.avgPuttsPerHole,
    required this.avgPenaltiesPerRound,
    required this.par3,
    required this.par4,
    required this.par5,
  });

  factory _DashboardStats.empty() => _DashboardStats(
        roundsCount: 0,
        avgScore: null,
        avgToPar: null,
        firPct: null,
        girPct: null,
        avgPuttsPerHole: null,
        avgPenaltiesPerRound: null,
        par3: const _ParTypeStats(
          par: 3,
          holesWithScore: 0,
          avgScore: null,
          avgToPar: null,
          girPct: null,
          firPct: null,
          avgPutts: null,
          avgPenalties: null,
        ),
        par4: const _ParTypeStats(
          par: 4,
          holesWithScore: 0,
          avgScore: null,
          avgToPar: null,
          girPct: null,
          firPct: null,
          avgPutts: null,
          avgPenalties: null,
        ),
        par5: const _ParTypeStats(
          par: 5,
          holesWithScore: 0,
          avgScore: null,
          avgToPar: null,
          girPct: null,
          firPct: null,
          avgPutts: null,
          avgPenalties: null,
        ),
      );
}

class _StatsCard extends StatelessWidget {
  final _DashboardStats s;

  const _StatsCard(this.s);

  String _fmt(double? v, {int digits = 1}) =>
      v == null ? '-' : v.toStringAsFixed(digits);

  String _fmtPct(double? v) => v == null ? '-' : '${v.toStringAsFixed(0)}%';

  String _fmtToPar(double? avgScore, int par) {
    if (avgScore == null) return '-';
    final diff = avgScore - par;
    if (diff == 0) return 'E';
    return diff > 0 ? '+${diff.toStringAsFixed(1)}' : diff.toStringAsFixed(1);
  }

  Color _parColor(double? avgScore, int par) {
    if (avgScore == null) return Colors.black87;
    final diff = avgScore - par;
    if (diff < 0) return Colors.green;
    if (diff > 0) return Colors.red;
    return Colors.black87;
  }

  Color _parTint(double? avgScore, int par) {
    if (avgScore == null) return Colors.black.withOpacity(0.04);
    final diff = avgScore - par;
    if (diff < 0) return Colors.green.withOpacity(0.12);
    if (diff > 0) return Colors.red.withOpacity(0.12);
    return Colors.black.withOpacity(0.04);
  }

  void _showParBreakdown(BuildContext context, _ParTypeStats ps) {
    final theme = Theme.of(context);

    String fmtToPar(double? diff) {
      if (diff == null) return '-';
      if (diff == 0) return 'E';
      return diff > 0 ? '+${diff.toStringAsFixed(1)}' : diff.toStringAsFixed(1);
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Par ${ps.par} Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _kv('Holes counted', '${ps.holesWithScore}'),
              _kv('Avg score', _fmt(ps.avgScore)),
              _kv('Avg to-par', fmtToPar(ps.avgToPar)),
              _kv('GIR', _fmtPct(ps.girPct)),
              if (ps.firPct != null) _kv('FIR', _fmtPct(ps.firPct)),
              _kv('Avg putts', _fmt(ps.avgPutts)),
              _kv('Avg penalties', _fmt(ps.avgPenalties)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(k, style: const TextStyle(color: Colors.black54))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p3 = s.par3;
    final p4 = s.par4;
    final p5 = s.par5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stats (${s.roundsCount} completed rounds)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _pill('Avg Score', _fmt(s.avgScore)),
                _pill('Avg To Par', _fmt(s.avgToPar)),
                _pill('FIR', _fmtPct(s.firPct)),
                _pill('GIR', _fmtPct(s.girPct)),
                _pill('Putts/Hole', _fmt(s.avgPuttsPerHole)),
                _pill('Pen/Round', _fmt(s.avgPenaltiesPerRound)),

                // Par pills: tinted + tappable breakdown
                _pill(
                  'Par 3',
                  '${_fmt(p3.avgScore)} (${_fmtToPar(p3.avgScore, 3)})',
                  valueColor: _parColor(p3.avgScore, 3),
                  backgroundColor: _parTint(p3.avgScore, 3),
                  onTap: () => _showParBreakdown(context, p3),
                ),
                _pill(
                  'Par 4',
                  '${_fmt(p4.avgScore)} (${_fmtToPar(p4.avgScore, 4)})',
                  valueColor: _parColor(p4.avgScore, 4),
                  backgroundColor: _parTint(p4.avgScore, 4),
                  onTap: () => _showParBreakdown(context, p4),
                ),
                _pill(
                  'Par 5',
                  '${_fmt(p5.avgScore)} (${_fmtToPar(p5.avgScore, 5)})',
                  valueColor: _parColor(p5.avgScore, 5),
                  backgroundColor: _parTint(p5.avgScore, 5),
                  onTap: () => _showParBreakdown(context, p5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    String label,
    String value, {
    Color? valueColor,
    Color? backgroundColor,
    VoidCallback? onTap,
  }) {
    final bg = backgroundColor ?? Colors.black.withOpacity(0.04);

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.black54)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
