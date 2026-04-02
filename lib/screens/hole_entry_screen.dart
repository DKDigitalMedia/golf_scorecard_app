import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'round_summary_screen.dart';

class HoleEntryScreen extends ConsumerStatefulWidget {
  final int roundId;
  final int initialHole;

  /// When true, show a small "Editing" indicator in the UI.
  final bool editMode;

  const HoleEntryScreen({
    super.key,
    required this.roundId,
    this.initialHole = 1,
    this.editMode = false,
  });

  @override
  ConsumerState<HoleEntryScreen> createState() => _HoleEntryScreenState();
}

class _HoleEntryScreenState extends ConsumerState<HoleEntryScreen> {
  int _holeNumber = 1;
  int _navDir = 1; // +1 next, -1 back

  int? _score; // 1..10
  int? _putts; // 0..4
  int? _penalties; // 0..2

  String? _fir; // "L" | "C" | "R"
  String? _approachLocation; // "L" | "C" | "R" | "LONG" | "SHORT"

  int? _approachDistance; // 0..175
  int? _firstPuttDistance; // 0..60

  bool? _greensideBunker; // null/true/false
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _approachDistanceCtrl = TextEditingController();
  final TextEditingController _firstPuttDistanceCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;

  bool _showResumeBanner = false;

  final ScrollController _scrollController = ScrollController();

  Timer? _autoSaveTimer;

  final Map<int, CourseHole> _courseHoleByNum = {};
  final Map<int, TeeBoxHole> _teeHoleByNum = {};

