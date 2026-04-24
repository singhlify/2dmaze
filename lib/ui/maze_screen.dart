import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../engine/maze_engine.dart';
import '../logging/logger.dart' show logLine;
import '../state/maze_state.dart';
import 'maze3d_view.dart';
import 'maze_painter.dart';

/// Main screen hosting the maze canvas, controls, and stats.
class MazeScreen extends StatefulWidget {
  const MazeScreen({super.key, required this.engine});

  final MazeEngine engine;

  @override
  State<MazeScreen> createState() => _MazeScreenState();
}

class _MazeScreenState extends State<MazeScreen>
    with SingleTickerProviderStateMixin {
  final MazeState _mazeState = MazeState();
  final FocusNode _focusNode = FocusNode();

  late final Ticker _fpsTicker;
  int _frameCount = 0;
  Duration _lastFpsSampleTime = Duration.zero;

  // UI controls
  final TextEditingController _seedController =
      TextEditingController(text: '1');

  int _selectedSize = 20;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();

    // Logger is already initialised in main(); initLogger is
    // idempotent so we don't re-open the sink here.

    // One-shot log line that tags every subsequent [FPS] / [EVENT] line
    // in this process with enough context to interpret it (backend,
    // platform, build mode).
    const mazeMode =
        String.fromEnvironment('MAZE_MODE', defaultValue: '');
    const backend = mazeMode == 'server'
        ? 'Server'
        : mazeMode == 'wasm'
            ? 'WASM'
            : 'FFI';
    const buildMode = kReleaseMode ? 'release' : 'debug';
    logLine('[MODE] backend=$backend '
        'platform=${defaultTargetPlatform.name} '
        'build=$buildMode');

    _fpsTicker = createTicker(_onTick)..start();
    _lastFpsSampleTime = Duration.zero;

    // Initial dummy maze so UI is not empty for the first paint.
    _mazeState.setMaze(
      width: _selectedSize,
      height: _selectedSize,
      seed: 1,
      cells: Uint8List(_selectedSize * _selectedSize),
    );

    // Kick off a real maze from C++ on the first frame, then solve it
    // so the user sees walls AND a visible path immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _onNewMaze();
    });

    // Watch for the player reaching the target.
    _mazeState.addListener(_checkForWin);
  }

  bool _winDialogOpen = false;

  void _checkForWin() {
    if (_winDialogOpen) return;
    if (_mazeState.cells.isEmpty) return;
    if (_mazeState.playerX != _mazeState.targetX ||
        _mazeState.playerY != _mazeState.targetY) {
      return;
    }
    _winDialogOpen = true;
    _logEvent('win');
    // Defer to the next frame so we don't showDialog inside a notifyListeners().
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _winDialogOpen = false;
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('You reached the goal! 🎉'),
          content: Text(
            'Maze: ${_mazeState.width} × ${_mazeState.height} '
            '(seed ${_mazeState.seed})',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _mazeState
                  ..resetPlayer()
                  ..clearPath();
              },
              child: const Text('Play again (same maze)'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _onNewMaze();
              },
              child: const Text('New Maze'),
            ),
          ],
        ),
      );
      _winDialogOpen = false;
    });
  }

  void _onTick(Duration elapsed) {
    _frameCount++;
    if (_lastFpsSampleTime == Duration.zero) {
      _lastFpsSampleTime = elapsed;
      return;
    }
    final dt = elapsed - _lastFpsSampleTime;
    if (dt.inMilliseconds >= 1000) {
      final fps = _frameCount * 1000 / dt.inMilliseconds;
      _mazeState.updateFps(fps);
      _frameCount = 0;
      _lastFpsSampleTime = elapsed;
      _logFps(fps);
    }
  }

  // Terminal FPS log line — emitted once per second while the app runs,
  // so the terminal transcript alone is enough Q8 evidence (no screen
  // recording / manual table needed). Tag = [FPS], keys = view, size,
  // pathVisible, pathLen, fps.
  void _logFps(double fps) {
    final view = _mazeState.viewMode == ViewMode.view3D ? '3D' : '2D';
    logLine('[FPS] view=$view '
        'size=${_mazeState.width}x${_mazeState.height} '
        'pathVisible=${_mazeState.showPath} '
        'pathLen=${_mazeState.pathLength} '
        'fps=${fps.toStringAsFixed(1)}');
  }

  // Semantic event log — one line per user-visible state change that
  // matters for evidence. Lets you slice the FPS log by event (e.g.
  // "FPS after Solve on 100×100 in 3D").
  void _logEvent(String event, [Map<String, Object?>? fields]) {
    final view = _mazeState.viewMode == ViewMode.view3D ? '3D' : '2D';
    final parts = <String>[
      'event=$event',
      'view=$view',
      'size=${_mazeState.width}x${_mazeState.height}',
      if (fields != null)
        for (final e in fields.entries) '${e.key}=${e.value}',
    ];
    logLine('[EVENT] ${parts.join(' ')}');
  }

  @override
  void dispose() {
    _mazeState.removeListener(_checkForWin);
    _fpsTicker.dispose();
    _mazeState.dispose();
    _focusNode.dispose();
    _seedController.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (_mazeState.viewMode == ViewMode.view3D) {
      // Standard FPS-style tile controls:
      //   W / ArrowUp    - step forward
      //   S / ArrowDown  - step back
      //   A              - strafe left
      //   D              - strafe right
      //   Q / ArrowLeft  - rotate left 90°
      //   E / ArrowRight - rotate right 90°
      if (key == LogicalKeyboardKey.keyW ||
          key == LogicalKeyboardKey.arrowUp) {
        _mazeState.stepForward();
      } else if (key == LogicalKeyboardKey.keyS ||
          key == LogicalKeyboardKey.arrowDown) {
        _mazeState.stepBackward();
      } else if (key == LogicalKeyboardKey.keyA) {
        _mazeState.strafeLeft();
      } else if (key == LogicalKeyboardKey.keyD) {
        _mazeState.strafeRight();
      } else if (key == LogicalKeyboardKey.keyQ ||
          key == LogicalKeyboardKey.arrowLeft) {
        _mazeState.turnLeft();
      } else if (key == LogicalKeyboardKey.keyE ||
          key == LogicalKeyboardKey.arrowRight) {
        _mazeState.turnRight();
      }
      return;
    }

    // 2D mode: arrow/WASD move player exactly one cell per key press.
    int dx = 0;
    int dy = 0;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      dy = -1;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      dy = 1;
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      dx = -1;
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      dx = 1;
    } else {
      return;
    }
    _mazeState.movePlayer(dx, dy);
  }

  int _parseSeed() {
    final text = _seedController.text.trim();
    if (text.isEmpty) {
      return Random().nextInt(1 << 31);
    }
    final value = int.tryParse(text);
    if (value == null) {
      return Random().nextInt(1 << 31);
    }
    return value;
  }

  Future<void> _onNewMaze() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final seed = _parseSeed();
      final width = _selectedSize;
      final height = _selectedSize;

      final cells = await widget.engine.generateMaze(
        width: width,
        height: height,
        seed: seed,
      );

      stopwatch.stop();
      _mazeState
        ..setMaze(width: width, height: height, seed: seed, cells: cells)
        ..setLastMazeGenMs(stopwatch.elapsedMicroseconds / 1000.0)
        ..clearPath();
      _logEvent('new_maze', {
        'seed': seed,
        'genMs': stopwatch.elapsedMicroseconds / 1000.0,
      });
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate maze: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      } else {
        _isBusy = false;
      }
    }
  }

  Future<void> _onSolve() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
    });
    try {
      await _resolvePathFromPlayer();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      } else {
        _isBusy = false;
      }
    }
  }

  /// Core A* call — no UI gating. Used by the Solve button (wrapped in
  /// `_onSolve`), by `_onNewMaze` after a fresh maze lands, and after
  /// every player move so the trail tracks the player automatically.
  bool _resolving = false;
  bool _resolveAgainWhenDone = false;
  Future<void> _resolvePathFromPlayer() async {
    if (_mazeState.cells.isEmpty) return;
    if (_resolving) {
      // A solve is already in flight; request one more pass after it
      // finishes so we don't miss the player's latest position.
      _resolveAgainWhenDone = true;
      return;
    }
    _resolving = true;
    try {
      do {
        _resolveAgainWhenDone = false;
        final stopwatch = Stopwatch()..start();
        try {
          final path = await widget.engine.astarPath(
            cells: _mazeState.cells,
            width: _mazeState.width,
            height: _mazeState.height,
            sx: _mazeState.playerX,
            sy: _mazeState.playerY,
            tx: _mazeState.targetX,
            ty: _mazeState.targetY,
          );
          stopwatch.stop();
          _mazeState
            ..setPath(path)
            ..setLastSolveMs(stopwatch.elapsedMicroseconds / 1000.0);
          _logEvent('solve', {
            'pathLen': path.length,
            'solveMs': stopwatch.elapsedMicroseconds / 1000.0,
          });
        } catch (e) {
          stopwatch.stop();
          _mazeState.clearPath();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to solve path: $e')),
            );
          }
        }
      } while (_resolveAgainWhenDone && mounted);
    } finally {
      _resolving = false;
    }
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Maze Controls',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text('View'),
        const SizedBox(height: 4),
        AnimatedBuilder(
          animation: _mazeState,
          builder: (context, _) {
            return SegmentedButton<ViewMode>(
              segments: const [
                ButtonSegment(
                  value: ViewMode.view2D,
                  label: Text('2D'),
                ),
                ButtonSegment(
                  value: ViewMode.view3D,
                  label: Text('3D'),
                ),
              ],
              selected: {_mazeState.viewMode},
              onSelectionChanged: (modes) {
                setState(() {
                  _mazeState.viewMode = modes.first;
                });
                _logEvent('view_toggle');
              },
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _seedController,
          decoration: const InputDecoration(
            labelText: 'Seed',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        const Text('Size'),
        Wrap(
          spacing: 8,
          children: [20, 50, 100].map((size) {
            final selected = _selectedSize == size;
            return ChoiceChip(
              label: Text('${size}x$size'),
              selected: selected,
              onSelected: (value) {
                if (!value) return;
                setState(() {
                  _selectedSize = size;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _isBusy ? null : _onNewMaze,
              child: const Text('New Maze'),
            ),
            ElevatedButton(
              onPressed: () {
                _mazeState.togglePathVisibility();
                _logEvent('toggle_path',
                    {'pathVisible': _mazeState.showPath});
              },
              child: const Text('Toggle Path'),
            ),
            ElevatedButton(
              onPressed: () {
                _mazeState
                  ..resetPlayer()
                  ..clearPath();
                _logEvent('reset_player');
              },
              child: const Text('Reset Player'),
            ),
            ElevatedButton(
              onPressed: _isBusy ? null : _onSolve,
              child: const Text('Solve'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Stats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        AnimatedBuilder(
          animation: _mazeState,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Maze: ${_mazeState.width} x ${_mazeState.height} (seed ${_mazeState.seed})'),
                Text('Path length: ${_mazeState.pathLength}'),
                Text('FPS: ${_mazeState.fps.toStringAsFixed(1)}'),
                Text('View: ${_mazeState.viewMode == ViewMode.view2D ? '2D' : '3D'}'),
                Text(
                    'Last maze gen: ${_mazeState.lastMazeGenMs.toStringAsFixed(2)} ms'),
                Text(
                    'Last A* solve: ${_mazeState.lastSolveMs.toStringAsFixed(2)} ms'),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maze Runner PoC'),
      ),
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      // Keep BOTH views alive in an IndexedStack and swap
                      // which one is visible. Rebuilding Maze3DView on every
                      // toggle tears down the three_js engine, which
                      // doesn't reliably re-init cleanly. TickerMode pauses
                      // the inactive view so it doesn't waste GPU.
                      child: AnimatedBuilder(
                        animation: _mazeState,
                        builder: (context, _) {
                          final is3D = _mazeState.viewMode == ViewMode.view3D;
                          return IndexedStack(
                            index: is3D ? 1 : 0,
                            sizing: StackFit.expand,
                            children: [
                              TickerMode(
                                enabled: !is3D,
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: MazePainter(_mazeState),
                                  ),
                                ),
                              ),
                              TickerMode(
                                enabled: is3D,
                                child: Maze3DView(state: _mazeState),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: min(320, constraints.maxWidth * 0.35),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildControls(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

