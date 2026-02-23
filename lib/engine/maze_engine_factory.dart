import 'engine_impl_io.dart' if (dart.library.html) 'engine_impl_web.dart' as impl;

import 'maze_engine.dart';

/// Creates the appropriate [MazeEngine] for the current platform.
/// On desktop (dart.library.io): [NativeMazeEngine].
/// On web (dart.library.html): [ServerMazeEngine] when MAZE_MODE=server, else throws.
MazeEngine createMazeEngine() => impl.createMazeEngine();
