import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:maze_runner_windows/maze/maze_backend.dart';
import 'package:maze_runner_windows/state/maze_state.dart';

void main() {
  group('MazeEngineFromBackend', () {
    test('forwards generateMaze and astarPath to backend', () async {
      final mock = _MockBackend();
      final engine = MazeEngineFromBackend(mock);

      final cells = await engine.generateMaze(
        width: 5,
        height: 5,
        seed: 42,
      );
      expect(cells.length, 25);
      expect(mock.generateMazeCalled, isTrue);
      expect(mock.lastW, 5);
      expect(mock.lastH, 5);
      expect(mock.lastSeed, 42);

      final path = await engine.astarPath(
        cells: cells,
        width: 5,
        height: 5,
        sx: 0,
        sy: 0,
        tx: 4,
        ty: 4,
      );
      expect(path, isNotEmpty);
      expect(path.first.x, 0);
      expect(path.first.y, 0);
      expect(path.last.x, 4);
      expect(path.last.y, 4);
      expect(mock.astarPathCalled, isTrue);
    });
  });

  group('Deterministic 5x5 (real backend when on desktop)', () {
    test('generateMaze returns w*h cells; A* from (0,0) to (4,4) returns non-empty path', () async {
      final backend = createMazeBackend();
      const w = 5, h = 5, seed = 42;
      final cells = await backend.generateMaze(w: w, h: h, seed: seed);
      expect(cells.length, w * h, reason: 'cell count must match w*h');

      final path = await backend.solveAStar(
        cells: cells,
        w: w,
        h: h,
        sx: 0,
        sy: 0,
        tx: 4,
        ty: 4,
      );
      expect(path, isNotEmpty, reason: 'deterministic 5x5 seed 42 should have path');
      expect(path.first.x, 0);
      expect(path.first.y, 0);
      expect(path.last.x, 4);
      expect(path.last.y, 4);
    }, skip: 'Requires native backend (Windows + maze_lib.dll or server/wasm); run manually when available');
  });
}

class _MockBackend implements MazeBackend {
  bool generateMazeCalled = false;
  bool astarPathCalled = false;
  int lastW = 0, lastH = 0, lastSeed = 0;

  @override
  Future<Uint8List> generateMaze({
    required int w,
    required int h,
    required int seed,
  }) async {
    generateMazeCalled = true;
    lastW = w;
    lastH = h;
    lastSeed = seed;
    return Uint8List(w * h);
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
    astarPathCalled = true;
    return [CellPoint(sx, sy), CellPoint(tx, ty)];
  }
}
