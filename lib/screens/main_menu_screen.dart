import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart' show routeObserver;

import '../providers/database_provider.dart';
import 'course_list_screen.dart';
import 'dashboard_screen.dart';
import 'hole_entry_screen.dart';
import 'round_summary_screen.dart';
import 'saved_rounds_screen.dart';
import 'start_round_screen.dart';

// ===========================
// Resume info (TOP-LEVEL CLASS)
// ===========================
class _ResumeInfo {
  final int roundId;
  final String courseName;
  final String teeName;
  final DateTime date;
  final int? lastHole;
  final int resumeHole;
  final bool multiple;

  const _ResumeInfo({
    required this.roundId,
    required this.courseName,
    required this.teeName,
    required this.date,
    required this.lastHole,
    required this.resumeHole,
    required this.multiple,
  });

  String titleLine() {
    if (multiple) return 'Multiple in-progress rounds';
    return '$courseName — $teeName';
  }

  String subtitleLine(String Function(DateTime) fmtDate) {
    if (multiple) return 'Tap to choose which round to resume';
    final last = lastHole == null ? 'Last: —' : 'Last: Hole $lastHole';
    return '${fmtDate(date)} • $last • Resume: Hole $resumeHole';
  }
}

final resumeInfoProvider =
    FutureProvider.autoDispose<_ResumeInfo?>((ref) async {
  final db = ref.read(databaseProvider);
  final active = await db.getInProgressRounds();
  if (active.isEmpty) return null;

  if (active.length > 1) {
    return _ResumeInfo(
      roundId: -1,
      courseName: '',
      teeName: '',
      date: DateTime.fromMillisecondsSinceEpoch(0),
      lastHole: null,
      resumeHole: 1,
      multiple: true,
    );
  }

  final r = active.first;
  final courses = await db.getAllCourses();
  final tees = await db.select(db.teeBoxTable).get();

  final courseName = courses.firstWhere((c) => c.id == r.courseId).name;
  final teeName = tees.firstWhere((t) => t.id == r.teeBoxId).name;

  final lastHole = await db.getLatestHoleNumberForRound(r.id);
  final resumeHole =
      lastHole == null ? 1 : (lastHole >= 18 ? 18 : lastHole + 1);

  return _ResumeInfo(
    roundId: r.id,
    courseName: courseName,
    teeName: teeName,
    date: r.date,
    lastHole: lastHole,
    resumeHole: resumeHole,
    multiple: false,
  );
});

class MainMenuScreen extends ConsumerStatefulWidget {
  const MainMenuScreen({super.key});

