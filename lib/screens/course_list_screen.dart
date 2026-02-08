import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';
import 'course_edit_screen.dart';

class CourseListScreen extends ConsumerStatefulWidget {
  const CourseListScreen({super.key});

  @override
  ConsumerState<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends ConsumerState<CourseListScreen> {
  Future<void> _refresh() async {
    setState(() {});
  }

  Future<void> _confirmDeleteCourse(
      BuildContext context, int courseId, String courseName) async {
    final db = ref.read(databaseProvider);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Course?'),
        content: Text(
          'Delete “$courseName”?\n\n'
          'This is only allowed if the course has no tee boxes and no rounds.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    final deleted = await db.deleteCourseIfUnused(courseId);
    if (!mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot delete: course has tee boxes or rounds.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course deleted.')),
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CourseEditScreen()),
              );
              await _refresh();
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: db.getAllCourses(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final courses = snapshot.data!;
          if (courses.isEmpty) {
            return const Center(
                child: Text('No courses yet. Tap + to add one.'));
          }

          return ListView.separated(
            itemCount: courses.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = courses[i];

              return ListTile(
                title: Text(c.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CourseEditScreen(courseId: c.id)),
                  );
                  await _refresh();
                },
                onLongPress: () => _confirmDeleteCourse(context, c.id, c.name),
              );
            },
          );
        },
      ),
    );
  }
}