  @override
  void initState() {
    super.initState();
    _holeNumber = widget.initialHole.clamp(1, 18);
    _init();

    _notesCtrl.addListener(_onNotesChanged);
    _approachDistanceCtrl.addListener(_onApproachDistanceTextChanged);
    _firstPuttDistanceCtrl.addListener(_onFirstPuttDistanceTextChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _scrollController.dispose();
    _notesCtrl.dispose();
    _approachDistanceCtrl.dispose();
    _firstPuttDistanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final db = ref.read(databaseProvider);

    final r = await db.getRound(widget.roundId);

    if (r != null) {
      final ch = await db.getCourseHolesForCourse(r.courseId);
      _courseHoleByNum
        ..clear()
        ..addEntries(ch.map((h) => MapEntry(h.holeNumber, h)));

      final th = await db.getTeeBoxHoles(r.teeBoxId);
      _teeHoleByNum
        ..clear()
        ..addEntries(th.map((h) => MapEntry(h.holeNumber, h)));
    }

    // If this round already has saved holes, show a temporary resume banner.
    final lastHole = await db.getLatestHoleNumberForRound(widget.roundId);
    final isResuming = lastHole != null && lastHole > 0;

    if (isResuming && mounted) {
      setState(() => _showResumeBanner = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _showResumeBanner = false);
        }
      });
    }

    await _loadHole(_holeNumber);
    _scrollToTop();
  }

  void _onNotesChanged() {
    // Keep autosave behavior
    _scheduleAutoSave();
  }

  // ---------------- Autosave (debounced) ----------------

  void _scheduleAutoSave() {
    // Don’t autosave while loading or during a navigation save/load.
    if (_loading || _busy) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      if (_busy || _loading) return;
      await _saveCurrentHole();
    });
  }

  void _cancelAutoSave() => _autoSaveTimer?.cancel();

  // ---------------- Navigation (buttons + swipe) ----------------

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _onSwipe(DragEndDetails details) async {
    final velocity = details.primaryVelocity ?? 0;

    // Right swipe (positive) => Back
    if (velocity > 350) {
      await _goBack();
    }

    // Left swipe (negative) => Next
    if (velocity < -350) {
      await _goNext();
    }
  }

  Future<void> _goBack() async {
    if (_holeNumber <= 1) return;
    if (_loading || _busy) return;

    _navDir = -1;
    _cancelAutoSave();

    final target = _holeNumber - 1;

    final ok = await _saveCurrentHole();
    if (!ok) return;

    await _loadHole(target);
    _scrollToTop();
  }

  Future<void> _goNext() async {
    if (_loading || _busy) return;

    // Require score before moving forward (keeps on-course flow sane)
    if (_score == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a score before moving on.')),
      );
      return;
    }

    _navDir = 1;
    _cancelAutoSave();

    final isLastHole = _holeNumber == 18;
    final target = _holeNumber + 1;

    final ok = await _saveCurrentHole();
    if (!ok) return;

    if (isLastHole) {
      await _finishRound();
      return;
    }

    await _loadHole(target);
    _scrollToTop();
  }

  Future<void> _finishRound() async {
    if (_loading || _busy) return;

    _cancelAutoSave();

    final ok = await _saveCurrentHole();
    if (!ok) return;

    final db = ref.read(databaseProvider);
    await db.setRoundCompleted(widget.roundId, true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RoundSummaryScreen(roundId: widget.roundId),
      ),
    );
  }

  // ---------------- Load/Save ----------------

  Future<void> _loadHole(int holeNumber) async {
    if (_busy) return;
    _busy = true;

    var didSetLoadingTrue = false;

    try {
      if (mounted) {
        didSetLoadingTrue = true;
        setState(() => _loading = true);
      }

      final db = ref.read(databaseProvider);
      final hole = await db.getHole(widget.roundId, holeNumber);

      if (!mounted) return;

      setState(() {
        _holeNumber = holeNumber;

        _score = hole?.score;
        _putts = hole?.putts;
        _penalties = hole?.penalties;

        _fir = hole?.fir;
        _approachLocation = hole?.approachLocation;

        _approachDistance = hole?.approachDistance;
        _firstPuttDistance = hole?.firstPuttDistance;
        _approachDistanceCtrl.text = _approachDistance?.toString() ?? '';
        _firstPuttDistanceCtrl.text = _firstPuttDistance?.toString() ?? '';

        _greensideBunker = hole?.greensideBunker;
        _notesCtrl.text = hole?.holeNotes ?? '';

        _loading = false;
      });
    } finally {
      _busy = false;
      if (mounted && didSetLoadingTrue && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _hasAnythingToSave {
    return _score != null ||
        _putts != null ||
        _penalties != null ||
        _fir != null ||
        _approachLocation != null ||
        _approachDistance != null ||
        _firstPuttDistance != null ||
        _greensideBunker != null ||
        _notesCtrl.text.trim().isNotEmpty;
  }

  Future<bool> _saveCurrentHole() async {
    if (_busy) return false;

    // Don’t create an empty record
    if (!_hasAnythingToSave) return true;

    _busy = true;

    try {
      final db = ref.read(databaseProvider);

      await db.upsertHole(
        roundId: widget.roundId,
        holeNumber: _holeNumber,
        score: _score,
        putts: _putts,
        penalties: _penalties,
        fir: _fir,
        approachLocation: _approachLocation,
        approachDistance: _approachDistance,
        firstPuttDistance: _firstPuttDistance,
        greensideBunker: _greensideBunker,
        holeNotes: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
      );

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
      return false;
    } finally {
      _busy = false;
    }
  }

  // ---------------- TextField Distance Sync helpers ----------------

  void _onApproachDistanceTextChanged() {
    if (_loading || _busy) return;
    final txt = _approachDistanceCtrl.text.trim();
    if (txt.isEmpty) {
      if (_approachDistance != null) {
        setState(() => _approachDistance = null);
        _scheduleAutoSave();
      }
      return;
    }

    final parsed = int.tryParse(txt);
    if (parsed == null) return;
    final clamped = parsed.clamp(0, 175);
    if (clamped != _approachDistance) {
      setState(() => _approachDistance = clamped);
      _scheduleAutoSave();
    }
  }

  void _onFirstPuttDistanceTextChanged() {
    if (_loading || _busy) return;
    final txt = _firstPuttDistanceCtrl.text.trim();
    if (txt.isEmpty) {
      if (_firstPuttDistance != null) {
        setState(() => _firstPuttDistance = null);
        _scheduleAutoSave();
      }
      return;
    }

    final parsed = int.tryParse(txt);
    if (parsed == null) return;
    final clamped = parsed.clamp(0, 60);
    if (clamped != _firstPuttDistance) {
      setState(() => _firstPuttDistance = clamped);
      _scheduleAutoSave();
    }
  }

  // ---------------- Computed fields ----------------

  int? get _par => _courseHoleByNum[_holeNumber]?.par;
  int? get _strokeIndex => _courseHoleByNum[_holeNumber]?.strokeIndex;
  int? get _yardage => _teeHoleByNum[_holeNumber]?.yardage;

  bool? get _gir {
    final par = _par;
    final score = _score;
    final putts = _putts;
    if (par == null || score == null || putts == null) return null;

    // GIR if strokes_to_green <= par - 2
    final strokesToGreen = score - putts;
    return strokesToGreen <= (par - 2);
  }

  bool? get _upAndDown {
    final par = _par;
    final score = _score;
    final gir = _gir;
    if (par == null || score == null || gir == null) return null;

    // Up & down: missed GIR but made par or better
    return (gir == false) && (score <= par);
  }

  // ---------------- UI helpers ----------------

  Widget _sectionTitle(String text, {EdgeInsetsGeometry? padding}) => Padding(
    padding: padding ?? const EdgeInsets.only(top: 16, bottom: 6), // +2 top
    child: Text(
      text,
      style:
          Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize:
                (Theme.of(context).textTheme.titleSmall?.fontSize ?? 14) + 2,
          ) ??
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );

  Widget _chipRow<T>({
    required List<T> values,
    required T? selected,
    required String Function(T v) label,
    required void Function(T v) onSelected,
    Color? Function(T v)? selectedColor,
    EdgeInsetsGeometry? chipPadding,
    VisualDensity? visualDensity,
    TextStyle? labelStyle,
    MaterialTapTargetSize? tapTargetSize,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final isSelected = selected == v;
        final selColor = selectedColor?.call(v);

        return ChoiceChip(
          label: Text(label(v), style: labelStyle),
          selected: isSelected,
          selectedColor: selColor,
          padding: chipPadding,
          visualDensity: visualDensity,
          materialTapTargetSize: tapTargetSize,
          onSelected: (_) => onSelected(v),
        );
      }).toList(),
    );
  }

  Widget _distanceSlider({
    required String label,
    required int max,
    required int? value,
    required TextEditingController controller,
    required void Function(int? v) onChanged,
  }) {
    final v = value ?? 0;

    return Row(
      children: [
        Expanded(
          child: Slider(
            value: v.toDouble(),
            min: 0,
            max: max.toDouble(),
            divisions: max,
            label: v.toString(),
            onChanged: (d) {
              final next = d.round();
              setState(() {
                onChanged(next);
                controller.text = next.toString();
              });
              _scheduleAutoSave();
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.end,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(),
            ),
            onTap: () {
              final text = controller.text;
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: text.length,
              );
            },
            onSubmitted: (_) => _scheduleAutoSave(),
          ),
        ),
      ],
    );
  }

  Widget _verticalDistanceSlider({
    required int max,
    required int? value,
    required TextEditingController controller,
    required void Function(int? v) onChanged,
  }) {
    final v = value ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Vertical slider
        SizedBox(
          height: 160,
          child: RotatedBox(
            quarterTurns: -1, // make slider vertical
            child: Slider(
              value: v.toDouble(),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              label: v.toString(),
              onChanged: (d) {
                final next = d.round();
                setState(() {
                  onChanged(next);
                  controller.text = next.toString();
                });
                _scheduleAutoSave();
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 72,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(),
            ),
            onTap: () {
              final text = controller.text;
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: text.length,
              );
            },
            onSubmitted: (_) => _scheduleAutoSave(),
          ),
        ),
      ],
    );
  }

  Color? _firSelectedColor(String code) {
    switch (code) {
      case 'C':
        return Colors.green;
      case 'L':
      case 'R':
        return Colors.yellow;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastHole = _holeNumber == 18;

    final par = _par;
    final yds = _yardage;
    final si = _strokeIndex;
    final gir = _gir;
    final upDown = _upAndDown;

    final buttonsDisabled = _loading || _busy;
    final media = MediaQuery.of(context);
    final largeText = media.textScaler.scale(14) > 17;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hole $_holeNumber'),
            if (widget.editMode) ...[
              const SizedBox(width: 10),
              Chip(
                label: const Text('Editing'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.green.shade200,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Par: '),
                              TextSpan(
                                text: (par ?? '-').toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: par == null
                                      ? Colors.black87
                                      : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (yds != null)
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Yardage: '),
                                TextSpan(
                                  text: yds.toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.indigo.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (si != null)
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'SI: '),
                                TextSpan(
                                  text: si.toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          'GIR: ${gir == null ? '-' : (gir ? 'Yes' : 'No')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: gir == true
                                    ? Colors.green.shade700
                                    : Colors.black87,
                                fontWeight: gir == true
                                    ? FontWeight.w700
                                    : null,
                              ),
                        ),
                        Text(
                          'Up&Down: ${upDown == null ? '-' : (upDown ? 'Yes' : 'No')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: upDown == true
                                    ? Colors.green.shade700
                                    : Colors.black87,
                                fontWeight: upDown == true
                                    ? FontWeight.w700
                                    : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: _onSwipe,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) {
                  final currentKey = ValueKey(_holeNumber);
                  final isOutgoing = child.key != currentKey;

                  final curved = CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOut,
                  );

                  final begin = isOutgoing
                      ? Offset.zero
                      : Offset(_navDir.toDouble(), 0);

                  final end = isOutgoing
                      ? Offset(-_navDir.toDouble(), 0)
                      : Offset.zero;

                  final slideAnim = isOutgoing
                      ? ReverseAnimation(curved)
                      : curved;

                  final offset = Tween<Offset>(
                    begin: begin,
                    end: end,
                  ).animate(slideAnim);

                  return ClipRect(
                    child: FadeTransition(
                      opacity: curved,
                      child: SlideTransition(position: offset, child: child),
                    ),
                  );
                },
                child: ListView(
                  key: ValueKey(_holeNumber),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: _showResumeBanner
                          ? Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Resumed Round · Hole $_holeNumber',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontStyle: FontStyle.italic),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Primary quick-entry block: Score + Putts
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('Score', padding: EdgeInsets.zero),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(10, (i) => i + 1).map((
                                v,
                              ) {
                                final isSelected = _score == v;
                                final parLocal = _par;

                                Color? fillColor;
                                if (parLocal != null) {
                                  if (v == parLocal) {
                                    fillColor = Colors.lightGreen.shade200;
                                  } else if (v == parLocal + 1) {
                                    fillColor = Colors.yellow.shade200;
                                  } else if (v < parLocal) {
                                    fillColor = Colors.green.shade700;
                                  } else {
                                    fillColor = Colors.red.shade200;
                                  }
                                }

                                final isPar = parLocal != null && v == parLocal;

                                return ChoiceChip(
                                  label: Text(v.toString()),
                                  selected: isSelected,
                                  selectedColor: fillColor,
                                  side: BorderSide(
                                    color: isPar
                                        ? Colors.black38
                                        : Colors.black12,
                                    width: isPar ? 2 : 1,
                                  ),
                                  onSelected: (_) {
                                    setState(() => _score = v);
                                    _scheduleAutoSave();
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            _sectionTitle('Putts', padding: EdgeInsets.zero),
                            _chipRow<int>(
                              values: const [0, 1, 2, 3, 4],
                              selected: _putts,
                              label: (v) => v.toString(),
                              onSelected: (v) {
                                setState(() => _putts = v);
                                _scheduleAutoSave();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(
                              'Penalties',
                              padding: EdgeInsets.zero,
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 180,
                                  ),
                                  child: _chipRow<int>(
                                    values: const [0, 1, 2],
                                    selected: _penalties,
                                    label: (v) => v.toString(),
                                    onSelected: (v) {
                                      setState(() => _penalties = v);
                                      _scheduleAutoSave();
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Sand',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Checkbox(
                                      value: _greensideBunker ?? false,
                                      onChanged: (checked) {
                                        if (_loading || _busy) return;
                                        setState(
                                          () => _greensideBunker =
                                              checked ?? false,
                                        );
                                        _scheduleAutoSave();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('Tee Shot', padding: EdgeInsets.zero),
                            _chipRow<String>(
                              values: const ['L', 'C', 'R'],
                              selected: _fir,
                              label: (v) => v == 'L'
                                  ? 'Left'
                                  : v == 'C'
                                  ? 'Center'
                                  : 'Right',
                              selectedColor: _firSelectedColor,
                              onSelected: (v) {
                                setState(() => _fir = v);
                                _scheduleAutoSave();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: _sectionTitle(
                                'Approach',
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Location',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black87,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      ApproachLocationPicker(
                                        selected: _approachLocation,
                                        onChanged: (v) {
                                          setState(() => _approachLocation = v);
                                          _scheduleAutoSave();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Distance',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black87,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    _verticalDistanceSlider(
                                      max: 175,
                                      value: _approachDistance,
                                      controller: _approachDistanceCtrl,
                                      onChanged: (v) => _approachDistance = v,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(
                              'First Putt Distance',
                              padding: EdgeInsets.zero,
                            ),
                            _distanceSlider(
                              label: 'First Putt Distance',
                              max: 60,
                              value: _firstPuttDistance,
                              controller: _firstPuttDistanceCtrl,
                              onChanged: (v) => _firstPuttDistance = v,
                            ),
                          ],
                        ),
                      ),
                    ),

                    _sectionTitle('Notes'),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 1,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        hintText: 'Notes about this hole…',
                        hintStyle: const TextStyle(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Finish CTA on hole 18
                    if (isLastHole)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: buttonsDisabled ? null : _finishRound,
                            icon: const Icon(Icons.flag),
                            label: const Text('Finish Round'),
                          ),
                        ),
                      ),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (!buttonsDisabled && _holeNumber > 1)
                                ? _goBack
                                : null,
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: buttonsDisabled
                                ? null
                                : (isLastHole ? _finishRound : _goNext),
                            child: Text(isLastHole ? 'Round Summary' : 'Next'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tip: Swipe left/right to move holes (auto-saves).',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class ApproachLocationPicker extends StatelessWidget {
  final String? selected; // "L" | "C" | "R" | "LONG" | "SHORT"
  final ValueChanged<String> onChanged;

  const ApproachLocationPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  Color _bgFor(String code) {
    if (selected != code) return Colors.white;

    switch (code) {
      case 'C':
        return Colors.green;
      case 'L':
      case 'R':
        return Colors.yellow;
      case 'SHORT':
      case 'LONG':
        return Colors.cyan;
      default:
        return Colors.white;
    }
  }

  String _labelFor(String code) {
    switch (code) {
      case 'L':
        return 'Left';
      case 'R':
        return 'Right';
      case 'SHORT':
        return 'Short';
      case 'LONG':
        return 'Long';
      case 'C':
        return 'Center';
      default:
        return code;
    }
  }

  Widget _cell(String code, {BorderRadius? radius, double textRotation = 0}) {
    return Material(
      color: _bgFor(code),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(code);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: Colors.black12),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Transform.rotate(
                angle: textRotation,
                child: Text(
                  _labelFor(code),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Size tuned so labels fit without clutter.
    const double size = 180;
    const double centerSize = 74;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26, width: 1.5),
                ),
                child: ClipOval(
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _cell(
                                    'LONG',
                                    textRotation: -math.pi / 4,
                                  ),
                                ),
                                Expanded(
                                  child: _cell('R', textRotation: -math.pi / 4),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _cell('L', textRotation: -math.pi / 4),
                                ),
                                Expanded(
                                  child: _cell(
                                    'SHORT',
                                    textRotation: -math.pi / 4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: centerSize,
                height: centerSize,
                child: Material(
                  color: _bgFor('C'),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged('C');
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            _labelFor('C'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
