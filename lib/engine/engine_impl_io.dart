import 'package:maze_runner_windows/maze/maze_backend.dart';
import 'maze_engine.dart';

/// Desktop/IO implementation: returns [MazeEngineFromBackend] with [DesktopFfiBackend].
MazeEngine createMazeEngine() => MazeEngineFromBackend(createMazeBackend());
