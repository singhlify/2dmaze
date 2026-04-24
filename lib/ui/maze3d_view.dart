import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:three_js/three_js.dart' as three;

import '../state/maze_state.dart';
import 'maze3d_hud.dart';
import 'maze3d_scene.dart';

/// First-person 3D maze view driven entirely by [MazeState].
///
/// No internal controller, no keyboard listener, no mouse-drag. The outer
/// screen's KeyboardListener routes WASD/arrows to MazeState methods
/// (stepForward/stepBackward/turnLeft/turnRight), and this view
/// smoothly interpolates the camera toward the target pose derived from
/// MazeState each frame. This mirrors classic tile-based 3D dungeon
/// crawlers (Wolfenstein / Eye of the Beholder style) — reliable,
/// focus-safe, and impossible to "leak" into a spinning state.
class Maze3DView extends StatefulWidget {
  const Maze3DView({super.key, required this.state});

  final MazeState state;

  @override
  State<Maze3DView> createState() => _Maze3DViewState();
}

class _Maze3DViewState extends State<Maze3DView>
    with SingleTickerProviderStateMixin {
  late final three.ThreeJS _threeJs;
  late final Ticker _ticker;

  three.Texture? _wallTexture;
  three.Texture? _floorTexture;
  three.Texture? _ceilingTexture;

  int _wallCount = 0;

  // Animated camera pose — lerps toward the MazeState-derived target.
  double _camX = 0, _camY = 0.5, _camZ = 0;
  double _camYaw = 0;

  // Previous state values we animate from; when the player jumps more
  // than one cell (e.g., new maze) we snap instead of lerping.
  int _lastPlayerX = -1;
  int _lastPlayerY = -1;

  Duration _lastTickerTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _threeJs = three.ThreeJS(
      onSetupComplete: () {
        if (mounted) setState(() {});
      },
      setup: _setup,
    );
    widget.state.addListener(_onStateChanged);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant Maze3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _snapCameraToState();
      _rebuildScene();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _ticker.dispose();
    _threeJs.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    _threeJs.camera =
        three.PerspectiveCamera(75, _threeJs.width / _threeJs.height, 0.1, 1000);
    // ThreeJS.scene is `late final` — assign it exactly once here.
    _threeJs.scene = three.Scene();

    final loader = three.TextureLoader();
    _wallTexture = await loader.fromAsset('assets/textures/wall.png');
    _floorTexture = await loader.fromAsset('assets/textures/floor.png');
    _ceilingTexture = await loader.fromAsset('assets/textures/ceiling.png');

    _snapCameraToState();
    _rebuildScene();
  }

  void _onStateChanged() {
    _rebuildScene();
  }

  /// Snap camera directly to the current state's target pose (no lerp).
  /// Called on init, widget-swap, and when the maze is regenerated.
  void _snapCameraToState() {
    final s = widget.state;
    _camX = s.playerX + 0.5;
    _camY = 0.5;
    _camZ = s.playerY + 0.5;
    _camYaw = s.facing.yaw;
    _lastPlayerX = s.playerX;
    _lastPlayerY = s.playerY;
  }

  void _rebuildScene() {
    if (_wallTexture == null || _floorTexture == null) return;

    // Detect a "new maze" — size changed, or player jumped to a cell
    // more than one step away — and snap instead of lerp in that case.
    final s = widget.state;
    final dx = (s.playerX - _lastPlayerX).abs();
    final dy = (s.playerY - _lastPlayerY).abs();
    if (_lastPlayerX < 0 || dx + dy > 1) {
      _snapCameraToState();
    }

    final result = buildMaze3DScene(
      scene: _threeJs.scene,
      state: s,
      wallTexture: _wallTexture!,
      floorTexture: _floorTexture!,
      ceilingTexture: _ceilingTexture,
      showPath: s.showPath,
    );
    _wallCount = result.wallCount;
  }

  void _onTick(Duration elapsed) {
    if (_wallTexture == null) return;
    final camera = _threeJs.camera;

    final dt = (_lastTickerTime == Duration.zero)
        ? 1.0 / 60.0
        : (elapsed - _lastTickerTime).inMicroseconds / 1e6;
    _lastTickerTime = elapsed;
    if (dt <= 0) return;

    final s = widget.state;
    final tgtX = s.playerX + 0.5;
    final tgtZ = s.playerY + 0.5;
    final tgtYaw = s.facing.yaw;

    // Ease-in-out via exponential smoothing. Time constant ~120ms
    // feels snappy but not jarring for tile-sized steps.
    const timeConstant = 0.12;
    final alpha = 1.0 - math.exp(-dt / timeConstant);

    _camX += (tgtX - _camX) * alpha;
    _camZ += (tgtZ - _camZ) * alpha;

    // Yaw needs shortest-arc interpolation so a turn from
    // west (-π/2) to north (+π) goes the short way.
    var yawDelta = tgtYaw - _camYaw;
    while (yawDelta > math.pi) {
      yawDelta -= 2 * math.pi;
    }
    while (yawDelta < -math.pi) {
      yawDelta += 2 * math.pi;
    }
    _camYaw += yawDelta * alpha;

    _lastPlayerX = s.playerX;
    _lastPlayerY = s.playerY;

    _updateCamera(camera);
  }

  void _updateCamera(dynamic camera) {
    camera.position
      ..x = _camX
      ..y = _camY
      ..z = _camZ;

    final forwardX = math.sin(_camYaw);
    final forwardZ = math.cos(_camYaw);
    final target = three.Vector3(
      _camX + forwardX,
      _camY,
      _camZ + forwardZ,
    );
    camera.lookAt(target);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _threeJs.build(),
        Maze3DHud(state: widget.state, wallCount: _wallCount),
      ],
    );
  }
}
