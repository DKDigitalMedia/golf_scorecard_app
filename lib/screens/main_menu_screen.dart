import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'about_screen.dart';

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

final resumeInfoProvider = FutureProvider.autoDispose<_ResumeInfo?>((
  ref,
) async {
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
  final resumeHole = lastHole == null
      ? 1
      : (lastHole >= 18 ? 18 : lastHole + 1);

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

  Future<void> _showBackupRestoreSheet(
    BuildContext pageContext,
    WidgetRef ref,
  ) async {
    if (!pageContext.mounted) return;

    await showModalBottomSheet<void>(
      context: pageContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (sheetContext, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                      'Share your local database file (AirDrop, Files, Drive, etc.)',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _exportDatabaseBackup(pageContext);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: const Text('Export CSV (Excel)'),
                    subtitle: const Text(
                      'All rounds, one row per hole (easy to analyze in Excel).',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _exportAllRoundsCsv();
                    },
                  ),
                  if (kDebugMode) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: const Text('Add Sample Rounds (Debug)'),
                      subtitle: const Text(
                        'Seeds 3 completed rounds with hole-by-hole stats.',
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _seedSampleRounds();
                      },
                    ),
                  ],
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Restore Backup'),
                    subtitle: const Text(
                      'Pick a backup file and replace the local database.',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _restoreDatabaseBackup(pageContext, ref);
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _exportDatabaseBackup(BuildContext context) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${docsDir.path}/golf_scorecard.sqlite');

      if (!await dbFile.exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No database file found to export.')),
        );
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final now = DateTime.now().toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      final friendlyDate =
          '${two(now.month)}-${two(now.day)}-${now.year}_${two(now.hour)}-${two(now.minute)}';
      final outMain = File(
        '${tmpDir.path}/golf_scorecard_backup_$friendlyDate.sqlite',
      );
      await outMain.writeAsBytes(await dbFile.readAsBytes(), flush: true);

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
        ...extras.map((f) => XFile(f.path)),
      ];

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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _restoreDatabaseBackup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final pickedPath = picked.path;
      final pickedName = picked.name;

      final lower = pickedName.toLowerCase();
      final isAllowed =
          lower.endsWith('.sqlite') ||
          lower.endsWith('.db') ||
          lower.endsWith('.sqlite3');

      if (!isAllowed) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please choose a .sqlite, .db, or .sqlite3 backup file.',
            ),
          ),
        );
        return;
      }

      Uint8List? pickedBytes = picked.bytes;
      if (pickedBytes == null && pickedPath != null && pickedPath.isNotEmpty) {
        final pickedFile = File(pickedPath);
        if (await pickedFile.exists()) {
          pickedBytes = await pickedFile.readAsBytes();
        }
      }

      if (pickedBytes == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the selected backup file.'),
          ),
        );
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restore Backup?'),
          content: const Text(
            'This will overwrite your current data. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restoring: $pickedName')));

      final docsDir = await getApplicationDocumentsDirectory();
      final destMain = File('${docsDir.path}/golf_scorecard.sqlite');
      final destWal = File('${destMain.path}-wal');
      final destShm = File('${destMain.path}-shm');

      final srcWal = (pickedPath == null || pickedPath.isEmpty)
          ? null
          : File('$pickedPath-wal');
      final srcShm = (pickedPath == null || pickedPath.isEmpty)
          ? null
          : File('$pickedPath-shm');

      final db = ref.read(databaseProvider);
      await db.close();

      if (await destWal.exists()) await destWal.delete();
      if (await destShm.exists()) await destShm.delete();
      if (await destMain.exists()) await destMain.delete();

      await destMain.writeAsBytes(pickedBytes, flush: true);

      if (srcWal != null && await srcWal.exists()) {
        await srcWal.copy(destWal.path);
      }
      if (srcShm != null && await srcShm.exists()) {
        await srcShm.copy(destShm.path);
      }

      ref.invalidate(databaseProvider);
      ref.invalidate(resumeInfoProvider);

      if (mounted) {
        setState(() {});
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> _resumeRound(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final active = await db.getInProgressRounds();
    if (active.isEmpty) return;

    if (active.length == 1) {
      final lastHole = await db.getLatestHoleNumberForRound(active.first.id);
      final resumeHole = lastHole == null
          ? 1
          : (lastHole >= 18 ? 18 : lastHole + 1);

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
                    '${teeById[r.teeBoxId]!.name} • ${_fmtDate(r.date)}',
                  ),
                  onTap: () => Navigator.pop(ctx, r.id),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (pickedId == null || !context.mounted) return;

    final lastHole = await db.getLatestHoleNumberForRound(pickedId);
    final resumeHole = lastHole == null
        ? 1
        : (lastHole >= 18 ? 18 : lastHole + 1);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HoleEntryScreen(roundId: pickedId, initialHole: resumeHole),
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
    ref.invalidate(resumeInfoProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Yet Another Golf Scorecard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // ===========================
            // PLAY
            // ===========================
            Builder(
              builder: (context) {
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
                      const Text(
                        'Play',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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
                                builder: (_) => const StartRoundScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      ref
                          .watch(resumeInfoProvider)
                          .when(
                            data: (info) {
                              if (info == null) return const SizedBox.shrink();

                              return Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.green.withOpacity(
                                        0.08,
                                      ),
                                      foregroundColor: Colors.green[800],
                                      side: BorderSide(
                                        color: Colors.green.shade400,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 12,
                                      ),
                                    ),
                                    icon: const Icon(Icons.play_arrow),
                                    onPressed: () => _resumeRound(context, ref),
                                    label: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Resume Round',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          info.titleLine(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
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
                                const Text(
                                  'Quick Start',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
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
              },
            ),

            const SizedBox(height: 16),

            // ===========================
            // REVIEW
            // ===========================
            Builder(
              builder: (context) {
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
                      const Text(
                        'Review',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ActionTile(
                        icon: Icons.dashboard_outlined,
                        title: 'Dashboard',
                        subtitle: 'Trends and averages across rounds',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DashboardScreen(),
                          ),
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
                            builder: (_) => const SavedRoundsScreen(),
                          ),
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
                                  side: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: ExpansionTile(
                                  maintainState: true,
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  title: Text(
                                    '\u00A0\u00A0\u00A0Recent Rounds',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  children: [
                                    for (final r in rows) ...[
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          r.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
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
                                              builder: (_) =>
                                                  RoundSummaryScreen(
                                                    roundId: r.roundId,
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      if (r != rows.last)
                                        const Divider(height: 1),
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
              },
            ),

            const SizedBox(height: 16),

            // ===========================
            // MANAGE
            // ===========================
            Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manage',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ActionTile(
                        icon: Icons.map_outlined,
                        title: 'Courses',
                        subtitle: 'Add or edit courses and tees',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CourseListScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ActionTile(
                        icon: Icons.cloud_outlined,
                        title: 'Backup & Restore',
                        subtitle: 'Backup, restore, or export data',
                        onTap: () => _showBackupRestoreSheet(context, ref),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: const Icon(Icons.info_outline),
                title: const Text(
                  'About This App',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Learn more about the app and planned features',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedSampleRounds() async {
    try {
      final db = ref.read(databaseProvider);

      final courses = await db.getAllCourses();
      final tees = await db.getAllTeeBoxes();
      if (courses.isEmpty || tees.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add at least one Course + Tee Box first.'),
          ),
        );
        return;
      }

      final course = courses.first;
      final tee = tees.firstWhere(
        (t) => t.courseId == course.id,
        orElse: () => tees.first,
      );

      final now = DateTime.now();
      const sampleDays = [2, 7, 14];
      for (var roundIndex = 0; roundIndex < sampleDays.length; roundIndex++) {
        final daysAgo = sampleDays[roundIndex];
        final rid = await db.createRound(courseId: course.id, teeBoxId: tee.id);

        await db.updateRoundMeta(
          roundId: rid,
          date: now.subtract(Duration(days: daysAgo)),
          weather: null,
          notes: switch (roundIndex) {
            0 => 'Sample round: good day',
            1 => 'Sample round: average day',
            _ => 'Sample round: rough day',
          },
        );

        for (var hole = 1; hole <= 18; hole++) {
          final putts = switch (roundIndex) {
            0 => (hole % 7 == 0) ? 3 : ((hole % 4 == 0) ? 1 : 2),
            1 => (hole % 5 == 0) ? 3 : ((hole % 3 == 0) ? 1 : 2),
            _ => (hole % 4 == 0) ? 3 : ((hole % 6 == 0) ? 1 : 2),
          };

          final penalties = switch (roundIndex) {
            0 => (hole % 11 == 0) ? 1 : 0,
            1 => (hole % 9 == 0) ? 1 : 0,
            _ => (hole % 6 == 0) ? 1 : ((hole % 13 == 0) ? 2 : 0),
          };

          final fir = switch (roundIndex) {
            0 => (hole % 4 == 0) ? 'R' : 'C',
            1 => (hole % 3 == 0) ? 'C' : ((hole % 2 == 0) ? 'R' : 'L'),
            _ => (hole % 4 == 0) ? 'L' : ((hole % 5 == 0) ? 'R' : 'C'),
          };

          final base = switch (roundIndex) {
            0 => 4, // better round
            1 => 5, // average round
            _ => 5, // rougher round
          };

          final swing = switch (roundIndex) {
            0 =>
              (hole % 8 == 0)
                  ? -1
                  : ((hole % 6 == 0) ? 1 : ((hole % 5 == 0) ? 0 : -1)),
            1 =>
              (hole % 8 == 0)
                  ? -1
                  : ((hole % 7 == 0) ? 2 : ((hole % 5 == 0) ? 1 : 0)),
            _ =>
              (hole % 9 == 0)
                  ? 3
                  : ((hole % 7 == 0) ? 2 : ((hole % 4 == 0) ? 1 : 0)),
          };

          final score = (base + swing + penalties).clamp(2, 10);

          String? loc;
          switch ((hole + roundIndex) % 5) {
            case 0:
              loc = 'C';
              break;
            case 1:
              loc = 'L';
              break;
            case 2:
              loc = 'R';
              break;
            case 3:
              loc = 'SHORT';
              break;
            case 4:
              loc = 'LONG';
              break;
          }

          final approachDistance = switch (roundIndex) {
            0 =>
              (hole % 4 == 0)
                  ? 105
                  : ((hole % 4 == 1) ? 140 : ((hole % 4 == 2) ? 85 : 160)),
            1 =>
              (hole % 4 == 0)
                  ? 120
                  : ((hole % 4 == 1) ? 155 : ((hole % 4 == 2) ? 90 : 175)),
            _ =>
              (hole % 4 == 0)
                  ? 135
                  : ((hole % 4 == 1) ? 170 : ((hole % 4 == 2) ? 110 : 185)),
          };

          final firstPuttDistance = switch (putts) {
            1 => roundIndex == 0 ? 8 : 6,
            2 => roundIndex == 2 ? 24 : 18,
            _ => roundIndex == 2 ? 42 : 35,
          };

          await db.upsertHole(
            roundId: rid,
            holeNumber: hole,
            score: score,
            putts: putts,
            penalties: penalties,
            fir: fir,
            approachLocation: loc,
            approachDistance: approachDistance,
            firstPuttDistance: firstPuttDistance,
          );
        }

        await db.markRoundCompleted(rid);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seeded 3 sample rounds.')));

      ref.invalidate(resumeInfoProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sample seeding failed: $e')));
    }
  }

  Future<void> _exportAllRoundsCsv() async {
    try {
      final db = ref.read(databaseProvider);

      final rounds = await db.getCompletedRoundsNewestFirst();
      if (rounds.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No completed rounds to export.')),
        );
        return;
      }

      final courses = await db.getAllCourses();
      final tees = await db.getAllTeeBoxes();

      final courseNameById = {for (final c in courses) c.id: c.name};
      final teeNameById = {for (final t in tees) t.id: t.name};
      final teeYardageById = {for (final t in tees) t.id: t.yardage};

      final parByCourseHole = <int, Map<int, int>>{};
      final siByCourseHole = <int, Map<int, int?>>{};

      Future<void> ensureCourseMaps(int courseId) async {
        if (parByCourseHole.containsKey(courseId)) return;
        final courseHoles = await db.getCourseHolesForCourse(courseId);
        parByCourseHole[courseId] = {
          for (final ch in courseHoles) ch.holeNumber: (ch.par ?? 0),
        };
        siByCourseHole[courseId] = {
          for (final ch in courseHoles) ch.holeNumber: ch.strokeIndex,
        };
      }

      String fmtRoundDate(DateTime dt) {
        final d = dt.toLocal();
        int hour = d.hour;
        final am = hour < 12;
        hour = hour % 12;
        if (hour == 0) hour = 12;
        final mm = d.minute.toString().padLeft(2, '0');
        return '${d.month}/${d.day}/${d.year} $hour:$mm ${am ? 'AM' : 'PM'}';
      }

      String csvEscape(Object? v) {
        if (v == null) return '';
        final s = v.toString();
        final needsQuotes =
            s.contains(',') ||
            s.contains('"') ||
            s.contains('\n') ||
            s.contains('\r');
        if (!needsQuotes) return s;
        return '"${s.replaceAll('"', '""')}"';
      }

      final header = <String>[
        'round_id',
        'round_date',
        'course',
        'tee_box',
        'hole_number',
        'par',
        'yardage',
        'stroke_index',
        'score',
        'to_par',
        'putts',
        'penalties',
        'fir',
        'approach_location',
        'approach_distance',
        'first_putt_distance',
        'greenside_bunker',
        'hole_notes',
      ].join(',');

      final sb = StringBuffer();
      sb.writeln(header);

      for (final r in rounds) {
        await ensureCourseMaps(r.courseId);

        final parMap = parByCourseHole[r.courseId] ?? const <int, int>{};
        final siMap = siByCourseHole[r.courseId] ?? const <int, int?>{};

        T? pickJson<T>(Map<String, dynamic> m, List<String> keys) {
          for (final k in keys) {
            final v = m[k];
            if (v is T) return v;
            if (v != null) {
              if (T == int && v is num) return v.toInt() as T;
              if (T == double && v is num) return v.toDouble() as T;
              if (T == String) return v.toString() as T;
            }
          }
          return null;
        }

        final holes = await db.getHolesForRoundOrdered(r.id);
        for (final h in holes) {
          final par = parMap[h.holeNumber] ?? 0;
          final score = h.score;
          final toPar = (score == null) ? null : (score - par);

          final j = h.toJson();
          final row = <Object?>[
            r.id,
            fmtRoundDate(r.date),
            courseNameById[r.courseId] ?? '',
            teeNameById[r.teeBoxId] ?? '',
            h.holeNumber,
            par == 0 ? null : par,
            teeYardageById[r.teeBoxId],
            siMap[h.holeNumber],
            score,
            toPar,
            pickJson<int>(j, const ['putts']) ?? h.putts,
            pickJson<int>(j, const ['penalties']) ?? h.penalties,
            pickJson<String>(j, const ['fir']) ?? h.fir,
            pickJson<String>(j, const [
                  'approachLocation',
                  'approach_location',
                ]) ??
                h.approachLocation,
            pickJson<int>(j, const ['approachDistance', 'approach_distance']) ??
                h.approachDistance,
            pickJson<int>(j, const [
                  'firstPuttDistance',
                  'first_putt_distance',
                ]) ??
                h.firstPuttDistance,
            pickJson<bool>(j, const ['greensideBunker', 'greenside_bunker']) ??
                h.greensideBunker,
            pickJson<String>(j, const ['holeNotes', 'hole_notes']) ??
                h.holeNotes,
          ];

          sb.writeln(row.map(csvEscape).join(','));
        }
      }

      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().toLocal().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final out = File('${tmpDir.path}/golf_scorecard_export_$ts.csv');
      await out.writeAsString(sb.toString(), flush: true);

      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : (box.localToGlobal(Offset.zero) & box.size);

      await Share.shareXFiles(
        [XFile(out.path)],
        text: 'Golf Scorecard export (CSV for Excel).',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }
}

class _QuickStart {
  final int courseId;
  final int teeBoxId;
  final String label;

  const _QuickStart({
    required this.courseId,
    required this.teeBoxId,
    required this.label,
  });
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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
