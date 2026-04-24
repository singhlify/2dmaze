import 'package:maze_runner_windows/maze/maze_backend.dart';
import 'maze_engine.dart';

/// Web implementation: returns [MazeEngineFromBackend] with server or wasm backend per MAZE_MODE.
MazeEngine createMazeEngine() => MazeEngineFromBackend(createMazeBackend());
