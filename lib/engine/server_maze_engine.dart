import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../state/maze_state.dart';
import 'maze_engine.dart';

/// Maze engine that calls the C++ HTTP server (for Flutter Web).
class ServerMazeEngine implements MazeEngine {
  ServerMazeEngine({String? baseUrl})
      : _baseUrl = baseUrl ??
            const String.fromEnvironment('MAZE_SERVER_URL',
                defaultValue: 'http://localhost:8080');

  final String _baseUrl;

  String get baseUrl => _baseUrl;

  @override
  Future<Uint8List> generateMaze({
    required int width,
    required int height,
    required int seed,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/maze/generate');
    final body = jsonEncode({
      'width': width,
      'height': height,
      'seed': seed,
    });
    final client = http.Client();
    try {
      final response = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode != 200) {
        final String msg = _tryParseError(response.body) ??
            'HTTP ${response.statusCode}';
        throw Exception('Generate maze failed: $msg');
      }
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String? cellsB64 = data['cells_base64'] as String?;
      if (cellsB64 == null) {
        throw Exception('Server response missing cells_base64');
      }
      return Uint8List.fromList(base64Decode(cellsB64));
    } finally {
      client.close();
    }
  }

  @override
  Future<List<CellPoint>> astarPath({
    required Uint8List cells,
    required int width,
    required int height,
    required int sx,
    required int sy,
    required int tx,
    required int ty,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/maze/astar');
    final body = jsonEncode({
      'width': width,
      'height': height,
      'sx': sx,
      'sy': sy,
      'tx': tx,
      'ty': ty,
      'cells_base64': base64Encode(cells),
    });
    final client = http.Client();
    try {
      final response = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode != 200) {
      final String msg = _tryParseError(response.body) ??
          'HTTP ${response.statusCode}';
        throw Exception('A* path failed: $msg');
      }
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic>? pathXy = data['path_xy'] as List<dynamic>?;
      final int? pathLen = data['path_len'] as int?;
      if (pathXy == null || pathLen == null) {
        throw Exception('Server response missing path_xy or path_len');
      }
      final List<CellPoint> path = <CellPoint>[];
      for (int i = 0; i < pathLen; i++) {
        final int x = (pathXy[2 * i] as num).toInt();
        final int y = (pathXy[2 * i + 1] as num).toInt();
        path.add(CellPoint(x, y));
      }
      return path;
    } finally {
      client.close();
    }
  }

  String? _tryParseError(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['error'] as String?;
    } catch (_) {
      return null;
    }
  }
}
