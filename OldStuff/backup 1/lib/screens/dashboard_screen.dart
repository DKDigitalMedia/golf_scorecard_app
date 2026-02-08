import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import '../providers/round_provider.dart';
import '../providers/db_provider.dart';
import '../widgets/chip_group.dart';
import '../widgets/distance_slider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: FutureBuilder(
        future: db.getAllRounds(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No rounds recorded yet.'));
          }

          final rounds = snapshot.data!;

          return FutureBuilder(
            future: Future.wait(rounds.map((r) => db.getHolesForRound(r.id))),
            builder: (context, holesSnapshot) {
              if (!holesSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final roundsHoles = holesSnapshot.data! as List<List<dynamic>>;

              // Calculate stats
              int totalScore = 0,
                  totalFront9 = 0,
                  totalBack9 = 0,
                  totalPutts = 0;
              int totalPenalties = 0, upAndDowns = 0;
              int firHits = 0, firAttempts = 0, girHits = 0, girAttempts = 0;

              for (var holes in roundsHoles) {
                for (var i = 0; i < holes.length; i++) {
                  final h = holes[i];
                  if (h.score != null) totalScore += h.score!;
                  if (i < 9 && h.score != null) totalFront9 += h.score!;
                  if (i >= 9 && h.score != null) totalBack9 += h.score!;
                  if (h.putts != null) totalPutts += h.putts!;
                  totalPenalties += h.penalties ?? 0;

                  if ((h.score != null && h.putts != null) &&
                      (h.approachLocation != 'Green' && h.putts! <= 2))
                    upAndDowns++;

                  if (h.fir != null && h.fir != 'N/A') {
                    firAttempts++;
                    if (h.fir == 'Center') firHits++;
                  }

                  if (h.approachLocation != null) {
                    girAttempts++;
                    if (h.approachLocation == 'Green') girHits++;
                  }
                }
              }

              final roundsCount = rounds.length;
              final firPercent =
                  firAttempts == 0 ? 0 : (firHits / firAttempts * 100).round();
              final girPercent =
                  girAttempts == 0 ? 0 : (girHits / girAttempts * 100).round();

              double handicap = 0.0;
              for (var r in rounds) {
                final rating = 72.0;
                final slope = 113;
                final adjustedScore = totalScore / roundsCount;
                handicap += (adjustedScore - rating) * 113 / slope;
              }
              handicap = roundsCount > 0 ? handicap / roundsCount : 0.0;

              List<FlSpot> firSpots = [];
              List<FlSpot> girSpots = [];
              for (var i = 0; i < roundsHoles.length; i++) {
                final holes = roundsHoles[i];
                int firHitsRound = holes.where((h) => h.fir == 'Center').length;
                int girHitsRound =
                    holes.where((h) => h.approachLocation == 'Green').length;
                firSpots.add(
                    FlSpot(i.toDouble(), (firHitsRound / holes.length) * 100));
                girSpots.add(
                    FlSpot(i.toDouble(), (girHitsRound / holes.length) * 100));
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Text('Total Rounds: $roundsCount',
                        style: const TextStyle(fontSize: 18)),
                    Text('Total Score: $totalScore',
                        style: const TextStyle(fontSize: 18)),
                    Text('Front 9 Total: $totalFront9',
                        style: const TextStyle(fontSize: 18)),
                    Text('Back 9 Total: $totalBack9',
                        style: const TextStyle(fontSize: 18)),
                    Text('Total Putts: $totalPutts',
                        style: const TextStyle(fontSize: 18)),
                    Text('Total Penalties: $totalPenalties',
                        style: const TextStyle(fontSize: 18)),
                    Text('Up-and-Downs: $upAndDowns',
                        style: const TextStyle(fontSize: 18)),
                    Text('FIR %: $firPercent%',
                        style: const TextStyle(fontSize: 18)),
                    Text('GIR %: $girPercent%',
                        style: const TextStyle(fontSize: 18)),
                    Text('Handicap Index: ${handicap.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 24),
                    const Text('FIR % Trend', style: TextStyle(fontSize: 18)),
                    SizedBox(
                      height: 200,
                      child: LineChart(LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: firSpots,
                            isCurved: true,
                            barWidth: 3,
                            colors: [Colors.green],
                            dotData: FlDotData(show: true),
                          )
                        ],
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true)),
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true)),
                        ),
                      )),
                    ),
                    const SizedBox(height: 24),
                    const Text('GIR % Trend', style: TextStyle(fontSize: 18)),
                    SizedBox(
                      height: 200,
                      child: LineChart(LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: girSpots,
                            isCurved: true,
                            barWidth: 3,
                            colors: [Colors.blue],
                            dotData: FlDotData(show: true),
                          )
                        ],
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true)),
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true)),
                        ),
                      )),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
