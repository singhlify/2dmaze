// Tiny harness to exercise query_gpu_info from the release DLL and
// print the output. Run from repo root after building the Windows app:
//
//   dart run tools/gpu_info.dart
//
// On this Intel-iGPU test host it'll print exactly one adapter. On a
// hybrid (iGPU + dGPU) machine it'll list both plus the preferences
// and which one a default D3D11 device picks.

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkg_ffi;

typedef _QueryGpuInfoNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Int8>, ffi.Int32);
typedef _QueryGpuInfoDart = int Function(ffi.Pointer<ffi.Int8>, int);

String _libName() {
  if (Platform.isWindows) return 'maze_lib.dll';
  if (Platform.isMacOS) return 'libmaze_lib.dylib';
  if (Platform.isLinux) return 'libmaze_lib.so';
  throw UnsupportedError(Platform.operatingSystem);
}

ffi.DynamicLibrary _open() {
  final name = _libName();
  final sep = Platform.pathSeparator;
  final cwd = Directory.current.path;
  final candidates = [
    '$cwd${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}$name',
    '$cwd${sep}build${sep}linux${sep}x64${sep}release${sep}bundle${sep}lib${sep}$name',
    '$cwd${sep}native${sep}build${sep}Release${sep}$name',
    '$cwd${sep}native${sep}build${sep}$name',
    name,
  ];
  for (final p in candidates) {
    try {
      return ffi.DynamicLibrary.open(p);
    } on Object {
      // try next
    }
  }
  stderr.writeln('Could not find $name; tried:');
  for (final p in candidates) {
    stderr.writeln('  $p');
  }
  exit(2);
}

void main() {
  final lib = _open();
  final query = lib.lookupFunction<_QueryGpuInfoNative, _QueryGpuInfoDart>(
      'query_gpu_info');
  const size = 4096;
  final buf = pkg_ffi.calloc<ffi.Int8>(size);
  try {
    final n = query(buf, size);
    if (n <= 0) {
      stderr.writeln('query_gpu_info returned $n');
      exit(1);
    }
    final bytes = buf.cast<ffi.Uint8>().asTypedList(n);
    stdout.write(String.fromCharCodes(bytes));
  } finally {
    pkg_ffi.calloc.free(buf);
  }
}