  @override
  ConsumerState<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends ConsumerState<MainMenuScreen>
    with RouteAware {
  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year}';
  }

  String _fmtToPar(int v) => v == 0 ? 'E' : (v > 0 ? '+$v' : '$v');

  Future<void> _showBackupRestoreSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backup & Restore',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Export Backup'),
                  subtitle: const Text(
                      'Share your local database file (AirDrop, Files, Drive, etc.)'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _exportDatabaseBackup();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Restore Backup'),
                  subtitle: const Text(
                      'Coming soon (requires a file picker for iOS + Android).'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Restore is coming soon.')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportDatabaseBackup() async {
    try {
      // Drift usually stores the sqlite file in the app documents directory.
      final docsDir = await getApplicationDocumentsDirectory();
      final files = docsDir.listSync().whereType<File>().where((f) {
        final name = f.path.toLowerCase();
        return name.endsWith('.sqlite') ||
            name.endsWith('.db') ||
            name.endsWith('.sqlite3');
      }).toList();

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No database file found to export.')),
        );
        return;
      }

      // Prefer a file that looks like our app DB, otherwise pick the newest.
      files
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      File dbFile = files.first;
      for (final f in files) {
        final n = f.path.toLowerCase();
        if (n.contains('golf') || n.contains('score')) {
          dbFile = f;
          break;
        }
      }

      final tmpDir = await getTemporaryDirectory();
      final ts =
          DateTime.now().toLocal().toIso8601String().replaceAll(':', '-');
      final baseName = dbFile.uri.pathSegments.isNotEmpty
          ? dbFile.uri.pathSegments.last
          : 'golf_scorecard.sqlite';

      final outMain = File('${tmpDir.path}/backup_${ts}_$baseName');
      await outMain.writeAsBytes(await dbFile.readAsBytes(), flush: true);

      // Also include WAL/SHM if they exist (common when SQLite uses WAL).
      final extras = <File>[];
      final wal = File('${dbFile.path}-wal');
      final shm = File('${dbFile.path}-shm');
      if (await wal.exists()) {
        final outWal = File('${outMain.path}-wal');
        await outWal.writeAsBytes(await wal.readAsBytes(), flush: true);
        extras.add(outWal);
      }
      if (await shm.exists()) {
        final outShm = File('${outMain.path}-shm');
        await outShm.writeAsBytes(await shm.readAsBytes(), flush: true);
        extras.add(outShm);
      }

      final shareFiles = <XFile>[
        XFile(outMain.path),
        ...extras.map((f) => XFile(f.path))
      ];

      // Compute anchor rect for iPad share sheet
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : (box.localToGlobal(Offset.zero) & box.size);

      await Share.shareXFiles(
        shareFiles,
        text: 'Golf Scorecard backup (SQLite).',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _resumeRound(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final active = await db.getInProgressRounds();
    if (active.isEmpty) return;

    if (active.length == 1) {
      final lastHole = await db.getLatestHoleNumberForRound(active.first.id);
      final resumeHole =
          lastHole == null ? 1 : (lastHole >= 18 ? 18 : lastHole + 1);

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HoleEntryScreen(
            roundId: active.first.id,
            initialHole: resumeHole,
          ),
        ),
      );
      return;
    }

    final courses = await db.getAllCourses();
    final tees = await db.select(db.teeBoxTable).get();
    final courseById = {for (final c in courses) c.id: c};
    final teeById = {for (final t in tees) t.id: t};

    if (!context.mounted) return;

    final pickedId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resume which round?'),
        content: ListView(
          shrinkWrap: true,
          children: active
              .map(
                (r) => ListTile(
                  title: Text(courseById[r.courseId]!.name),
                  subtitle: Text(
                      '${teeById[r.teeBoxId]!.name} • ${_fmtDate(r.date)}'),
                  onTap: () => Navigator.pop(ctx, r.id),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (pickedId == null || !context.mounted) return;

    final lastHole = await db.getLatestHoleNumberForRound(pickedId);
    final resumeHole =
        lastHole == null ? 1 : (lastHole >= 18 ? 18 : lastHole + 1);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HoleEntryScreen(
          roundId: pickedId,
          initialHole: resumeHole,
        ),
      ),
    );
  }

  Future<_QuickStart?> _loadQuickStart(WidgetRef ref) async {
    final db = ref.read(databaseProvider);

    final active = await db.getInProgressRounds();
    if (active.isNotEmpty) {
      final r = active.first;
      final course = await db.getCourse(r.courseId);
      final tee = await db.getTeeBox(r.teeBoxId);
      return _QuickStart(
        courseId: r.courseId,
        teeBoxId: r.teeBoxId,
        label: '${course!.name} — ${tee!.name} (in progress)',
      );
    }

    final completed = await db.getCompletedRoundsNewestFirst();
    if (completed.isEmpty) return null;

    final r = completed.first;
    final course = await db.getCourse(r.courseId);
    final tee = await db.getTeeBox(r.teeBoxId);

    return _QuickStart(
      courseId: r.courseId,
      teeBoxId: r.teeBoxId,
      label: '${course!.name} — ${tee!.name}',
    );
  }

  Future<List<_RecentRoundRow>> _loadRecentCompleted(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final rounds = (await db.getCompletedRoundsNewestFirst()).take(3).toList();
    if (rounds.isEmpty) return const [];

    final courses = await db.getAllCourses();
    final tees = await db.getAllTeeBoxes();
    final courseById = {for (final c in courses) c.id: c.name};
    final teeById = {for (final t in tees) t.id: t.name};

    final rows = <_RecentRoundRow>[];

    for (final r in rounds) {
      final holes = await db.getHolesForRoundOrdered(r.id);
      final courseHoles = await db.getCourseHolesForCourse(r.courseId);

      final score = holes.fold<int>(0, (s, h) => s + (h.score ?? 0));
      final par = courseHoles.fold<int>(0, (s, h) => s + h.par);

      rows.add(
        _RecentRoundRow(
          roundId: r.id,
          title: '${courseById[r.courseId]} — ${teeById[r.teeBoxId]}',
          subtitle: _fmtDate(r.date),
          score: score,
          toPar: score - par,
        ),
      );
    }

    return rows;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // We just returned to this screen; re-check for in-progress rounds.
    ref.invalidate(resumeInfoProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Golf Scorecard')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ===========================
          // PLAY
          // ===========================
          Builder(builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Play',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Start New Round'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const StartRoundScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  ref.watch(resumeInfoProvider).when(
                        data: (info) {
                          if (info == null) return const SizedBox.shrink();

                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      Colors.green.withOpacity(0.08),
                                  foregroundColor: Colors.green[800],
                                  side:
                                      BorderSide(color: Colors.green.shade400),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 12),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () => _resumeRound(context, ref),
                                label: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Resume Round',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 2),
                                    Text(
                                      info.titleLine(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      info.subtitleLine(_fmtDate),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (e, st) => const SizedBox.shrink(),
                      ),
                  const SizedBox(height: 14),
                  FutureBuilder<_QuickStart?>(
                    future: _loadQuickStart(ref),
                    builder: (context, snap) {
                      final qs = snap.data;
                      if (qs == null) return const SizedBox.shrink();

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Quick Start',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.flash_on_outlined),
                                label: Text(qs.label),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StartRoundScreen(
                                        initialCourseId: qs.courseId,
                                        initialTeeBoxId: qs.teeBoxId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // ===========================
          // REVIEW
          // ===========================
          Builder(builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Review',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.dashboard_outlined,
                    title: 'Dashboard',
                    subtitle: 'Trends and averages across rounds',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DashboardScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActionTile(
                    icon: Icons.history,
                    title: 'Saved Rounds',
                    subtitle: 'Browse completed rounds',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SavedRoundsScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  FutureBuilder<List<_RecentRoundRow>>(
                    future: _loadRecentCompleted(ref),
                    builder: (context, snap) {
                      final rows = snap.data ?? const [];
                      if (rows.isEmpty) return const SizedBox.shrink();

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: Card(
                            elevation: 0,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: scheme.outlineVariant),
                            ),
                            child: ExpansionTile(
                              maintainState: true,
                              tilePadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              title: Text(
                                '\u00A0\u00A0\u00A0Recent Rounds',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                              children: [
                                for (final r in rows) ...[
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(r.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    subtitle: Text(r.subtitle),
                                    trailing: _ScorePill(
                                      score: r.score,
                                      toPar: r.toPar,
                                      fmtToPar: _fmtToPar,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RoundSummaryScreen(
                                              roundId: r.roundId),
                                        ),
                                      );
                                    },
                                  ),
                                  if (r != rows.last) const Divider(height: 1),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // ===========================
          // MANAGE
          // ===========================
          Builder(builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manage',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.map_outlined,
                    title: 'Courses',
                    subtitle: 'Add or edit courses and tees',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CourseListScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActionTile(
                    icon: Icons.cloud_outlined,
                    title: 'Backup & Restore',
                    subtitle: 'Export a backup file (restore coming soon)',
                    onTap: _showBackupRestoreSheet,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _QuickStart {
  final int courseId;
  final int teeBoxId;
  final String label;
  const _QuickStart(
      {required this.courseId, required this.teeBoxId, required this.label});
}

class _RecentRoundRow {
  final int roundId;
  final String title;
  final String subtitle;
  final int score;
  final int toPar;
  const _RecentRoundRow({
    required this.roundId,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.toPar,
  });
}

class _ScorePill extends StatelessWidget {
  final int score;
  final int toPar;
  final String Function(int) fmtToPar;

  const _ScorePill({
    required this.score,
    required this.toPar,
    required this.fmtToPar,
  });

  @override
  Widget build(BuildContext context) {
    Color? c;
    if (toPar < 0) c = Colors.green[700];
    if (toPar > 0) c = Colors.red[700];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$score (${fmtToPar(toPar)})',
        style: TextStyle(fontWeight: FontWeight.w900, color: c),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon),
        title: Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
