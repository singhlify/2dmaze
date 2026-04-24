// Wrapper appended after Emscripten output. Expects createMazeModule in scope.
(function () {
  'use strict';
  var Module = null;

  function ensureModule() {
    if (Module) return Promise.resolve();
    var locateFile = function (path) {
      return (typeof window !== 'undefined' && window.location ? window.location.pathname.replace(/\/[^/]*$/, '/') : '') + 'wasm/' + path;
    };
    return typeof createMazeModule !== 'undefined'
      ? createMazeModule({ locateFile: locateFile }).then(function (m) { Module = m; })
      : Promise.reject(new Error('createMazeModule not found'));
  }

  function createUint8Array(arr) {
    return new Uint8Array(arr);
  }

  function createUint8ArrayFromBase64(base64) {
    var binary = atob(base64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function generateMaze(width, height, seed) {
    var cellCount = width * height;
    var ptr = Module._malloc(cellCount);
    if (!ptr) throw new Error('WASM malloc failed');
    try {
      var result = Module._generate_maze(width, height, seed, ptr, cellCount);
      if (result !== 0) throw new Error('generate_maze failed: ' + result);
      var out = new Uint8Array(cellCount);
      out.set(Module.HEAPU8.subarray(ptr, ptr + cellCount));
      return out;
    } finally {
      Module._free(ptr);
    }
  }

  function astarPath(cellsUint8Array, width, height, sx, sy, tx, ty) {
    var cellCount = width * height;
    var cellsPtr = Module._malloc(cellCount);
    if (!cellsPtr) throw new Error('WASM malloc failed (cells)');
    var pathSlots = cellCount * 2;
    var pathPtr = Module._malloc(pathSlots * 4);
    if (!pathPtr) {
      Module._free(cellsPtr);
      throw new Error('WASM malloc failed (path)');
    }
    try {
      Module.HEAPU8.set(cellsUint8Array, cellsPtr);
      var pathLen = Module._astar_path(cellsPtr, width, height, sx, sy, tx, ty, pathPtr, pathSlots);
      if (pathLen < 0) throw new Error('astar_path failed: ' + pathLen);
      var out = new Int32Array(pathLen * 2);
      out.set(Module.HEAP32.subarray(pathPtr >> 2, (pathPtr >> 2) + pathLen * 2));
      return out;
    } finally {
      Module._free(cellsPtr);
      Module._free(pathPtr);
    }
  }

  function initMazeWasm() {
    return ensureModule();
  }

  if (typeof window !== 'undefined') {
    window.MazeWasm = {
      initMazeWasm: initMazeWasm,
      generateMaze: generateMaze,
      astarPath: astarPath,
      createUint8Array: createUint8Array,
      createUint8ArrayFromBase64: createUint8ArrayFromBase64
    };
  }
})();
