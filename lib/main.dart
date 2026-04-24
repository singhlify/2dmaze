import 'package:flutter/material.dart';

import 'engine/maze_engine.dart';
import 'engine/maze_engine_factory.dart';
import 'logging/logger.dart';
import 'ui/maze_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Open the log file as early as possible so even the startup [GPU]
  // / [LOG] lines land in it (createMazeEngine prints GPU info).
  final logPath = initLogger();
  if (logPath != null) {
    logLine('[LOG] file=$logPath');
  }
  final engine = createMazeEngine();
  runApp(MazeRunnerApp(engine: engine));
}

class MazeRunnerApp extends StatelessWidget {
  const MazeRunnerApp({required this.engine});

  final MazeEngine engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maze Runner PoC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: MazeScreen(engine: engine),
      debugShowCheckedModeBanner: false,
    );
  }
}

