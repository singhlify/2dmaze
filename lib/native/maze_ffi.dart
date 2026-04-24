import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../logging/logger.dart';
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
  late final _QueryGpuInfoDart _queryGpuInfo;

  static ffi.DynamicLibrary _openLibrary() {
    final candidates = _libraryCandidates();

    Object? lastError;
    for (final path in candidates) {
      try {
        final lib = ffi.DynamicLibrary.open(path);
        // ignore: avoid_print
        print('[MazeFfi] Loaded native maze library from "$path".');
        return lib;
      } on Object catch (e) {
        lastError = e;
      }
    }

    // ignore: avoid_print
    print('[MazeFfi] Failed to load native maze library. '
        'Tried: ${candidates.join(", ")}. Last error: $lastError');
    throw UnsupportedError(
      'Could not load native maze library on ${Platform.operatingSystem}. '
      'Tried: ${candidates.join(", ")}',
    );
  }

  /// Ordered list of paths to try when loading the native library.
  ///
  /// On desktop Flutter the library ends up next to the runner executable
  /// (via CMake install rules), so we try there first, then fall back to the
  /// plain filename which lets the OS loader search its usual paths.
  static List<String> _libraryCandidates() {
    final String fileName;
    if (Platform.isWindows) {
      fileName = 'maze_lib.dll';
    } else if (Platform.isMacOS) {
      fileName = 'libmaze_lib.dylib';
    } else if (Platform.isLinux) {
      fileName = 'libmaze_lib.so';
    } else {
      throw UnsupportedError(
        'Unsupported platform for maze_lib: ${Platform.operatingSystem}',
      );
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;

    // On Linux Flutter desktop, bundled libs live under <bundle>/lib/
    // with RPATH $ORIGIN/lib on the executable. On Windows, DLLs sit
    // next to the exe. macOS follows Linux-like convention for this PoC.
    return <String>[
      '$exeDir${sep}lib$sep$fileName',
      '$exeDir$sep$fileName',
      fileName,
    ];
  }

  void _bindFunctions() {
    _generateMaze = _library
        .lookupFunction<_GenerateMazeNative, _GenerateMazeDart>('generate_maze');
    _astarPath = _library
        .lookupFunction<_AStarPathNative, _AStarPathDart>('astar_path');
    _queryGpuInfo = _library
        .lookupFunction<_QueryGpuInfoNative, _QueryGpuInfoDart>('query_gpu_info');
  }

  /// Asks the native library for GPU / adapter info and prints it to
  /// stdout. On Windows this enumerates all DXGI adapters, reports the
  /// OS preference for high-performance vs low-power, and the adapter
  /// a default D3D11 device binds to (what ANGLE/Flutter sees). Elsewhere
  /// it prints a short "unsupported" line.
  void logGpuInfo() {
    const int bufferSize = 4096;
    final ffi.Pointer<ffi.Uint8> buffer =
        pkg_ffi.calloc<ffi.Uint8>(bufferSize);
    try {
      final int written = _queryGpuInfo(buffer.cast<ffi.Int8>(), bufferSize);
      if (written <= 0) {
        logLine('[MazeFfi] query_gpu_info returned $written');
        return;
      }
      final bytes = buffer.asTypedList(written);
      final text = String.fromCharCodes(bytes);
      for (final line in text.split('\n')) {
        if (line.trim().isEmpty) continue;
        logLine(line);
      }
    } finally {
      pkg_ffi.calloc.free(buffer);
    }
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

typedef _QueryGpuInfoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Int8> outBuffer,
  ffi.Int32 outBufferSize,
);

typedef _QueryGpuInfoDart = int Function(
  ffi.Pointer<ffi.Int8> outBuffer,
  int outBufferSize,
);

