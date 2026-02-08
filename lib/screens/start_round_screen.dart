import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'course_list_screen.dart';
import 'hole_entry_screen.dart';

class StartRoundScreen extends ConsumerStatefulWidget {
  final int? initialCourseId;
  final int? initialTeeBoxId;

  const StartRoundScreen({
    super.key,
    this.initialCourseId,
    this.initialTeeBoxId,
  });

  @override
  ConsumerState<StartRoundScreen> createState() => _StartRoundScreenState();
}

class _StartRoundScreenState extends ConsumerState<StartRoundScreen> {
  bool _loading = true;

  List<Course> _courses = [];
  List<TeeBox> _teeBoxes = [];

  Course? _selectedCourse;
  TeeBox? _selectedTee;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final db = ref.read(databaseProvider);

    setState(() => _loading = true);

    final courses = await db.getAllCourses();

    Course? selectedCourse;
    List<TeeBox> tees = [];
    TeeBox? selectedTee;

    if (courses.isNotEmpty) {
      // Try initial course first, else default to first
      selectedCourse = widget.initialCourseId == null
          ? courses.first
          : courses.firstWhere(
              (c) => c.id == widget.initialCourseId,
              orElse: () => courses.first,
            );

      tees = await db.getTeeBoxesForCourse(selectedCourse.id);

      if (tees.isNotEmpty) {
        // Try initial tee first, else default to first tee for that course
        selectedTee = widget.initialTeeBoxId == null
            ? tees.first
            : tees.firstWhere(
                (t) => t.id == widget.initialTeeBoxId,
                orElse: () => tees.first,
              );
      } else {
        selectedTee = null;
      }
    } else {
      selectedCourse = null;
      tees = [];
      selectedTee = null;
    }

    if (!mounted) return;
    setState(() {
      _courses = courses;
      _selectedCourse = selectedCourse;
      _teeBoxes = tees;
      _selectedTee = selectedTee;
      _loading = false;
    });
  }

  Future<void> _onCourseChanged(Course? course) async {
    if (course == null) return;
    final db = ref.read(databaseProvider);

    setState(() {
      _selectedCourse = course;
      _selectedTee = null;
      _teeBoxes = [];
      _loading = true;
    });

    final tees = await db.getTeeBoxesForCourse(course.id);

    if (!mounted) return;
    setState(() {
      _teeBoxes = tees;
      _selectedTee = tees.isNotEmpty ? tees.first : null;
      _loading = false;
    });
  }

  void _goToCourses() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CourseListScreen()),
    ).then((_) => _loadCourses());
  }

  Future<void> _beginRound() async {
    final db = ref.read(databaseProvider);

    if (_selectedCourse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a course first.')),
      );
      return;
    }
    if (_selectedTee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a tee box first.')),
      );
      return;
    }

    // ✅ Enforce one active round
    final existing = await db.getLatestInProgressRound();
    if (existing != null) {
      if (!mounted) return;

      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('In-progress round exists'),
          content: const Text(
            'You can only have one active round at a time.\n\n'
            'Resume your current round, or abandon it to start a new one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'abandon'),
              child: const Text('Abandon'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'resume'),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (choice == 'resume') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => HoleEntryScreen(roundId: existing.id)),
        );
        return;
      }

      if (choice == 'abandon') {
        await db.setRoundCompleted(existing.id, true);
        // continue to create a new round below
      } else {
        // cancel or dismissed
        return;
      }
    }

    final roundId = await db.createRound(
      courseId: _selectedCourse!.id,
      teeBoxId: _selectedTee!.id,
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HoleEntryScreen(roundId: roundId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noCourses = !_loading && _courses.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Start Round')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : noCourses
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No courses yet.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Add a course before starting your first round.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _goToCourses,
                          child: const Text('Add Course'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<Course>(
                        value: _selectedCourse,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Course',
                          border: OutlineInputBorder(),
                        ),
                        items: _courses
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c.name),
                                ))
                            .toList(),
                        onChanged: _onCourseChanged,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TeeBox>(
                        value: _selectedTee,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tee Box',
                          border: OutlineInputBorder(),
                        ),
                        items: _teeBoxes
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                    '${t.name} • ${t.yardage} • ${t.rating} / ${t.slope}',
                                  ),
                                ))
                            .toList(),
                        onChanged: (t) => setState(() => _selectedTee = t),
                      ),
                      if (_selectedCourse != null && _teeBoxes.isEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'No tee boxes for this course yet.',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton(
                          onPressed: _goToCourses,
                          child: const Text('Add Tee Boxes'),
                        ),
                      ],
                      const Spacer(),
                      ElevatedButton(
                        onPressed:
                            (_selectedCourse != null && _selectedTee != null)
                                ? _beginRound
                                : null,
                        child: const Text('Begin Round'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
