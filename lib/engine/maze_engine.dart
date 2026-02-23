import 'dart:typed_data';

import '../state/maze_state.dart';

/// Abstraction for maze generation and A* pathfinding.
/// Implemented by [NativeMazeEngine] (desktop/FFI) or [ServerMazeEngine] (web/HTTP).
abstract class MazeEngine {
  Future<Uint8List> generateMaze({
    required int width,
    required int height,
    required int seed,
  });

  Future<List<CellPoint>> astarPath({
    required Uint8List cells,
    required int width,
    required int height,
    required int sx,
    required int sy,
    required int tx,
    required int ty,
  });
}
