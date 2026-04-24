import 'engine_impl_io.dart' if (dart.library.html) 'engine_impl_web.dart' as impl;

import 'maze_engine.dart';

/// Creates the appropriate [MazeEngine] for the current platform.
///
/// Desktop (`dart.library.io`) — Windows/Linux/macOS: adapts a
/// [DesktopFfiBackend] that calls the native maze shared library
/// (`maze_lib.dll` / `libmaze_lib.so` / `libmaze_lib.dylib`) via `dart:ffi`.
///
/// Web (`dart.library.html`): adapts either [WebServerBackend] (HTTP to a
/// C++ server) or [WebWasmBackend] (Emscripten-compiled C++ via JS interop),
/// selected by `--dart-define=MAZE_MODE=server|wasm`.
MazeEngine createMazeEngine() => impl.createMazeEngine();
