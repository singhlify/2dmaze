// Perf characterization for maze_lib via dart:ffi.
//
// Runs generate_maze + astar_path at multiple sizes and prints microsecond
// timings so we can report concrete perf numbers for the PoC review.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

typedef _GenerateMazeNative = ffi.Int32 Function(
  ffi.Int32, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _GenerateMazeDart = int Function(
  int, int, int, ffi.Pointer<ffi.Uint8>, int);

typedef _AStarPathNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Pointer<ffi.Int32>,
  ffi.Int32,
);
typedef _AStarPathDart = int Function(
  ffi.Pointer<ffi.Uint8>, int, int, int, int, int, int,
  ffi.Pointer<ffi.Int32>, int,
);

String _libName() => Platform.isWindows
    ? 'maze_lib.dll'
    : Platform.isMacOS
        ? 'libmaze_lib.dylib'
        : 'libmaze_lib.so';

ffi.DynamicLibrary _open() {
  final name = _libName();
  final sep = Platform.pathSeparator;
  final cwd = Directory.current.path;
  final candidates = [
    '${cwd}${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}$name',
    '${cwd}${sep}build${sep}linux${sep}x64${sep}release${sep}bundle${sep}lib${sep}$name',
    '${cwd}${sep}native${sep}build${sep}Release${sep}$name',
    '${cwd}${sep}native${sep}build${sep}$name',
    name,
  ];
  for (final p in candidates) {
    try {
      return ffi.DynamicLibrary.open(p);
    } on Object {
      // try next
    }
  }
  throw StateError('cannot find $name');
}

void main() {
  final lib = _open();
  final gen = lib
      .lookupFunction<_GenerateMazeNative, _GenerateMazeDart>('generate_maze');
  final astar = lib
      .lookupFunction<_AStarPathNative, _AStarPathDart>('astar_path');

  final sizes = [20, 50, 100, 200];

  stdout.writeln(
      'size    | gen_us  | astar_us | path_len | cells');
  stdout.writeln(
      '--------|---------|----------|----------|------');

  for (final n in sizes) {
    final cellCount = n * n;
    final cellsPtr = pkg_ffi.calloc<ffi.Uint8>(cellCount);
    final pathPtr = pkg_ffi.calloc<ffi.Int32>(cellCount * 2);

    // Warm the cache.
    gen(n, n, 1, cellsPtr, cellCount);

    final sw1 = Stopwatch()..start();
    final r1 = gen(n, n, 42, cellsPtr, cellCount);
    sw1.stop();
    if (r1 != 0) {
      stderr.writeln('generate_maze($n) failed: $r1');
      continue;
    }

    final sw2 = Stopwatch()..start();
    final pathLen =
        astar(cellsPtr, n, n, 0, 0, n - 1, n - 1, pathPtr, cellCount * 2);
    sw2.stop();
    if (pathLen < 0) {
      stderr.writeln('astar_path($n) failed: $pathLen');
      continue;
    }

    stdout.writeln('${'${n}x$n'.padRight(7)} | '
        '${sw1.elapsedMicroseconds.toString().padLeft(7)} | '
        '${sw2.elapsedMicroseconds.toString().padLeft(8)} | '
        '${pathLen.toString().padLeft(8)} | '
        '$cellCount');

    pkg_ffi.calloc.free(cellsPtr);
    pkg_ffi.calloc.free(pathPtr);

    // Suppress `unused` warning on import.
    Uint8List(0);
  }
}
