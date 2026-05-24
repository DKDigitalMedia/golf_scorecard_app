import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'hole_entry_screen.dart';

class RoundSummaryScreen extends ConsumerStatefulWidget {
  final int roundId;

  const RoundSummaryScreen({super.key, required this.roundId});

  @override
  ConsumerState<RoundSummaryScreen> createState() => _RoundSummaryScreenState();
}

class _RoundSummaryScreenState extends ConsumerState<RoundSummaryScreen> {
  bool _unlocked = false;
  int _reloadTick = 0;

  Future<String> _buildShareText(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final data = await _load(db, widget.roundId);

    final r = data.round;
    final courseName = data.course?.name ?? 'Course';
    final teeName = data.tee?.name ?? 'Tee';

    final totalScore = data.holes.fold<int>(0, (s, h) => s + (h.score ?? 0));
    final totalPar = data.parByHole.values.fold<int>(0, (s, v) => s + v);
    final toPar = totalScore - totalPar;

    String fmtToPar(int v) {
      if (v == 0) return 'E';
      return v > 0 ? '+$v' : '$v';
    }

    String fmtDate(DateTime dt) {
      final d = dt.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.month)}/${two(d.day)}/${d.year}';
    }

    final lines = <String>[
      'Golf Round Summary',
      '$courseName — $teeName',
      'Date: ${fmtDate(r.date)}',
      'Score: $totalScore (${fmtToPar(toPar)})',
      'Par: $totalPar',
      '',
      'Hole  Par  Score',
    ];

    for (var hole = 1; hole <= 18; hole++) {
      final par = data.parByHole[hole] ?? 0;
      final score = data.holeByNumber[hole]?.score;
      lines.add(
        '${hole.toString().padLeft(2, ' ')}    '
        '${par == 0 ? '-' : par.toString()}     '
        '${score?.toString() ?? '-'}',
      );
    }

    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    final roundId = widget.roundId;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) return;
        setState(() {
          _unlocked = false;
        });
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Round Summary', maxLines: 1),
          ),
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

                  await Share.share(text, sharePositionOrigin: origin);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
                }
              },
            ),
            IconButton(
              tooltip: _unlocked ? 'Lock round' : 'Unlock round',
              icon: Icon(_unlocked ? Icons.lock_open : Icons.lock),
              onPressed: () {
                setState(() {
                  _unlocked = !_unlocked;
                });
              },
            ),
          ],
        ),
        body: FutureBuilder<_RoundSummaryData>(
          key: ValueKey(_reloadTick),
          future: _load(db, roundId),
          builder: (context, snap) {
            if (!snap.hasData) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              return const Center(child: CircularProgressIndicator());
            }

            final data = snap.data!;
            final r = data.round;

            final courseName = data.course?.name ?? 'Course';
            final teeName = data.tee?.name ?? 'Tee';

            final totalScore = data.holes.fold<int>(
              0,
              (s, h) => s + (h.score ?? 0),
            );
            final totalPar = data.parByHole.values.fold<int>(
              0,
              (s, v) => s + v,
            );
            final toPar = totalScore - totalPar;

            String fmtToPar(int v) {
              if (v == 0) return 'E';
              return v > 0 ? '+$v' : '$v';
            }

            String fmtCompleted(DateTime dt) {
              final m = dt.month;
              final d = dt.day;
              final y = dt.year;

              final minute = dt.minute.toString().padLeft(2, '0');
              final isPm = dt.hour >= 12;
              final hour12 = (dt.hour % 12 == 0) ? 12 : (dt.hour % 12);
              final ampm = isPm ? 'PM' : 'AM';

              return '$m/$d/$y $hour12:$minute $ampm';
            }

            int parOf(int holeNumber) => data.parByHole[holeNumber] ?? 0;

            int? scoreOf(int holeNumber) =>
                data.holeByNumber[holeNumber]?.score;

            int? puttsOf(int holeNumber) =>
                data.holeByNumber[holeNumber]?.putts;

            String? teeShotOf(int holeNumber) =>
                data.holeByNumber[holeNumber]?.fir;

            String? approachShotOf(int holeNumber) =>
                data.holeByNumber[holeNumber]?.approachLocation;

            int? penaltiesOf(int holeNumber) =>
                data.holeByNumber[holeNumber]?.penalties;

            final frontHoles = List<int>.generate(9, (i) => i + 1);
            final backHoles = List<int>.generate(9, (i) => i + 10);

            int sumScores(List<int> holeNums) =>
                holeNums.fold(0, (s, n) => s + (scoreOf(n) ?? 0));
            int sumPars(List<int> holeNums) =>
                holeNums.fold(0, (s, n) => s + parOf(n));

            final frontScore = sumScores(frontHoles);
            final backScore = sumScores(backHoles);
            final frontPar = sumPars(frontHoles);
            final backPar = sumPars(backHoles);
            final frontToPar = frontScore - frontPar;
            final backToPar = backScore - backPar;

            final totalPutts = data.holes.fold<int>(
              0,
              (s, h) => s + (h.putts ?? 0),
            );
            final totalPenalties = data.holes.fold<int>(
              0,
              (s, h) => s + (h.penalties ?? 0),
            );

            int firOpps = 0;
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

            for (final h in data.holes) {
              final par = parOf(h.holeNumber);

              if (par == 4 || par == 5) {
                firOpps++;
                if (h.fir == 'L') firLeft++;
                if (h.fir == 'C') firCenter++;
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

              if (par != 0 && h.score != null && h.putts != null) {
                girOpps++;
                final strokesToGreen = h.score! - h.putts!;
                if (strokesToGreen <= (par - 2)) {
                  girHits++;
                }
              }
            }

            String fmtPct(int hits, int opps) {
              if (opps == 0) return '-';
              return '${((hits / opps) * 100).round()}%';
            }

            final Color scoreColor;
            if (toPar < 0) {
              scoreColor = Colors.green.shade700;
            } else if (toPar > 0) {
              scoreColor = Colors.red.shade700;
            } else {
              scoreColor = Colors.black87;
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$courseName — $teeName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _BigStatCard(
                                label: 'Total',
                                value: '$totalScore (${fmtToPar(toPar)})',
                                sub: 'Par $totalPar',
                                valueColor: scoreColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _BigStatCard(
                                label: 'Front / Back',
                                value: '$frontScore / $backScore',
                                sub: 'Par $frontPar / $backPar',
                              ),
                            ),
                          ],
                        ),
                        if (r.completed) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Date: ${fmtCompleted(r.date)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _SummaryChip(
                                label: 'Putts',
                                value: '$totalPutts',
                              ),
                              _SummaryChip(
                                label: 'Penalties',
                                value: '$totalPenalties',
                              ),
                              _SummaryChip(
                                label: 'GIR',
                                value: fmtPct(girHits, girOpps),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 700;

                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TeeShotsBox(
                                      left: fmtPct(firLeft, firOpps),
                                      center: fmtPct(firCenter, firOpps),
                                      right: fmtPct(firRight, firOpps),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ApproachShotsBox(
                                      left: fmtPct(approachLeft, approachOpps),
                                      center: fmtPct(
                                        approachCenter,
                                        approachOpps,
                                      ),
                                      right: fmtPct(
                                        approachRight,
                                        approachOpps,
                                      ),
                                      long: fmtPct(approachLong, approachOpps),
                                      short: fmtPct(
                                        approachShort,
                                        approachOpps,
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
                                  left: fmtPct(firLeft, firOpps),
                                  center: fmtPct(firCenter, firOpps),
                                  right: fmtPct(firRight, firOpps),
                                ),
                                const SizedBox(height: 12),
                                ApproachShotsBox(
                                  left: fmtPct(approachLeft, approachOpps),
                                  center: fmtPct(approachCenter, approachOpps),
                                  right: fmtPct(approachRight, approachOpps),
                                  long: fmtPct(approachLong, approachOpps),
                                  short: fmtPct(approachShort, approachOpps),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        _unlocked
                            ? 'Round is unlocked. Tap a hole below to edit it.'
                            : 'Round is locked. Tap the lock icon to enable editing.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontStyle: FontStyle.italic,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ScorecardCard(
                  title: 'Front 9',
                  holes: frontHoles,
                  parOf: parOf,
                  scoreOf: scoreOf,
                  puttsOf: puttsOf,
                  teeShotOf: teeShotOf,
                  approachShotOf: approachShotOf,
                  penaltiesOf: penaltiesOf,
                  onHoleTap: _unlocked
                      ? (holeNumber) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HoleEntryScreen(
                                roundId: roundId,
                                initialHole: holeNumber,
                                editMode: true,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          setState(() {
                            _reloadTick++; // recompute stats on return
                          });
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                _ScorecardCard(
                  title: 'Back 9',
                  holes: backHoles,
                  parOf: parOf,
                  scoreOf: scoreOf,
                  puttsOf: puttsOf,
                  teeShotOf: teeShotOf,
                  approachShotOf: approachShotOf,
                  penaltiesOf: penaltiesOf,
                  onHoleTap: _unlocked
                      ? (holeNumber) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HoleEntryScreen(
                                roundId: roundId,
                                initialHole: holeNumber,
                                editMode: true,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          setState(() {
                            _reloadTick++; // recompute stats on return
                          });
                        }
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<_RoundSummaryData> _load(AppDatabase db, int roundId) async {
    final round = await db.getRound(roundId);
    final holes = await db.getHolesForRoundOrdered(roundId);

    final course = round == null ? null : await db.getCourse(round.courseId);
    final tee = round == null ? null : await db.getTeeBox(round.teeBoxId);

    final courseHoles = round == null
        ? <CourseHole>[]
        : await db.getCourseHolesForCourse(round.courseId);

    final parByHole = <int, int>{
      for (final ch in courseHoles) ch.holeNumber: (ch.par ?? 0),
    };

    final holeByNumber = <int, Hole>{for (final h in holes) h.holeNumber: h};

    if (round == null) {
      throw Exception('Round not found');
    }

    return _RoundSummaryData(
      round: round,
      holes: holes,
      course: course,
      tee: tee,
      parByHole: parByHole,
      holeByNumber: holeByNumber,
    );
  }
}

class _RoundSummaryData {
  final Round round;
  final List<Hole> holes;
  final Course? course;
  final TeeBox? tee;
  final Map<int, int> parByHole;
  final Map<int, Hole> holeByNumber;

  _RoundSummaryData({
    required this.round,
    required this.holes,
    required this.course,
    required this.tee,
    required this.parByHole,
    required this.holeByNumber,
  });
}

class _ScorecardCard extends StatelessWidget {
  final String title;
  final List<int> holes;
  final int Function(int holeNumber) parOf;
  final int? Function(int holeNumber) scoreOf;
  final int? Function(int holeNumber) puttsOf;
  final String? Function(int holeNumber) teeShotOf;
  final String? Function(int holeNumber) approachShotOf;
  final int? Function(int holeNumber) penaltiesOf;
  final void Function(int holeNumber)? onHoleTap;

  const _ScorecardCard({
    required this.title,
    required this.holes,
    required this.parOf,
    required this.scoreOf,
    required this.puttsOf,
    required this.teeShotOf,
    required this.approachShotOf,
    required this.penaltiesOf,
    this.onHoleTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalPar = holes.fold(0, (s, n) => s + parOf(n));
    final totalScore = holes.fold(0, (s, n) => s + (scoreOf(n) ?? 0));
    final totalPutts = holes.fold(0, (s, n) => s + (puttsOf(n) ?? 0));
    final totalPenalties = holes.fold(0, (s, n) => s + (penaltiesOf(n) ?? 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'Par $totalPar  •  $totalScore',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _ScorecardHeaderRow(),
            const Divider(height: 1),
            for (final n in holes)
              _ScorecardDataRow(
                holeNumber: n,
                par: parOf(n),
                score: scoreOf(n),
                putts: puttsOf(n),
                teeShot: teeShotOf(n),
                approachShot: approachShotOf(n),
                penalties: penaltiesOf(n),
                onTap: onHoleTap == null ? null : () => onHoleTap!(n),
              ),
            const Divider(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 6,
              children: [
                _MiniTotal(label: 'Score', value: '$totalScore'),
                _MiniTotal(label: 'Par', value: '$totalPar'),
                _MiniTotal(label: 'Putts', value: '$totalPutts'),
                _MiniTotal(label: 'Pen', value: '$totalPenalties'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorecardHeaderRow extends StatelessWidget {
  const _ScorecardHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.black54,
          fontWeight: FontWeight.w700,
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.035),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _scoreCell(Text('Hole', style: style), flex: 15),
          _scoreCell(Text('Par', style: style), flex: 13),
          _scoreCell(Text('Score', style: style), flex: 16),
          _scoreCell(Text('Putts', style: style), flex: 14),
          _scoreCell(Text('Tee', style: style), flex: 14),
          _scoreCell(Text('GIR', style: style), flex: 14),
          _scoreCell(Text('Pen', style: style), flex: 14),
        ],
      ),
    );
  }
}

class _ScorecardDataRow extends StatelessWidget {
  final int holeNumber;
  final int par;
  final int? score;
  final int? putts;
  final String? teeShot;
  final String? approachShot;
  final int? penalties;
  final VoidCallback? onTap;

  const _ScorecardDataRow({
    required this.holeNumber,
    required this.par,
    required this.score,
    required this.putts,
    required this.teeShot,
    required this.approachShot,
    required this.penalties,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        _scoreCell(_plainValue('$holeNumber'), flex: 15),
        _scoreCell(_plainValue(par == 0 ? '-' : '$par'), flex: 13),
        _scoreCell(
          _scoreValue(score, par),
          flex: 16,
        ),
        _scoreCell(_plainValue(putts?.toString() ?? '-'), flex: 14),
        _scoreCell(_shotBadge(teeShot, isTeeShot: true), flex: 14),
        _scoreCell(_shotBadge(approachShot, isTeeShot: false), flex: 14),
        _scoreCell(_penaltyValue(penalties), flex: 14),
      ],
    );

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: row,
      ),
    );
  }

  Widget _plainValue(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  Widget _scoreValue(int? score, int par) {
    if (score == null) return _plainValue('-');

    Color? color;
    if (par > 0) {
      final toPar = score - par;
      if (toPar < 0) {
        color = Colors.green.shade700;
      } else if (toPar > 0) {
        color = Colors.red.shade700;
      }
    }

    return Text(
      score.toString(),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _penaltyValue(int? penalties) {
    if (penalties == null || penalties == 0) {
      return const Text(
        '-',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w600),
      );
    }

    return Text(
      penalties.toString(),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.red.shade700,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _shotBadge(String? value, {required bool isTeeShot}) {
    final label = _shotLabel(value, isTeeShot: isTeeShot);
    if (label == '-') {
      return const Text(
        '-',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w600),
      );
    }

    final isCenter = value == 'C';
    final isMiss =
        value == 'L' || value == 'R' || value == 'LONG' || value == 'SHORT';

    return Container(
      width: 28,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCenter
            ? Colors.green.shade100
            : isMiss
                ? Colors.amber.shade100
                : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isCenter
              ? Colors.green.shade300
              : isMiss
                  ? Colors.amber.shade300
                  : Colors.black12,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  String _shotLabel(String? value, {required bool isTeeShot}) {
    switch (value) {
      case 'L':
        return '←';
      case 'C':
        return '✓';
      case 'R':
        return '→';
      case 'LONG':
        return isTeeShot ? '-' : '↑';
      case 'SHORT':
        return isTeeShot ? '-' : '↓';
      default:
        return '-';
    }
  }
}

Widget _scoreCell(Widget child, {required int flex}) {
  return Expanded(
    flex: flex,
    child: Center(child: child),
  );
}

class _MiniTotal extends StatelessWidget {
  final String label;
  final String value;

  const _MiniTotal({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label ',
        style: const TextStyle(color: Colors.black54),
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  const _BigStatCard({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
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
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

class TeeShotsBox extends StatelessWidget {
  final String left;
  final String center;
  final String right;

  const TeeShotsBox({
    required this.left,
    required this.center,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {bool bold = false, Color? backgroundColor}) {
      return Expanded(
        child: Container(
          alignment: Alignment.center,
          color: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: Colors.black12,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            alignment: Alignment.center,
            child: const Text(
              'Tee Shots',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell('Left', bold: true, backgroundColor: Colors.yellow.shade100),
              const SizedBox.shrink(),
              cell(
                'Center',
                bold: true,
                backgroundColor: Colors.green.shade200,
              ),
              const SizedBox.shrink(),
              cell('Right',
                  bold: true, backgroundColor: Colors.yellow.shade100),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell(left, backgroundColor: Colors.yellow.shade100),
              const SizedBox.shrink(),
              cell(center, backgroundColor: Colors.green.shade200),
              const SizedBox.shrink(),
              cell(right, backgroundColor: Colors.yellow.shade100),
            ],
          ),
        ],
      ),
    );
  }
}

class ApproachShotsBox extends StatelessWidget {
  final String left;
  final String center;
  final String right;
  final String long;
  final String short;

  const ApproachShotsBox({
    required this.left,
    required this.center,
    required this.right,
    required this.long,
    required this.short,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {bool bold = false, Color? backgroundColor}) {
      return Expanded(
        child: Container(
          alignment: Alignment.center,
          color: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    Widget dividerV([double h = 24]) => const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: Colors.black12,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            alignment: Alignment.center,
            child: const Text(
              'Approach Shots',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell(''),
              dividerV(),
              cell('Long', bold: true, backgroundColor: Colors.cyan.shade100),
              dividerV(),
              cell(''),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell(''),
              dividerV(),
              cell(long, backgroundColor: Colors.cyan.shade100),
              dividerV(),
              cell('')
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell('Left', bold: true, backgroundColor: Colors.yellow.shade100),
              dividerV(),
              cell(
                'Center',
                bold: true,
                backgroundColor: Colors.green.shade200,
              ),
              dividerV(),
              cell('Right',
                  bold: true, backgroundColor: Colors.yellow.shade100),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell(left, backgroundColor: Colors.yellow.shade100),
              dividerV(),
              cell(center, backgroundColor: Colors.green.shade200),
              dividerV(),
              cell(right, backgroundColor: Colors.yellow.shade100),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell(''),
              dividerV(),
              cell('Short', bold: true, backgroundColor: Colors.cyan.shade100),
              dividerV(),
              cell(''),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cell(''),
              dividerV(),
              cell(short, backgroundColor: Colors.cyan.shade100),
              dividerV(),
              cell('')
            ],
          ),
        ],
      ),
    );
  }
}
