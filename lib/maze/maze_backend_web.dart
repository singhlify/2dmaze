import 'dart:typed_data';

import '../engine/server_maze_engine.dart';
import '../state/maze_state.dart';
import 'maze_backend.dart';
import 'web_wasm/maze_wasm_interop.dart';

MazeBackend createMazeBackend() {
  const mode = String.fromEnvironment('MAZE_MODE', defaultValue: 'server');
  if (mode == 'server') {
    return WebServerBackend();
  }
  if (mode == 'wasm') {
    // ignore: avoid_print
    print('[MazeBackend] MAZE_MODE=wasm => WebWasmBackend');
    return WebWasmBackend();
  }
  throw UnsupportedError(
    'On web, set --dart-define=MAZE_MODE=server or --dart-define=MAZE_MODE=wasm.',
  );
}

/// Web backend that calls the C++ HTTP server (Phase 1).
class WebServerBackend implements MazeBackend {
  WebServerBackend({String? baseUrl}) : _engine = ServerMazeEngine(baseUrl: baseUrl);

  final ServerMazeEngine _engine;

  @override
  Future<Uint8List> generateMaze({
    required int w,
    required int h,
    required int seed,
  }) =>
      _engine.generateMaze(width: w, height: h, seed: seed);

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
      _engine.astarPath(
        cells: cells,
        width: w,
        height: h,
        sx: sx,
        sy: sy,
        tx: tx,
        ty: ty,
      );
}

/// Web backend that runs C++ maze + A* in the browser via WebAssembly.
class WebWasmBackend implements MazeBackend {
  @override
  Future<Uint8List> generateMaze({
    required int w,
    required int h,
    required int seed,
  }) async {
    final cells = await MazeWasmInterop.instance.generateMaze(w, h, seed);
    assert(cells.length == w * h, 'WASM generateMaze: cell count ${cells.length} != ${w * h}');
    return cells;
  }

  @override
  Future<List<CellPoint>> solveAStar({
    required Uint8List cells,
    required int w,
    required int h,
    required int sx,
    required int sy,
    required int tx,
    required int ty,
  }) async {
    final path = await MazeWasmInterop.instance.astarPath(
      cells,
      w,
      h,
      sx,
      sy,
      tx,
      ty,
    );
    if (path.isNotEmpty) {
      assert(path.first.x == sx && path.first.y == sy);
      assert(path.last.x == tx && path.last.y == ty);
    }
    return path;
  }
}
