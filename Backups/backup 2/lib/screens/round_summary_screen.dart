import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import 'hole_entry_screen.dart';

class RoundSummaryScreen extends ConsumerStatefulWidget {
  final int roundId;
  const RoundSummaryScreen({super.key, required this.roundId});

  @override
  ConsumerState<RoundSummaryScreen> createState() => _RoundSummaryScreenState();
}

class _RoundSummaryScreenState extends ConsumerState<RoundSummaryScreen> {
  List<Hole> holes = [];

  @override
  void initState() {
    super.initState();
    _loadHoles();
  }

  Future<void> _loadHoles() async {
    final db = ref.read(databaseProvider);
    final list = await db.getHolesForRound(widget.roundId);
    list.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));
    setState(() => holes = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Round Summary')),
      body: ListView.builder(
        itemCount: holes.length,
        itemBuilder: (_, index) {
          final h = holes[index];
          final completed = h.score != null && h.putts != null;

          return Card(
            color: completed ? Colors.green[50] : Colors.red[50],
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: completed ? Colors.green : Colors.grey,
                child: Text('${h.holeNumber}'),
              ),
              title:
                  Text('Score: ${h.score ?? "-"} | Putts: ${h.putts ?? "-"}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Yardage: ${h.yardage ?? "-"}'),
                  Text(
                      'FIR: ${h.fir ? "Yes" : "No"}, GIR: ${h.gir ? "Yes" : "No"}, Up & Down: ${h.upAndDown ? "Yes" : "No"}'),
                  Text(
                      'Approach: ${h.approachLocation?.name ?? "-"} (${h.approachDistance ?? "-"} yds), Putt: ${h.firstPuttDistance ?? "-"} ft'),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HoleEntryScreen(
                        roundId: h.roundId, initialHole: h.holeNumber),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
