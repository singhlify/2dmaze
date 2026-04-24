import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

import '../state/maze_state.dart';

class Maze3DSceneResult {
  Maze3DSceneResult({
    required this.scene,
    required this.wallCount,
  });

  final three.Scene scene;
  final int wallCount;
}

/// Populates [scene] with the current maze geometry. Clears any existing
/// children first, so this is safe to call every frame that state changes.
///
/// Why mutate rather than build a fresh Scene: `ThreeJS.scene` is declared
/// `late final` in the three_js package, meaning assignment after first
/// render is a no-op (or throws). Replacing children in-place is the only
/// way to reliably update the displayed scene.
Maze3DSceneResult buildMaze3DScene({
  required three.Scene scene,
  required MazeState state,
  required three.Texture wallTexture,
  required three.Texture floorTexture,
  three.Texture? ceilingTexture,
  bool showPath = false,
}) {
  // Remove all existing children before repopulating.
  while (scene.children.isNotEmpty) {
    scene.remove(scene.children.last);
  }

  final width = state.width;
  final height = state.height;
  if (width <= 0 || height <= 0) {
    return Maze3DSceneResult(scene: scene, wallCount: 0);
  }

  // Basic lighting.
  scene.add(three.AmbientLight(0xffffff, 0.4));
  final directional = three.DirectionalLight(0xffffff, 0.6)
    ..position.setValues(10, 10, 5);
  scene
    ..add(directional)
    ..add(directional.target);

  // Tile floor and ceiling textures once per cell so detail stays readable
  // regardless of maze size. Walls are 1x1 so they use default (1,1) repeat.
  floorTexture
    ..wrapS = three.RepeatWrapping
    ..wrapT = three.RepeatWrapping
    ..repeat.setValues(width.toDouble(), height.toDouble())
    ..needsUpdate = true;

  // Floor.
  final floorGeom = three.PlaneGeometry(width.toDouble(), height.toDouble());
  final floorMat = three.MeshStandardMaterial.fromMap({
    'map': floorTexture,
  })
    ..side = three.DoubleSide
    ..roughness = 1.0
    ..metalness = 0.0;

  final floorMesh = three.Mesh(floorGeom, floorMat)
    ..rotation.x = -math.pi / 2
    ..position.setValues(width / 2.0, 0, height / 2.0);
  scene.add(floorMesh);

  // Optional ceiling.
  if (ceilingTexture != null) {
    ceilingTexture
      ..wrapS = three.RepeatWrapping
      ..wrapT = three.RepeatWrapping
      ..repeat.setValues(width.toDouble(), height.toDouble())
      ..needsUpdate = true;

    final ceilingGeom =
        three.PlaneGeometry(width.toDouble(), height.toDouble());
    final ceilingMat = three.MeshStandardMaterial.fromMap({
      'map': ceilingTexture,
    })
      ..side = three.DoubleSide
      ..roughness = 1.0
      ..metalness = 0.0;

    final ceilingMesh = three.Mesh(ceilingGeom, ceilingMat)
      ..rotation.x = math.pi / 2
      ..position.setValues(width / 2.0, 1.0, height / 2.0);
    scene.add(ceilingMesh);
  }

  // Walls: one unit per cell on XZ plane.
  final cells = state.cells;
  const wallUp = 1;
  const wallRight = 2;
  const wallDown = 4;
  const wallLeft = 8;

  final wallGeom = three.BoxGeometry(1.0, 1.0, 0.1);
  final wallMat = three.MeshStandardMaterial.fromMap({
    'map': wallTexture,
  })
    ..roughness = 1.0
    ..metalness = 0.0;

  int wallCount = 0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (index < 0 || index >= cells.length) {
        continue;
      }
      final cell = cells[index];

          final cx = x.toDouble();
          final cy = y.toDouble();

      // Render only north and west interior walls to avoid duplicates.
      if ((cell & wallUp) != 0) {
        final mesh = three.Mesh(wallGeom, wallMat)
          ..position.setValues(cx + 0.5, 0.5, cy)
          ..rotation.y = 0;
        scene.add(mesh);
        wallCount++;
      }
      if ((cell & wallLeft) != 0) {
        final mesh = three.Mesh(wallGeom, wallMat)
          ..position.setValues(cx, 0.5, cy + 0.5)
          ..rotation.y = math.pi / 2;
        scene.add(mesh);
        wallCount++;
      }

      // Add east boundary wall for last column.
      if (x == width - 1 && (cell & wallRight) != 0) {
        final mesh = three.Mesh(wallGeom, wallMat)
          ..position.setValues(cx + 1.0, 0.5, cy + 0.5)
          ..rotation.y = math.pi / 2;
        scene.add(mesh);
        wallCount++;
      }

      // Add south boundary wall for last row.
      if (y == height - 1 && (cell & wallDown) != 0) {
        final mesh = three.Mesh(wallGeom, wallMat)
          ..position.setValues(cx + 0.5, 0.5, cy + 1.0)
          ..rotation.y = 0;
        scene.add(mesh);
        wallCount++;
      }
    }
  }

  // Target marker.
  final targetGeom = three.BoxGeometry(0.4, 0.4, 0.4);
  final targetMat = three.MeshStandardMaterial.fromMap({
    'color': 0xff4444,
    'emissive': 0xaa0000,
  });
  final targetMesh = three.Mesh(targetGeom, targetMat)
    ..position.setValues(
      state.targetX + 0.5,
      0.4,
      state.targetY + 0.5,
    );
  scene.add(targetMesh);

  // Optional path visualization — a bright glowing floor overlay at
  // each cell in the path. Uses MeshStandardMaterial with strong
  // emissive so it reads even in shadow, same material family as the
  // walls. The current player cell is skipped so the trail reads as
  // "the path ahead of you" rather than "you are here".
  if (showPath && state.showPath && state.path.isNotEmpty) {
    final overlayGeom = three.PlaneGeometry(0.96, 0.96);
    final overlayMat = three.MeshStandardMaterial.fromMap({
      'color': 0xfff05a,
      'emissive': 0xffaa00,
    })
      ..side = three.DoubleSide
      ..roughness = 0.2
      ..metalness = 0.0;

    for (final cell in state.path) {
      if (cell.x == state.playerX && cell.y == state.playerY) continue;
      final overlay = three.Mesh(overlayGeom, overlayMat)
        ..rotation.x = -math.pi / 2
        ..position.setValues(cell.x + 0.5, 0.01, cell.y + 0.5);
      scene.add(overlay);
    }
  }

  return Maze3DSceneResult(scene: scene, wallCount: wallCount);
}

