// Standalone end-to-end FFI smoke test for maze_lib.
//
// Usage (from repo root on Windows):
//   dart run tools/ffi_smoke.dart
//
// Expects the native shared library to be resolvable by DynamicLibrary.open:
//   - Windows: maze_lib.dll
//   - Linux:   libmaze_lib.so
//   - macOS:   libmaze_lib.dylib
// Looks up the built binary next to the release runner first, then falls back
// to the current directory and the system loader path.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

typedef _GenerateMazeNative = ffi.Int32 Function(
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 seed,
  ffi.Pointer<ffi.Uint8> outCells,
  ffi.Int32 outCellsLen,
);
typedef _GenerateMazeDart = int Function(
  int,
  int,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
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
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
  int,
  int,
  int,
  int,
  ffi.Pointer<ffi.Int32>,
  int,
);

String _libFileName() {
  if (Platform.isWindows) return 'maze_lib.dll';
  if (Platform.isMacOS) return 'libmaze_lib.dylib';
  if (Platform.isLinux) return 'libmaze_lib.so';
  throw UnsupportedError(Platform.operatingSystem);
}

List<String> _candidatePaths() {
  final name = _libFileName();
  final cwd = Directory.current.path;
  final sep = Platform.pathSeparator;
  return <String>[
    // Windows release output from `flutter build windows`.
    '${cwd}${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}$name',
    // Linux release output from `flutter build linux`.
    '${cwd}${sep}build${sep}linux${sep}x64${sep}release${sep}bundle${sep}lib${sep}$name',
    // Next to the CMake native build directory (if built directly).
    '${cwd}${sep}native${sep}build${sep}Release${sep}$name',
    '${cwd}${sep}native${sep}build${sep}$name',
    // Fall back to current directory and plain name (OS loader search).
    '${cwd}${sep}$name',
    name,
  ];
}

ffi.DynamicLibrary _open() {
  for (final path in _candidatePaths()) {
    try {
      final lib = ffi.DynamicLibrary.open(path);
      stdout.writeln('[ffi_smoke] Loaded "$path".');
      return lib;
    } on Object {
      // try next
    }
  }
  stderr.writeln('[ffi_smoke] Could not load ${_libFileName()} from any of:');
  for (final p in _candidatePaths()) {
    stderr.writeln('  - $p');
  }
  exit(2);
}

int main() {
  final lib = _open();
  final generateMaze = lib
      .lookupFunction<_GenerateMazeNative, _GenerateMazeDart>('generate_maze');
  final astarPath = lib
      .lookupFunction<_AStarPathNative, _AStarPathDart>('astar_path');

  const width = 10;
  const height = 10;
  const seed = 42;
  const cellCount = width * height;

  // --- generate_maze -------------------------------------------------------
  final cellsPtr = pkg_ffi.calloc<ffi.Uint8>(cellCount);
  final sw1 = Stopwatch()..start();
  final genResult = generateMaze(width, height, seed, cellsPtr, cellCount);
  sw1.stop();

  if (genResult != 0) {
    stderr.writeln('[ffi_smoke] generate_maze failed: $genResult');
    pkg_ffi.calloc.free(cellsPtr);
    return 1;
  }

  final cells = Uint8List.fromList(cellsPtr.asTypedList(cellCount));
  stdout.writeln(
      '[ffi_smoke] generate_maze ok: ${width}x$height, seed=$seed, '
      '${sw1.elapsedMicroseconds} us');

  // Invariant: a perfect-maze recursive backtracker produces exactly
  // (cells - 1) carved edges; each edge clears 2 wall bits. Each cell has
  // 4 walls. Missing-wall count should equal 2 * (cellCount - 1).
  var openWallBits = 0;
  for (final c in cells) {
    openWallBits += 4 - _popcount(c & 0xF);
  }
  if (openWallBits != 2 * (cellCount - 1)) {
    stderr.writeln(
        '[ffi_smoke] FAIL: open wall bits = $openWallBits, expected '
        '${2 * (cellCount - 1)}');
    return 1;
  }
  stdout.writeln('[ffi_smoke] perfect-maze invariant ok '
      '(open edges = ${openWallBits ~/ 2})');

  // --- astar_path ----------------------------------------------------------
  final pathPtr = pkg_ffi.calloc<ffi.Int32>(cellCount * 2);
  final sw2 = Stopwatch()..start();
  final pathLen =
      astarPath(cellsPtr, width, height, 0, 0, 9, 9, pathPtr, cellCount * 2);
  sw2.stop();

  if (pathLen < 0) {
    stderr.writeln('[ffi_smoke] astar_path failed: $pathLen');
    pkg_ffi.calloc.free(cellsPtr);
    pkg_ffi.calloc.free(pathPtr);
    return 1;
  }

  final path = pathPtr.asTypedList(pathLen * 2);
  final firstX = path[0];
  final firstY = path[1];
  final lastX = path[(pathLen - 1) * 2];
  final lastY = path[(pathLen - 1) * 2 + 1];

  if (firstX != 0 || firstY != 0 || lastX != 9 || lastY != 9) {
    stderr.writeln('[ffi_smoke] FAIL: path endpoints '
        '($firstX,$firstY) -> ($lastX,$lastY), expected (0,0) -> (9,9)');
    return 1;
  }

  stdout.writeln('[ffi_smoke] astar_path ok: length=$pathLen, '
      '${sw2.elapsedMicroseconds} us, (0,0) -> (9,9)');

  // --- error codes ---------------------------------------------------------
  final badResult = generateMaze(-1, -1, 0, cellsPtr, cellCount);
  if (badResult != -1) {
    stderr.writeln('[ffi_smoke] FAIL: invalid-args path returned $badResult, '
        'expected -1');
    return 1;
  }
  stdout.writeln('[ffi_smoke] error-code contract ok (invalid args -> -1)');

  pkg_ffi.calloc.free(cellsPtr);
  pkg_ffi.calloc.free(pathPtr);
  stdout.writeln('[ffi_smoke] ALL PASS');
  return 0;
}

int _popcount(int x) {
  var n = 0;
  var v = x & 0xFF;
  while (v != 0) {
    n += v & 1;
    v >>= 1;
  }
  return n;
}
