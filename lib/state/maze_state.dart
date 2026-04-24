import 'dart:math';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Simple value class representing an integer grid point.
class CellPoint {
  const CellPoint(this.x, this.y);

  final int x;
  final int y;
}

/// Visual mode for the maze view.
enum ViewMode {
  view2D,
  view3D,
}

/// Cardinal facing direction used by the 3D first-person view.
/// Clockwise from north: N=0, E=1, S=2, W=3.
enum Facing {
  north,
  east,
  south,
  west,
}

extension FacingOps on Facing {
  Facing turnedLeft() => Facing.values[(index + 3) % 4];
  Facing turnedRight() => Facing.values[(index + 1) % 4];

  /// Unit delta to step "forward" one cell from this facing.
  /// North = -y, East = +x, South = +y, West = -x.
  (int, int) get forwardDelta {
    switch (this) {
      case Facing.north: return (0, -1);
      case Facing.east:  return (1, 0);
      case Facing.south: return (0, 1);
      case Facing.west:  return (-1, 0);
    }
  }

  /// Yaw (radians) for a three_js camera: yaw=0 looks at +Z (south).
  double get yaw {
    switch (this) {
      case Facing.north: return math.pi;
      case Facing.east:  return math.pi / 2;
      case Facing.south: return 0;
      case Facing.west:  return -math.pi / 2;
    }
  }
}

/// Holds maze data and player / path state.
class MazeState extends ChangeNotifier {
  // Maze configuration
  int _width = 20;
  int _height = 20;
  int _seed = 1;

  // Maze cells encoded as wall bitflags, length = width * height.
  Uint8List _cells = Uint8List(0);

  // Player and target positions in grid coordinates.
  int _playerX = 0;
  int _playerY = 0;
  int _targetX = 0;
  int _targetY = 0;

  // A* path as ordered list of cells from start to target.
  List<CellPoint> _path = const [];
  // Hidden by default — the path is a user-requested hint, not an
  // always-on guide. Toggle Path flips it, Solve computes a fresh one.
  bool _showPath = false;

  // Simple stats.
  double _lastMazeGenMs = 0;
  double _lastSolveMs = 0;
  double _fps = 0;

  // Current visual mode.
  ViewMode _viewMode = ViewMode.view2D;

  // Player's facing direction (used only in 3D mode). Default: south, so
  // the player starts looking toward the default target at (w-1, h-1).
  Facing _facing = Facing.south;

  // FPS tracking internals (updated externally by a ticker).
  void updateFps(double fps) {
    if ((fps - _fps).abs() > 0.1) {
      _fps = fps;
      notifyListeners();
    }
  }

  // Public getters
  int get width => _width;
  int get height => _height;
  int get seed => _seed;
  Uint8List get cells => _cells;

  int get playerX => _playerX;
  int get playerY => _playerY;
  int get targetX => _targetX;
  int get targetY => _targetY;

  List<CellPoint> get path => _path;
  bool get showPath => _showPath;

  double get lastMazeGenMs => _lastMazeGenMs;
  double get lastSolveMs => _lastSolveMs;
  double get fps => _fps;

  ViewMode get viewMode => _viewMode;
  Facing get facing => _facing;

  int get pathLength => _path.length;

  /// Configure maze (cells, dimensions, seed) and reset player/target.
  void setMaze({
    required int width,
    required int height,
    required int seed,
    required Uint8List cells,
  }) {
    _width = width;
    _height = height;
    _seed = seed;
    _cells = cells;

    // Start at top-left, target at bottom-right by default.
    _playerX = 0;
    _playerY = 0;
    _targetX = max(0, width - 1);
    _targetY = max(0, height - 1);
    _facing = Facing.south;

    _path = const [];
    notifyListeners();
  }

  set viewMode(ViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();
  }

  void setLastMazeGenMs(double ms) {
    _lastMazeGenMs = ms;
    notifyListeners();
  }

