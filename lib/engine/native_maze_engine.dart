import 'dart:typed_data';

import '../native/maze_ffi.dart';
import '../state/maze_state.dart';
import 'maze_engine.dart';

/// Maze engine that uses the native DLL via dart:ffi (Windows desktop only).
class NativeMazeEngine implements MazeEngine {
  @override
  Future<Uint8List> generateMaze({
    required int width,
    required int height,
    required int seed,
  }) =>
      MazeFfi.instance.generateMazeGrid(
        width: width,
        height: height,
        seed: seed,
      );

  @override
  Future<List<CellPoint>> astarPath({
    required Uint8List cells,
    required int width,
    required int height,
    required int sx,
    required int sy,
    required int tx,
    required int ty,
  }) =>
      MazeFfi.instance.computeAStarPath(
        cells: cells,
        width: width,
        height: height,
        start: CellPoint(sx, sy),
        target: CellPoint(tx, ty),
      );
}
