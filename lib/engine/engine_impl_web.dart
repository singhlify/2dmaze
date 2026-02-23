import 'maze_engine.dart';
import 'server_maze_engine.dart';

/// Web implementation: returns [ServerMazeEngine] when MAZE_MODE=server, else throws.
MazeEngine createMazeEngine() {
  const mode = String.fromEnvironment('MAZE_MODE', defaultValue: '');
  if (mode == 'server') {
    return ServerMazeEngine();
  }
  throw UnsupportedError(
    'On web, set --dart-define=MAZE_MODE=server (and optionally MAZE_SERVER_URL).',
  );
}