  void setLastSolveMs(double ms) {
    _lastSolveMs = ms;
    notifyListeners();
  }

  void setPath(List<CellPoint> path) {
    _path = List.unmodifiable(path);
    notifyListeners();
  }

  void clearPath() {
    if (_path.isNotEmpty) {
      _path = const [];
      notifyListeners();
    }
  }

  void togglePathVisibility() {
    _showPath = !_showPath;
    notifyListeners();
  }

  void resetPlayer() {
    _playerX = 0;
    _playerY = 0;
    _facing = Facing.south;
    notifyListeners();
  }

  /// Turn the player 90° left (3D mode). No-op in 2D.
  void turnLeft() {
    _facing = _facing.turnedLeft();
    notifyListeners();
  }

  /// Turn the player 90° right (3D mode). No-op in 2D.
  void turnRight() {
    _facing = _facing.turnedRight();
    notifyListeners();
  }

  /// Step one cell in the current facing direction (3D mode).
  /// Blocked by walls via the same bitmask collision rules as 2D.
  void stepForward() {
    final (dx, dy) = _facing.forwardDelta;
    movePlayer(dx, dy);
  }

  /// Step one cell opposite the current facing direction (3D mode).
  void stepBackward() {
    final (dx, dy) = _facing.forwardDelta;
    movePlayer(-dx, -dy);
  }

  /// Strafe one cell to the player's left (perpendicular to facing).
  void strafeLeft() {
    final (dx, dy) = _facing.turnedLeft().forwardDelta;
    movePlayer(dx, dy);
  }

  /// Strafe one cell to the player's right (perpendicular to facing).
  void strafeRight() {
    final (dx, dy) = _facing.turnedRight().forwardDelta;
    movePlayer(dx, dy);
  }

  void setTarget(int x, int y) {
    if (x == _targetX && y == _targetY) return;
    _targetX = x.clamp(0, _width - 1);
    _targetY = y.clamp(0, _height - 1);
    notifyListeners();
  }

  /// Returns true if movement by (dx, dy) is allowed from the current player cell
  /// according to the encoded walls.
  bool _canMove(int dx, int dy) {
    if (_cells.isEmpty) return false;

    final int nx = _playerX + dx;
    final int ny = _playerY + dy;
    if (nx < 0 || nx >= _width || ny < 0 || ny >= _height) {
      return false;
    }

    const int wallUp = 1;
    const int wallRight = 2;
    const int wallDown = 4;
    const int wallLeft = 8;

    final int index = _playerY * _width + _playerX;
    final int cell = _cells[index];

    if (dx == 1 && dy == 0) {
      // Moving right: must have no right wall on current and no left wall on neighbor.
      if ((cell & wallRight) != 0) return false;
      final int neighbor = _cells[ny * _width + nx];
      if ((neighbor & wallLeft) != 0) return false;
      return true;
    } else if (dx == -1 && dy == 0) {
      // Moving left.
      if ((cell & wallLeft) != 0) return false;
      final int neighbor = _cells[ny * _width + nx];
      if ((neighbor & wallRight) != 0) return false;
      return true;
    } else if (dx == 0 && dy == 1) {
      // Moving down.
      if ((cell & wallDown) != 0) return false;
      final int neighbor = _cells[ny * _width + nx];
      if ((neighbor & wallUp) != 0) return false;
      return true;
    } else if (dx == 0 && dy == -1) {
      // Moving up.
      if ((cell & wallUp) != 0) return false;
      final int neighbor = _cells[ny * _width + nx];
      if ((neighbor & wallDown) != 0) return false;
      return true;
    }

    // Diagonals are not supported.
    return false;
  }

  /// Move the player by one cell if there is no blocking wall.
  void movePlayer(int dx, int dy) {
    if (dx == 0 && dy == 0) return;
    if (!_canMove(dx, dy)) return;

    _playerX += dx;
    _playerY += dy;
    notifyListeners();
  }
}

