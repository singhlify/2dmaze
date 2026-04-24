#!/usr/bin/env bash
# Build C++ maze_lib to WebAssembly using Emscripten.
# Requires Emscripten SDK: https://emscripten.org/docs/getting_started/downloads.html
# Run from repo root: ./tools/build_wasm.sh

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f "native/maze_lib.cpp" ]; then
  echo "Error: native/maze_lib.cpp not found. Run from repo root." >&2
  exit 1
fi

# Find emcc. Works for POSIX shells and for git-bash on Windows, where the
# Emscripten entry point is `emcc.bat` and `command -v` may not pick up .bat
# files depending on PATHEXT.
EMCC=""
for candidate in emcc emcc.bat; do
  if command -v "$candidate" >/dev/null 2>&1; then
    EMCC="$candidate"
    break
  fi
done
if [ -z "$EMCC" ]; then
  for loc in \
    "${EMSDK:-}/upstream/emscripten/emcc" \
    "${EMSDK:-}/upstream/emscripten/emcc.bat" \
    "$HOME/emsdk/upstream/emscripten/emcc" \
    "$HOME/emsdk/upstream/emscripten/emcc.bat" \
    "/c/Users/$USER/emsdk/upstream/emscripten/emcc.bat" \
    "/c/emsdk/upstream/emscripten/emcc.bat"; do
    if [ -n "$loc" ] && [ -x "$loc" ]; then
      EMCC="$loc"
      break
    fi
  done
fi
if [ -z "$EMCC" ]; then
  echo "Error: emcc not found. Install Emscripten SDK (https://emscripten.org)" >&2
  echo "and either activate it in this shell (source emsdk_env.sh) or set \$EMSDK." >&2
  exit 1
fi

mkdir -p web/wasm
NATIVE_DIR="$REPO_ROOT/native"
OUT_JS="$REPO_ROOT/web/wasm/maze.js"
WRAPPER="$REPO_ROOT/web/wasm/maze_wrapper.js"

"$EMCC" \
  "$NATIVE_DIR/maze_lib.cpp" \
  -I "$NATIVE_DIR" \
  -DMAZE_STATIC \
  -std=c++17 \
  -O2 \
  -sMODULARIZE=1 \
  -sEXPORT_NAME=createMazeModule \
  -sEXPORTED_FUNCTIONS=_generate_maze,_astar_path,_malloc,_free \
  -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,HEAPU8,HEAP32 \
  -sALLOW_MEMORY_GROWTH=1 \
  -sSTACK_SIZE=256KB \
  -o "$OUT_JS"

if [ -f "$WRAPPER" ]; then
  cat "$WRAPPER" >> "$OUT_JS"
else
  echo "Warning: maze_wrapper.js not found; maze.js may not expose MazeWasm API." >&2
fi

echo "WASM build done: $OUT_JS, $REPO_ROOT/web/wasm/maze.wasm"
