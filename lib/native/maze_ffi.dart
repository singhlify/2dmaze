import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../state/maze_state.dart';

/// Thin Dart FFI wrapper around the native C++ maze DLL.
class MazeFfi {
  MazeFfi._() {
    _library = _openLibrary();
    _bindFunctions();
  }

  static final MazeFfi instance = MazeFfi._();

  late final ffi.DynamicLibrary _library;

  late final _GenerateMazeDart _generateMaze;
  late final _AStarPathDart _astarPath;

  static ffi.DynamicLibrary _openLibrary() {
    if (!Platform.isWindows) {
      // This PoC targets Windows only.
      throw UnsupportedError(
        'maze_lib.dll loading is only supported on Windows in this PoC.',
      );
    }

    try {
      final lib = ffi.DynamicLibrary.open('maze_lib.dll');
      // Basic debug log.
      // ignore: avoid_print
      print('[MazeFfi] Loaded maze_lib.dll successfully.');
      return lib;
    } on Object catch (e) {
      // ignore: avoid_print
      print('[MazeFfi] Failed to load maze_lib.dll: $e');
      rethrow;
    }
  }

  void _bindFunctions() {
    _generateMaze = _library
        .lookupFunction<_GenerateMazeNative, _GenerateMazeDart>('generate_maze');
    _astarPath = _library
        .lookupFunction<_AStarPathNative, _AStarPathDart>('astar_path');
  }

  /// Generate a maze grid using the native DLL.
  ///
  /// Returns a [Uint8List] of length width * height with wall bitflags.
  Future<Uint8List> generateMazeGrid({
    required int width,
    required int height,
    required int seed,
  }) async {
    final int cellCount = width * height;
    final ffi.Pointer<ffi.Uint8> buffer =
        pkg_ffi.calloc<ffi.Uint8>(cellCount);

    try {
      final int result =
          _generateMaze(width, height, seed, buffer, cellCount);
      if (result < 0) {
        throw Exception(
          'generate_maze failed with error code $result',
        );
      }

      final Uint8List view = buffer.asTypedList(cellCount);
      final Uint8List copy = Uint8List.fromList(view);

      // ignore: avoid_print
      print(
          '[MazeFfi] Maze generated: ${width}x$height, seed=$seed, cells=$cellCount');

      return copy;
    } finally {
      pkg_ffi.calloc.free(buffer);
    }
  }

  /// Compute A* path for the given maze and start/target.
  ///
  /// Returns a list of [CellPoint] from start to target (inclusive).
  Future<List<CellPoint>> computeAStarPath({
    required Uint8List cells,
    required int width,
    required int height,
    required CellPoint start,
    required CellPoint target,
  }) async {
    final int cellCount = width * height;
    if (cells.length < cellCount) {
      throw ArgumentError(
        'cells buffer too small: expected at least $cellCount, got ${cells.length}',
      );
    }

    final ffi.Pointer<ffi.Uint8> cellsPtr =
        pkg_ffi.calloc<ffi.Uint8>(cellCount);
    final ffi.Pointer<ffi.Int32> pathPtr = pkg_ffi.calloc<ffi.Int32>(
      cellCount * 2,
    ); // worst case: visit all cells.

    try {
      // Copy maze data into native buffer.
      final Uint8List cellsView = cellsPtr.asTypedList(cellCount);
      cellsView.setAll(0, cells);

      final int result = _astarPath(
        cellsPtr,
        width,
        height,
        start.x,
        start.y,
        target.x,
        target.y,
        pathPtr,
        cellCount * 2,
      );

      if (result < 0) {
        throw Exception('astar_path failed with error code $result');
      }

      final int pathLen = result;
      final List<CellPoint> path = <CellPoint>[];
      final ints = pathPtr.asTypedList(pathLen * 2);
      for (int i = 0; i < pathLen; i++) {
        final int x = ints[2 * i];
        final int y = ints[2 * i + 1];
        path.add(CellPoint(x, y));
      }

      // ignore: avoid_print
      print('[MazeFfi] A* path length=$pathLen '
          'from (${start.x},${start.y}) to (${target.x},${target.y})');

      return path;
    } finally {
      pkg_ffi.calloc
        ..free(cellsPtr)
        ..free(pathPtr);
    }
  }
}

// Native function signatures.
typedef _GenerateMazeNative = ffi.Int32 Function(
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 seed,
  ffi.Pointer<ffi.Uint8> outCells,
  ffi.Int32 outCellsLen,
);

typedef _GenerateMazeDart = int Function(
  int width,
  int height,
  int seed,
  ffi.Pointer<ffi.Uint8> outCells,
  int outCellsLen,
);

typedef _AStarPathNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> cells,
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 sx,
  ffi.Int32 sy,
  ffi.Int32 tx,
  ffi.Int32 ty,
  ffi.Pointer<ffi.Int32> outPathXY,
  ffi.Int32 outPathXYLen,
);

typedef _AStarPathDart = int Function(
  ffi.Pointer<ffi.Uint8> cells,
  int width,
  int height,
  int sx,
  int sy,
  int tx,
  int ty,
  ffi.Pointer<ffi.Int32> outPathXY,
  int outPathXYLen,
);

