import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'course_holes_editor_screen.dart';

class CourseEditScreen extends ConsumerStatefulWidget {
  final int? courseId;
  const CourseEditScreen({super.key, this.courseId});

  @override
  ConsumerState<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends ConsumerState<CourseEditScreen> {
  final _courseNameCtrl = TextEditingController();

  final _teeNameCtrl = TextEditingController(text: 'White');
  final _yardageCtrl = TextEditingController(text: '6200');
  final _ratingCtrl = TextEditingController(text: '70.5');
  final _slopeCtrl = TextEditingController(text: '125');

  int? _courseId;
  List<TeeBox> _tees = [];
  bool _loading = true;

  bool _addNewTeeExpanded = false;

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void dispose() {
    _courseNameCtrl.dispose();
    _teeNameCtrl.dispose();
    _yardageCtrl.dispose();
    _ratingCtrl.dispose();
    _slopeCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    final db = ref.read(databaseProvider);

    if (widget.courseId == null) {
      setState(() => _loading = false);
      return;
    }

    final courses = await db.getAllCourses();
    final course = courses.firstWhere((c) => c.id == widget.courseId);

    final tees = await db.getTeeBoxesForCourse(course.id);

    setState(() {
      _courseId = course.id;
      _courseNameCtrl.text = course.name;
      _tees = tees;
      _loading = false;
    });
  }

  bool _teeNameExists(String name, {int? excludeTeeBoxId}) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return false;

    return _tees.any((t) {
      if (excludeTeeBoxId != null && t.id == excludeTeeBoxId) return false;
      return t.name.trim().toLowerCase() == needle;
    });
  }

  Future<void> _refreshTees() async {
    final db = ref.read(databaseProvider);
    if (_courseId == null) return;
    final tees = await db.getTeeBoxesForCourse(_courseId!);
    setState(() => _tees = tees);
  }

  Future<void> _saveCourse() async {
    final db = ref.read(databaseProvider);
    final name = _courseNameCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course name required')),
      );
      return;
    }

    if (_courseId == null) {
      final newId = await db.into(db.courses).insert(
            CoursesCompanion.insert(name: name),
          );
      setState(() => _courseId = newId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course created.')),
      );
    } else {
      await db.updateCourseName(_courseId!, name);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course updated.')),
      );
    }
  }

  Future<void> _addTeeBoxQuick() async {
    final db = ref.read(databaseProvider);

    if (_courseId == null) {
      await _saveCourse();
      if (_courseId == null) return;
    }

    final teeName = _teeNameCtrl.text.trim();
    final yardage = int.tryParse(_yardageCtrl.text.trim());
    final rating = double.tryParse(_ratingCtrl.text.trim());
    final slope = int.tryParse(_slopeCtrl.text.trim());

    if (teeName.isEmpty || yardage == null || rating == null || slope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill tee box fields correctly')),
      );
      return;
    }

    if (_teeNameExists(teeName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tee box name already exists for this course.'),
        ),
      );
      return;
    }

    await db.into(db.teeBoxTable).insert(
          TeeBoxTableCompanion.insert(
            courseId: _courseId!,
            name: teeName,
            yardage: yardage,
            rating: rating,
            slope: slope,
          ),
        );

    await _refreshTees();
    if (!mounted) return;
    setState(() => _addNewTeeExpanded = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tee box added.')),
    );
  }

  Future<void> _editTeeBoxDialog(TeeBox tee) async {
    final db = ref.read(databaseProvider);

    final nameCtrl = TextEditingController(text: tee.name);
    final yardCtrl = TextEditingController(text: tee.yardage.toString());
    final ratingCtrl = TextEditingController(text: tee.rating.toString());
    final slopeCtrl = TextEditingController(text: tee.slope.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Tee Box'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: yardCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Yardage',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ratingCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rating',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: slopeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Slope',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      nameCtrl.dispose();
      yardCtrl.dispose();
      ratingCtrl.dispose();
      slopeCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    final yardage = int.tryParse(yardCtrl.text.trim());
    final rating = double.tryParse(ratingCtrl.text.trim());
    final slope = int.tryParse(slopeCtrl.text.trim());

    nameCtrl.dispose();
    yardCtrl.dispose();
    ratingCtrl.dispose();
    slopeCtrl.dispose();

    if (name.isEmpty || yardage == null || rating == null || slope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid tee box values')),
      );
      return;
    }

    if (_teeNameExists(name, excludeTeeBoxId: tee.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Another tee box already uses that name.'),
        ),
      );
      return;
    }

    await db.updateTeeBox(
      teeBoxId: tee.id,
      name: name,
      yardage: yardage,
      rating: rating,
      slope: slope,
    );

    await _refreshTees();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tee box updated.')),
    );
  }

  Future<void> _deleteTeeBox(TeeBox tee) async {
    final db = ref.read(databaseProvider);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Tee Box?'),
        content: Text(
          'Delete tee box “${tee.name}”? \n\n'
          'This is only allowed if no rounds use this tee box.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final deleted = await db.deleteTeeBoxIfUnused(tee.id);
    if (!mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete: tee box is used by a round.'),
        ),
      );
      return;
    }

    await _refreshTees();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tee box deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.courseId == null && _courseId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Add Course' : 'Edit Course'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text(
                      'Course',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextField(
                          controller: _courseNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Course Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveCourse,
                          child: const Text('Save Course'),
                        ),
                      ),
                      if (_courseId != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CourseHolesEditorScreen(
                                      courseId: _courseId!),
                                ),
                              );
                            },
                            child:
                                const Text('Edit Holes (Par / SI / Yardages)'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Tee Boxes section (NOT collapsible)
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tee Boxes',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),

                        const Text(
                          'Existing Tee Boxes',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        if (_tees.isEmpty)
                          const Text('No tee boxes yet.')
                        else
                          ..._tees.map(
                            (t) => Card(
                              child: ListTile(
                                title: Text(t.name),
                                subtitle: Text(
                                  'Yardage ${t.yardage} • Rating ${t.rating} • Slope ${t.slope}',
                                ),
                                onTap: () => _editTeeBoxDialog(t),
                                onLongPress: () => _deleteTeeBox(t),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        // Only this part is collapsible:
                        Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          child: ExpansionTile(
                            initiallyExpanded: _addNewTeeExpanded,
                            onExpansionChanged: (v) {
                              setState(() => _addNewTeeExpanded = v);
                            },
                            title: const Text(
                              'Add a New Tee Box',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(0, 0, 0, 16),
                            children: [
                              TextField(
                                controller: _teeNameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Tee Name (e.g., White)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _yardageCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Yardage',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _ratingCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Rating',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _slopeCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Slope',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _addTeeBoxQuick,
                                  child: const Text('Add Tee Box'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
