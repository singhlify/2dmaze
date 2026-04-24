// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../../state/maze_state.dart';

/// JS API object exposed as window.MazeWasm by web/wasm/maze.js (plain object, not a constructor).
@JS('MazeWasm')
external JSObject get _mazeWasmJS;

/// Dart interop for the C++ maze WASM module (web only).
/// Call [initMazeWasm] once before [generateMaze] / [astarPath]; lazy init is done automatically.
class MazeWasmInterop {
  MazeWasmInterop._();

  static final MazeWasmInterop instance = MazeWasmInterop._();

  bool _initialized = false;
  Future<void>? _initFuture;

  /// Ensures the WASM module is loaded and instantiated. Idempotent.
  Future<void> initMazeWasm() async {
    if (_initialized) return;
    _initFuture ??= _mazeWasmJS.callMethod<JSPromise<JSAny?>>('initMazeWasm'.toJS).toDart;
    await _initFuture;
    _initialized = true;
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MazeWasmInterop] WASM maze module initialized.');
    }
  }

  /// Generates maze cells; returns [Uint8List] of length width * height.
  Future<Uint8List> generateMaze(int width, int height, int seed) async {
    await initMazeWasm();
    final result = _mazeWasmJS.callMethod<JSObject?>('generateMaze'.toJS, width.toJS, height.toJS, seed.toJS);
    if (result == null) throw Exception('WASM generateMaze returned null');
    return _jsUint8ArrayToDart(result);
  }

  /// Computes A* path; returns list of [CellPoint] from (sx,sy) to (tx,ty).
  Future<List<CellPoint>> astarPath(
    Uint8List cells,
    int width,
    int height,
    int sx,
    int sy,
    int tx,
    int ty,
  ) async {
    await initMazeWasm();
    final cellsJS = _dartUint8ListToJS(cells);
    final result = _mazeWasmJS.callMethodVarArgs<JSObject?>(
      'astarPath'.toJS,
      [cellsJS, width.toJS, height.toJS, sx.toJS, sy.toJS, tx.toJS, ty.toJS],
    );
    if (result == null) throw Exception('WASM astarPath returned null');
    return _jsInt32ArrayToCellPoints(result);
  }

  static int _jsNumberToInt(JSAny? v) {
    if (v == null) return 0;
    return (v as JSNumber).toDartInt;
  }

  static Uint8List _jsUint8ArrayToDart(JSObject arr) {
    final len = _jsNumberToInt(arr.getProperty<JSAny?>('length'.toJS));
    final out = Uint8List(len);
    for (int i = 0; i < len; i++) {
      out[i] = _jsNumberToInt(arr.getProperty<JSAny?>(i.toJS));
    }
    return out;
  }

  static List<CellPoint> _jsInt32ArrayToCellPoints(JSObject arr) {
    final len = _jsNumberToInt(arr.getProperty<JSAny?>('length'.toJS));
    final pairCount = len ~/ 2;
    final path = <CellPoint>[];
    for (int i = 0; i < pairCount; i++) {
      path.add(CellPoint(
        _jsNumberToInt(arr.getProperty<JSAny?>((2 * i).toJS)),
        _jsNumberToInt(arr.getProperty<JSAny?>((2 * i + 1).toJS)),
      ));
    }
    return path;
  }

  /// Copy Dart Uint8List to JS Uint8Array via MazeWasm.createUint8ArrayFromBase64(base64).
  static JSObject? _dartUint8ListToJS(Uint8List list) {
    final b64 = base64Encode(list);
    return _mazeWasmJS.callMethod<JSObject?>('createUint8ArrayFromBase64'.toJS, b64.toJS);
  }
}
