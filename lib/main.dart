import 'package:flutter/material.dart';

import 'ui/maze_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MazeRunnerApp());
}

class MazeRunnerApp extends StatelessWidget {
  const MazeRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maze Runner PoC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const MazeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

