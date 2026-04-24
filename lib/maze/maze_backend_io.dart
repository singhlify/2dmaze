import 'dart:typed_data';

import '../native/maze_ffi.dart';
import '../state/maze_state.dart';
import 'maze_backend.dart';

/// Desktop (Windows / Linux / macOS) backend: uses the native maze
/// shared library via `dart:ffi`.
MazeBackend createMazeBackend() {
  // Print GPU adapter info once at startup so the terminal log contains
  // enough evidence to answer Q4 (which GPU Flutter renders on) without
  // needing to poke Task Manager. One-shot, cheap.
  MazeFfi.instance.logGpuInfo();
  return DesktopFfiBackend();
}

/// [MazeBackend] implementation that delegates to [MazeFfi] (native
/// shared library loaded via `dart:ffi`).
class DesktopFfiBackend implements MazeBackend {
  @override
  Future<Uint8List> generateMaze({
    required int w,
    required int h,
    required int seed,
  }) =>
      MazeFfi.instance.generateMazeGrid(
        width: w,
        height: h,
        seed: seed,
      );

  @override
  Future<List<CellPoint>> solveAStar({
    required Uint8List cells,
    required int w,
    required int h,
    required int sx,
    required int sy,
    required int tx,
    required int ty,
  }) =>
      MazeFfi.instance.computeAStarPath(
        cells: cells,
        width: w,
        height: h,
        start: CellPoint(sx, sy),
        target: CellPoint(tx, ty),
      );
}
