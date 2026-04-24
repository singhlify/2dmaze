import 'dart:typed_data';

import 'maze_backend_io.dart' if (dart.library.html) 'maze_backend_web.dart' as impl;

import '../engine/maze_engine.dart';
import '../state/maze_state.dart';

/// Backend abstraction for maze generation and A* pathfinding.
/// Implemented by [DesktopFfiBackend], [WebServerBackend], or [WebWasmBackend].
abstract class MazeBackend {
  Future<Uint8List> generateMaze({
    required int w,
    required int h,
    required int seed,
  });

  Future<List<CellPoint>> solveAStar({
    required Uint8List cells,
    required int w,
    required int h,
    required int sx,
    required int sy,
    required int tx,
    required int ty,
  });
}

/// Creates the appropriate [MazeBackend] for the current platform and build config.
/// Desktop: always [DesktopFfiBackend]. Web: [WebServerBackend] or [WebWasmBackend] via MAZE_MODE.
MazeBackend createMazeBackend() => impl.createMazeBackend();

/// Adapts a [MazeBackend] to the [MazeEngine] interface so existing UI stays unchanged.
class MazeEngineFromBackend implements MazeEngine {
  MazeEngineFromBackend(this._backend);

  final MazeBackend _backend;

  @override
  Future<Uint8List> generateMaze({
    required int width,
    required int height,
    required int seed,
  }) =>
      _backend.generateMaze(w: width, h: height, seed: seed);

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
      _backend.solveAStar(
        cells: cells,
        w: width,
        h: height,
        sx: sx,
        sy: sy,
        tx: tx,
        ty: ty,
      );
}
