import 'package:flutter/material.dart';

import 'engine/maze_engine.dart';
import 'engine/maze_engine_factory.dart';
import 'ui/maze_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

