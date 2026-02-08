import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';

class CourseHolesEditorScreen extends ConsumerStatefulWidget {
  final int courseId;
  const CourseHolesEditorScreen({super.key, required this.courseId});

  @override
  ConsumerState<CourseHolesEditorScreen> createState() =>
      _CourseHolesEditorScreenState();
}

class _CourseHolesEditorScreenState
    extends ConsumerState<CourseHolesEditorScreen> {
  bool _loading = true;

  bool _parSiExpanded = true;
  bool _yardExpanded = false;

  int? _openParSiHole; // 0..17
  int? _openYardHole; // 0..17

  List<CourseHole> _courseHoles = [];
  List<TeeBox> _teeBoxes = [];
  TeeBox? _selectedTee;
  List<TeeBoxHole> _teeHoles = [];

  // Par selections (1–18)
  final List<int> _pars = List.generate(18, (_) => 4);

  // Stroke Index values (nullable = unused)
  final List<int?> _strokeIndexes = List.generate(18, (_) => null);

  // Yardage values (nullable = unused)
  final List<int?> _yardages = List.generate(18, (_) => null);

  // Controllers so fields remain editable across rebuilds
  final List<TextEditingController> _siCtrls =
      List.generate(18, (_) => TextEditingController());
  final List<TextEditingController> _yardCtrls =
      List.generate(18, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in _siCtrls) {
      c.dispose();
    }
    for (final c in _yardCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    final db = ref.read(databaseProvider);

    final tees = await db.getTeeBoxesForCourse(widget.courseId);
    final ch = await db.getCourseHolesForCourse(widget.courseId);

    setState(() {
      _teeBoxes = tees;
      _selectedTee = tees.isNotEmpty ? tees.first : null;
      _courseHoles = ch;
    });

    _applyCourseHolesToUI();

    if (_selectedTee != null) {
      await _loadTeeHoles(_selectedTee!.id);
    } else {
      setState(() => _loading = false);
    }
  }

  void _applyCourseHolesToUI() {
    for (int i = 0; i < 18; i++) {
      final holeNum = i + 1;
      final existing =
          _courseHoles.where((h) => h.holeNumber == holeNum).toList();

      if (existing.isNotEmpty) {
        _pars[i] = existing.first.par;
        final si = existing.first.strokeIndex;
        _strokeIndexes[i] = (si == null || si == 0) ? null : si;
      } else {
        _pars[i] = 4;
        _strokeIndexes[i] = null;
      }

      // Only set text if user isn't actively typing
      final siText = _strokeIndexes[i]?.toString() ?? '';
      if (_siCtrls[i].text != siText) {
        _siCtrls[i].text = siText;
      }
    }
  }

  Future<void> _loadTeeHoles(int teeBoxId) async {
    setState(() {
      _loading = true;
      _teeHoles = [];
    });

    final db = ref.read(databaseProvider);
    final th = await db.getTeeBoxHoles(teeBoxId);

    setState(() {
      _teeHoles = th;
      _loading = false;
    });

    for (int i = 0; i < 18; i++) {
      final holeNum = i + 1;
      final existing = _teeHoles.where((h) => h.holeNumber == holeNum).toList();
      final y = existing.isNotEmpty ? existing.first.yardage : null;
      _yardages[i] = (y == null || y == 0) ? null : y;

      final yardText = _yardages[i]?.toString() ?? '';
      if (_yardCtrls[i].text != yardText) {
        _yardCtrls[i].text = yardText;
      }
    }
  }

  Future<void> _saveAll() async {
    final db = ref.read(databaseProvider);

    // Save course holes (par + stroke index)
    for (int i = 0; i < 18; i++) {
      final holeNum = i + 1;
      final par = _pars[i];

      final si = _strokeIndexes[i];
      final validSi = (si == null || si <= 0) ? null : si.clamp(1, 18);

      await db.upsertCourseHole(
        courseId: widget.courseId,
        holeNumber: holeNum,
        par: par,
        strokeIndex: validSi,
      );
    }

    // Save yardages for selected tee
    final tee = _selectedTee;
    if (tee != null) {
      for (int i = 0; i < 18; i++) {
        final holeNum = i + 1;

        final yard = _yardages[i];
        final validYard =
            (yard == null || yard == 0) ? null : yard.clamp(1, 650);

        await db.upsertTeeBoxHole(
          teeBoxId: tee.id,
          holeNumber: holeNum,
          yardage: validYard,
        );
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved hole pars / SI / yardages')),
    );

    await _loadAll();
  }

  Widget _parChips(int index) {
    return Wrap(
      spacing: 8,
      children: [3, 4, 5].map((p) {
        return ChoiceChip(
          label: Text('Par $p'),
          selected: _pars[index] == p,
          onSelected: (_) => setState(() => _pars[index] = p),
        );
      }).toList(),
    );
  }

  // ✅ Stroke Index: editable text field (+ clear)
  Widget _strokeIndexField(int index) {
    return Row(
      children: [
        const Text(
          'Stroke Index:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() {
            _strokeIndexes[index] = null;
            _siCtrls[index].text = '';
          }),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: TextField(
            controller: _siCtrls[index],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '1-18',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (txt) {
              final v = int.tryParse(txt);
              setState(() {
                _strokeIndexes[index] = v;
              });
            },
          ),
        ),
      ],
    );
  }

  // ✅ Yardage: slider + editable text field (+ clear)
  Widget _yardageSlider(int index) {
    const int minYard = 0;
    const int maxYard = 650;

    final value = _yardages[index];

    void setVal(int? v) {
      if (v == null) {
        setState(() {
          _yardages[index] = null;
          _yardCtrls[index].text = '';
        });
        return;
      }
      final clamped = v.clamp(minYard, maxYard);
      setState(() {
        _yardages[index] = clamped;
        _yardCtrls[index].text = clamped.toString();
      });
    }

    final sliderValue = (value ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Yardage:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () => setVal(null),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _yardCtrls[index],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  hintText: '0-650',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (txt) {
                  final v = int.tryParse(txt);
                  setState(() {
                    _yardages[index] = (v == null || v == 0) ? null : v;
                  });
                },
                onEditingComplete: () {
                  final v = int.tryParse(_yardCtrls[index].text);
                  if (v == null || v == 0) {
                    setVal(null);
                  } else {
                    setVal(v);
                  }
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
            const Spacer(),
            Text(
              value == null ? '-' : value.toString(),
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: sliderValue,
          min: minYard.toDouble(),
          max: maxYard.toDouble(),
          divisions: maxYard - minYard,
          label: value == null ? '-' : value.toString(),
          onChanged: (d) {
            final v = d.round();
            // 0 means "empty" (null) to keep “optional yardage” behavior
            setVal(v == 0 ? null : v);
          },
        ),
      ],
    );
  }

  Widget _smallPill(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface.withOpacity(0.75),
        ),
      ),
    );
  }

  Widget _parSiRow(int i) {
    final holeNum = i + 1;
    final par = _pars[i];
    final si = _strokeIndexes[i];
    final isOpen = _openParSiHole == i;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text('Hole $holeNum'),
          trailing: Wrap(
            spacing: 8,
            children: [
              _smallPill('Par $par'),
              _smallPill(si == null ? 'SI —' : 'SI $si'),
            ],
          ),
          onTap: () {
            setState(() {
              _openParSiHole = isOpen ? null : i;
            });
          },
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _parChips(i),
                const SizedBox(height: 10),
                _strokeIndexField(i),
              ],
            ),
          ),
      ],
    );
  }

  Widget _yardageRow(int i) {
    final holeNum = i + 1;
    final yard = _yardages[i];
    final isOpen = _openYardHole == i;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text('Hole $holeNum'),
          trailing: _smallPill(yard == null ? '—' : '${yard}y'),
          onTap: () {
            setState(() {
              _openYardHole = isOpen ? null : i;
            });
          },
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _yardageSlider(i),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Holes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _saveAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: _parSiExpanded,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _parSiExpanded = expanded;
                        if (expanded) {
                          _yardExpanded = false;
                          _openYardHole = null;
                        } else {
                          _openParSiHole = null;
                        }
                      });
                    },
                    title: const Text(
                      'Course holes (Par + Stroke Index)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: Builder(
                          builder: (context) {
                            final setCount =
                                _strokeIndexes.where((v) => v != null).length;
                            return Text(
                              'Stroke Index set: $setCount / 18',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            );
                          },
                        ),
                      ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 18,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _parSiRow(i),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: _yardExpanded,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _yardExpanded = expanded;
                        if (expanded) {
                          _parSiExpanded = false;
                          _openParSiHole = null;
                        } else {
                          _openYardHole = null;
                        }
                      });
                    },
                    title: const Text(
                      'Tee yardages (per hole)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      if (_teeBoxes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(
                              top: 8, left: 8, right: 8, bottom: 8),
                          child: Text('No tee boxes yet. Add a tee box first.'),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          child: DropdownButtonFormField<TeeBox>(
                            value: _selectedTee,
                            decoration: const InputDecoration(
                              labelText: 'Tee Box',
                              border: OutlineInputBorder(),
                            ),
                            isExpanded: true,
                            items: _teeBoxes
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(
                                        '${t.name} • ${t.yardage} • ${t.rating} / ${t.slope}',
                                      ),
                                    ))
                                .toList(),
                            onChanged: (t) async {
                              if (t == null) return;
                              setState(() {
                                _selectedTee = t;
                                _openYardHole = null;
                              });
                              await _loadTeeHoles(t.id);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Builder(
                            builder: (context) {
                              final setCount =
                                  _yardages.where((v) => v != null).length;
                              return Text(
                                'Yardages set: $setCount / 18',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.6),
                                ),
                              );
                            },
                          ),
                        ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 18,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _yardageRow(i),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveAll,
                    child: const Text('Save All'),
                  ),
                ),
              ],
            ),
    );
  }
}
