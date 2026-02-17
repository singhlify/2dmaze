import 'package:flutter/material.dart';

import '../state/maze_state.dart';

/// Renders the maze grid, player, target, and optional A* path.
class MazePainter extends CustomPainter {
  MazePainter(this.state);

  final MazeState state;

  @override
  void paint(Canvas canvas, Size size) {
    final int width = state.width;
    final int height = state.height;
    if (width <= 0 || height <= 0) {
      return;
    }

    final double cellWidth = size.width / width;
    final double cellHeight = size.height / height;

    final Paint backgroundPaint = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final Paint wallPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0;

    final cells = state.cells;
    if (cells.isNotEmpty) {
      // Draw walls based on bitflags per cell.
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int index = y * width + x;
          final int cell = cells[index];
          final double left = x * cellWidth;
          final double top = y * cellHeight;
          final double right = left + cellWidth;
          final double bottom = top + cellHeight;

          if ((cell & MazeCellWalls.wallUp) != 0) {
            canvas.drawLine(
              Offset(left, top),
              Offset(right, top),
              wallPaint,
            );
          }
          if ((cell & MazeCellWalls.wallRight) != 0) {
            canvas.drawLine(
              Offset(right, top),
              Offset(right, bottom),
              wallPaint,
            );
          }
          if ((cell & MazeCellWalls.wallDown) != 0) {
            canvas.drawLine(
              Offset(left, bottom),
              Offset(right, bottom),
              wallPaint,
            );
          }
          if ((cell & MazeCellWalls.wallLeft) != 0) {
            canvas.drawLine(
              Offset(left, top),
              Offset(left, bottom),
              wallPaint,
            );
          }
        }
      }
    }

    // Draw A* path overlay if enabled.
    if (state.showPath && state.path.isNotEmpty) {
      final Paint pathPaint = Paint()
        ..color = Colors.yellowAccent
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final path = Path();
      for (int i = 0; i < state.path.length; i++) {
        final cell = state.path[i];
        final double cx = (cell.x + 0.5) * cellWidth;
        final double cy = (cell.y + 0.5) * cellHeight;
        if (i == 0) {
          path.moveTo(cx, cy);
        } else {
          path.lineTo(cx, cy);
        }
      }
      canvas.drawPath(path, pathPaint);
    }

    // Draw target cell.
    final Paint targetPaint = Paint()..color = Colors.redAccent;
    final double targetLeft = state.targetX * cellWidth;
    final double targetTop = state.targetY * cellHeight;
    final Rect targetRect = Rect.fromLTWH(
      targetLeft + cellWidth * 0.25,
      targetTop + cellHeight * 0.25,
      cellWidth * 0.5,
      cellHeight * 0.5,
    );
    canvas.drawRect(targetRect, targetPaint);

    // Draw player.
    final Paint playerPaint = Paint()..color = Colors.lightBlueAccent;
    final double playerCx = (state.playerX + 0.5) * cellWidth;
    final double playerCy = (state.playerY + 0.5) * cellHeight;
    final double radius = 0.35 * (cellWidth < cellHeight ? cellWidth : cellHeight);
    canvas.drawCircle(Offset(playerCx, playerCy), radius, playerPaint);
  }

  @override
  bool shouldRepaint(covariant MazePainter oldDelegate) {
    // MazeState is mutable and drives repaints via AnimatedBuilder.
    // Always repaint on change notifications for simplicity.
    return true;
  }
}

/// Convenience wall flag constants mirroring the native/C++ side.
class MazeCellWalls {
  static const int wallUp = 1;
  static const int wallRight = 2;
  static const int wallDown = 4;
  static const int wallLeft = 8;
}

