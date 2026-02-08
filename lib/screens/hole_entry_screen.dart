import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/database_provider.dart';
import 'round_summary_screen.dart';

class HoleEntryScreen extends ConsumerStatefulWidget {
  final int roundId;

  /// Optional: open the screen on a specific hole (1-18).
  final int initialHole;

  const HoleEntryScreen({
    super.key,
    required this.roundId,
    this.initialHole = 1,
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

  bool _loading = true;
  bool _busy = false;

  bool _showSavedIndicator = false;
  Timer? _savedTimer;

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
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _scrollController.dispose();
    _savedTimer?.cancel();
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
        _firstPuttDistance != null;
  }

  void _showSaved() {
    if (!mounted) return;
    setState(() => _showSavedIndicator = true);

    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _showSavedIndicator = false);
      }
    });
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
      );

      _showSaved();

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
      return false;
    } finally {
      _busy = false;
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

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  Widget _chipRow<T>({
    required List<T> values,
    required T? selected,
    required String Function(T v) label,
    required void Function(T v) onSelected,
    Color? Function(T v)? selectedColor,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final isSelected = selected == v;
        final selColor = selectedColor?.call(v);

        return ChoiceChip(
          label: Text(label(v)),
          selected: isSelected,
          selectedColor: selColor,
          onSelected: (_) => onSelected(v),
        );
      }).toList(),
    );
  }

  Widget _distanceSlider({
    required String label,
    required int max,
    required int? value,
    required void Function(int v) onChanged,
  }) {
    final v = value ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $v'),
        Slider(
          value: v.toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: max,
          label: v.toString(),
          onChanged: (d) => setState(() {
            onChanged(d.round());
            _scheduleAutoSave();
          }),
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

  Color? _approachSelectedColor(String code) {
    switch (code) {
      case 'C':
        return Colors.green;
      case 'L':
      case 'R':
        return Colors.yellow;
      case 'LONG':
      case 'SHORT':
        return Colors.cyan;
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Hole $_holeNumber'),
      ),
      body: Focus(
        autofocus: true,
        child: Shortcuts(
          shortcuts: <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _GoBackIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowRight): const _GoNextIntent(),
            LogicalKeySet(LogicalKeyboardKey.enter): const _GoNextIntent(),
            LogicalKeySet(LogicalKeyboardKey.keyP): const _CyclePuttsIntent(),
            LogicalKeySet(LogicalKeyboardKey.digit1): const _SetScoreIntent(1),
            LogicalKeySet(LogicalKeyboardKey.digit2): const _SetScoreIntent(2),
            LogicalKeySet(LogicalKeyboardKey.digit3): const _SetScoreIntent(3),
            LogicalKeySet(LogicalKeyboardKey.digit4): const _SetScoreIntent(4),
            LogicalKeySet(LogicalKeyboardKey.digit5): const _SetScoreIntent(5),
            LogicalKeySet(LogicalKeyboardKey.digit6): const _SetScoreIntent(6),
            LogicalKeySet(LogicalKeyboardKey.digit7): const _SetScoreIntent(7),
            LogicalKeySet(LogicalKeyboardKey.digit8): const _SetScoreIntent(8),
            LogicalKeySet(LogicalKeyboardKey.digit9): const _SetScoreIntent(9),
            LogicalKeySet(LogicalKeyboardKey.digit0): const _SetScoreIntent(10),
            LogicalKeySet(LogicalKeyboardKey.numpad1): const _SetScoreIntent(1),
            LogicalKeySet(LogicalKeyboardKey.numpad2): const _SetScoreIntent(2),
            LogicalKeySet(LogicalKeyboardKey.numpad3): const _SetScoreIntent(3),
            LogicalKeySet(LogicalKeyboardKey.numpad4): const _SetScoreIntent(4),
            LogicalKeySet(LogicalKeyboardKey.numpad5): const _SetScoreIntent(5),
            LogicalKeySet(LogicalKeyboardKey.numpad6): const _SetScoreIntent(6),
            LogicalKeySet(LogicalKeyboardKey.numpad7): const _SetScoreIntent(7),
            LogicalKeySet(LogicalKeyboardKey.numpad8): const _SetScoreIntent(8),
            LogicalKeySet(LogicalKeyboardKey.numpad9): const _SetScoreIntent(9),
            LogicalKeySet(LogicalKeyboardKey.numpad0):
                const _SetScoreIntent(10),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _GoBackIntent: CallbackAction<_GoBackIntent>(
                onInvoke: (_) {
                  if (!_loading && !_busy) {
                    _goBack();
                  }
                  return null;
                },
              ),
              _GoNextIntent: CallbackAction<_GoNextIntent>(
                onInvoke: (_) {
                  if (!_loading && !_busy) {
                    _goNext();
                  }
                  return null;
                },
              ),
              _CyclePuttsIntent: CallbackAction<_CyclePuttsIntent>(
                onInvoke: (_) {
                  if (_loading || _busy) return null;
                  setState(() {
                    final current = _putts ?? 0;
                    _putts = (current + 1) % 5;
                  });
                  _scheduleAutoSave();
                  return null;
                },
              ),
              _SetScoreIntent: CallbackAction<_SetScoreIntent>(
                onInvoke: (intent) {
                  if (_loading || _busy) return null;
                  setState(() => _score = intent.score);
                  _scheduleAutoSave();
                  return null;
                },
              ),
            },
            child: GestureDetector(
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
                            parent: anim, curve: Curves.easeOut);

                        final begin = isOutgoing
                            ? Offset.zero
                            : Offset(_navDir.toDouble(), 0);

                        final end = isOutgoing
                            ? Offset(-_navDir.toDouble(), 0)
                            : Offset.zero;

                        final slideAnim =
                            isOutgoing ? ReverseAnimation(curved) : curved;

                        final offset = Tween<Offset>(begin: begin, end: end)
                            .animate(slideAnim);

                        return ClipRect(
                          child: FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
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
                                        vertical: 8, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Resumed Round · Hole $_holeNumber',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              fontStyle: FontStyle.italic),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          // Hole context row
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Par: ${par ?? '-'}'
                                      '${yds == null ? '' : '   Yardage: $yds'}'
                                      '${si == null ? '' : '   SI: $si'}',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'GIR: ${gir == null ? '-' : (gir ? 'Yes' : 'No')}',
                                      ),
                                      Text(
                                        'Up&Down: ${upDown == null ? '-' : (upDown ? 'Yes' : 'No')}',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          AnimatedOpacity(
                            opacity: _showSavedIndicator ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Saved ✓',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          _sectionTitle('Score'),
                          _chipRow<int>(
                            values: List.generate(10, (i) => i + 1),
                            selected: _score,
                            label: (v) => v.toString(),
                            onSelected: (v) {
                              setState(() => _score = v);
                              _scheduleAutoSave();
                            },
                          ),

                          _sectionTitle('Putts'),
                          _chipRow<int>(
                            values: const [0, 1, 2, 3, 4],
                            selected: _putts,
                            label: (v) => v.toString(),
                            onSelected: (v) {
                              setState(() => _putts = v);
                              _scheduleAutoSave();
                            },
                          ),

                          _sectionTitle('Penalties'),
                          _chipRow<int>(
                            values: const [0, 1, 2],
                            selected: _penalties,
                            label: (v) => v.toString(),
                            onSelected: (v) {
                              setState(() => _penalties = v);
                              _scheduleAutoSave();
                            },
                          ),

                          _sectionTitle('FIR'),
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

                          _sectionTitle('Approach Location'),
                          _chipRow<String>(
                            values: const ['L', 'C', 'R', 'LONG', 'SHORT'],
                            selected: _approachLocation,
                            label: (v) {
                              switch (v) {
                                case 'L':
                                  return 'Left';
                                case 'C':
                                  return 'Center';
                                case 'R':
                                  return 'Right';
                                case 'LONG':
                                  return 'Long';
                                case 'SHORT':
                                  return 'Short';
                                default:
                                  return v;
                              }
                            },
                            selectedColor: _approachSelectedColor,
                            onSelected: (v) {
                              setState(() => _approachLocation = v);
                              _scheduleAutoSave();
                            },
                          ),

                          _sectionTitle('Approach Distance'),
                          _distanceSlider(
                            label: 'Approach (max 175)',
                            max: 175,
                            value: _approachDistance,
                            onChanged: (v) => _approachDistance = v,
                          ),

                          _sectionTitle('First Putt Distance'),
                          _distanceSlider(
                            label: 'First putt (max 60)',
                            max: 60,
                            value: _firstPuttDistance,
                            onChanged: (v) => _firstPuttDistance = v,
                          ),

                          const SizedBox(height: 24),

                          // Finish CTA on hole 18
                          if (isLastHole)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      buttonsDisabled ? null : _finishRound,
                                  icon: const Icon(Icons.flag),
                                  label: const Text('Finish Round'),
                                ),
                              ),
                            ),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      (!buttonsDisabled && _holeNumber > 1)
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
                                  child: Text(
                                      isLastHole ? 'Round Summary' : 'Next'),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          Text(
                            'Tip: Swipe left/right to move holes (auto-saves).',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Private intent classes for keyboard shortcuts ----
class _GoBackIntent extends Intent {
  const _GoBackIntent();
}

class _GoNextIntent extends Intent {
  const _GoNextIntent();
}

class _CyclePuttsIntent extends Intent {
  const _CyclePuttsIntent();
}

class _SetScoreIntent extends Intent {
  final int score;
  const _SetScoreIntent(this.score);
}
