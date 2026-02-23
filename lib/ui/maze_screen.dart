import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../engine/maze_engine.dart';
import '../state/maze_state.dart';
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

    _fpsTicker = createTicker(_onTick)..start();
    _lastFpsSampleTime = Duration.zero;

    // Initial dummy maze so UI is not empty; real maze will come from DLL.
    _mazeState.setMaze(
      width: _selectedSize,
      height: _selectedSize,
      seed: 1,
      cells: Uint8List(_selectedSize * _selectedSize),
    );
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
    }
  }

  @override
  void dispose() {
    _fpsTicker.dispose();
    _mazeState.dispose();
    _focusNode.dispose();
    _seedController.dispose();
    super.dispose();
  }

  void _handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    final key = event.logicalKey;
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
    if (_mazeState.cells.isEmpty) return;

    setState(() {
      _isBusy = true;
    });
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
    } catch (e) {
      stopwatch.stop();
      _mazeState.clearPath();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to solve path: $e')),
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

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Maze Controls',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              onPressed: _mazeState.togglePathVisibility,
              child: const Text('Toggle Path'),
            ),
            ElevatedButton(
              onPressed: _mazeState.resetPlayer,
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
      body: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKey: _handleKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: AnimatedBuilder(
                        animation: _mazeState,
                        builder: (context, _) {
                          return RepaintBoundary(
                            child: CustomPaint(
                              painter: MazePainter(_mazeState),
                            ),
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

