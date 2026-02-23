import 'native_maze_engine.dart';
import 'maze_engine.dart';

/// Desktop/IO implementation: returns [NativeMazeEngine] (uses maze_lib.dll via FFI).
MazeEngine createMazeEngine() => NativeMazeEngine();
