import 'package:flutter/material.dart';

import '../state/maze_state.dart';

class Maze3DHud extends StatelessWidget {
  const Maze3DHud({
    super.key,
    required this.state,
    required this.wallCount,
  });

  final MazeState state;
  final int wallCount;

  String get _backendMode {
    // Best-effort: reflect backend mode from environment on web.
    const backend =
        String.fromEnvironment('MAZE_MODE', defaultValue: 'ffi-or-server');
    if (backend == 'server') return 'Server';
    if (backend == 'wasm') return 'WASM';
    return 'FFI';
  }

  String get _facingLabel {
    switch (state.facing) {
      case Facing.north: return 'N';
      case Facing.east:  return 'E';
      case Facing.south: return 'S';
      case Facing.west:  return 'W';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top-left: debug stats.
        Positioned(
          left: 12,
          top: 12,
          child: AnimatedBuilder(
            animation: state,
            builder: (context, _) {
              return _panel(
                children: [
                  const Text(
                    '3D Debug HUD',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text('Visual: 3D'),
                  Text('Backend: $_backendMode'),
                  Text('Maze: ${state.width} x ${state.height}'),
                  Text('Player: (${state.playerX}, ${state.playerY}) facing $_facingLabel'),
                  Text('Path length: ${state.pathLength}'),
                  Text('Path visible: ${state.showPath}'),
                  Text('Walls: $wallCount'),
                  Text('FPS: ${state.fps.toStringAsFixed(1)}'),
                ],
              );
            },
          ),
        ),
        // Bottom-left: controls reference.
        Positioned(
          left: 12,
          bottom: 12,
          child: _panel(
            children: const [
              Text(
                'Controls',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('W / ↑    step forward'),
              Text('S / ↓    step back'),
              Text('A / D    strafe left / right'),
              Text('Q / ←    rotate left 90°'),
              Text('E / →    rotate right 90°'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panel({required List<Widget> children}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}
