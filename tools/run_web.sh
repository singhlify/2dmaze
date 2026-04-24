#!/usr/bin/env bash
#
# One-command launcher for the Flutter web app.
#
#   ./tools/run_web.sh wasm     - Build C++ to WebAssembly, then run Flutter
#                                 web with MAZE_MODE=wasm. Everything runs
#                                 in the browser. One process.
#
#   ./tools/run_web.sh server   - Build + start the C++ HTTP server on port
#                                 8080, then run Flutter web with
#                                 MAZE_MODE=server pointing at it. Chrome
#                                 opens automatically. Ctrl+C stops both.
#
# Works on Linux, macOS, and Windows git-bash.

set -euo pipefail

MODE="${1:-}"
if [ -z "$MODE" ] || { [ "$MODE" != "wasm" ] && [ "$MODE" != "server" ]; }; then
  cat >&2 <<'USAGE'
Usage: tools/run_web.sh {wasm|server}

  wasm    Builds C++ to WebAssembly, runs Flutter web with MAZE_MODE=wasm.
          Chrome opens automatically. One process.

  server  Builds + starts the C++ HTTP server on :8080, runs Flutter web
          with MAZE_MODE=server pointing at it. Chrome opens automatically.
          Ctrl+C stops both processes.
USAGE
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ "$MODE" = "wasm" ]; then
  echo "==> Building C++ → WebAssembly..."
  ./tools/build_wasm.sh
  echo
  echo "==> Launching Flutter web (WASM mode). Chrome will open."
  echo "    Press Ctrl+C (then 'q' if prompted) to stop."
  echo
  exec flutter run -d chrome --dart-define=MAZE_MODE=wasm
fi

# --- server mode -------------------------------------------------------

echo "==> Building C++ HTTP server..."
cmake -S server_cpp -B server_cpp/build
cmake --build server_cpp/build --config Release

# Find the built binary across generators (MSVC-multiconfig, Ninja, Make).
SERVER=""
for candidate in \
  "server_cpp/build/Release/maze_server.exe" \
  "server_cpp/build/Release/maze_server" \
  "server_cpp/build/maze_server.exe" \
  "server_cpp/build/maze_server"; do
  if [ -x "$candidate" ]; then
    SERVER="$candidate"
    break
  fi
done
if [ -z "$SERVER" ]; then
  echo "Error: maze_server binary not found after build." >&2
  exit 1
fi

echo
echo "==> Starting maze_server at http://localhost:8080 ..."
"$SERVER" --port 8080 &
SERVER_PID=$!

cleanup() {
  echo
  echo "==> Stopping maze_server (PID $SERVER_PID)..."
  # Send SIGTERM, wait briefly, then SIGKILL if still alive.
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$SERVER_PID" 2>/dev/null || true
  fi
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Give the server a moment to bind the port before Flutter tries to call it.
sleep 1

echo
echo "==> Launching Flutter web (server mode). Chrome will open."
echo "    Press Ctrl+C (then 'q' if prompted) to stop both processes."
echo
flutter run -d chrome \
  --dart-define=MAZE_MODE=server \
  --dart-define=MAZE_SERVER_URL=http://localhost:8080
