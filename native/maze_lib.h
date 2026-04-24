#pragma once

#include <stddef.h>
#include <stdint.h>

#if defined(MAZE_STATIC)
#  define MAZE_API  /* static link (e.g. server executable); no export/import */
#elif defined(_WIN32)
#  ifdef MAZE_LIB_BUILD
#    define MAZE_API __declspec(dllexport)
#  else
#    define MAZE_API __declspec(dllimport)
#  endif
#elif defined(__GNUC__) || defined(__clang__)
#  define MAZE_API __attribute__((visibility("default")))
#else
#  define MAZE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Error codes shared with Dart side.
#define MAZE_SUCCESS 0
#define MAZE_ERROR_INVALID_ARGS -1
#define MAZE_ERROR_BUFFER_TOO_SMALL -2
#define MAZE_ERROR_NO_PATH -3
#define MAZE_ERROR_INTERNAL -4

// Cell wall bit flags (must stay in sync with Dart side).
// 1 = wall up, 2 = wall right, 4 = wall down, 8 = wall left.
enum MazeCellWalls {
  MAZE_WALL_UP = 1,
  MAZE_WALL_RIGHT = 2,
  MAZE_WALL_DOWN = 4,
  MAZE_WALL_LEFT = 8
};

// Generate a random perfect maze using the given seed.
//
// - width, height: maze dimensions in cells (must be > 0).
// - seed: RNG seed; same (width, height, seed) => same maze.
// - out_cells: caller-allocated buffer of length at least width * height.
//              Each cell is encoded as wall bitflags (see MazeCellWalls).
// - out_cells_len: number of bytes available in out_cells.
//
// Returns:
//   MAZE_SUCCESS (0) on success, or a negative MAZE_ERROR_* code.
MAZE_API int generate_maze(
  int width,
  int height,
  int seed,
  uint8_t* out_cells,
  int out_cells_len);

// Compute shortest path using A* on the given maze.
//
// - cells: maze cells as produced by generate_maze (length >= width * height).
// - width, height: maze dimensions.
// - sx, sy: start cell coordinates.
// - tx, ty: target cell coordinates.
// - out_path_xy: caller-allocated buffer of int32_t values,
//                storing (x, y) pairs in sequence.
// - out_path_xy_len: number of int32_t slots available (must be even).
//
// Returns:
//   > 0: number of (x, y) pairs written (path length in cells),
//   MAZE_ERROR_NO_PATH if no path exists,
//   or another negative MAZE_ERROR_* on failure.
MAZE_API int astar_path(
  const uint8_t* cells,
  int width,
  int height,
  int sx,
  int sy,
  int tx,
  int ty,
  int32_t* out_path_xy,
  int out_path_xy_len);

// Query GPU / graphics-adapter information from the OS and write a
// human-readable multi-line summary into out_buffer (UTF-8, null-
// terminated).
//
// On Windows this enumerates all DXGI adapters, reports which adapter
// Windows prefers for high-performance and low-power applications, and
// which adapter a default D3D11 device binds to (what ANGLE/Flutter
// effectively sees with no explicit GPU choice).
//
// On other platforms this writes a short "not supported" line.
//
// Returns the number of bytes written (not including the null
// terminator), or a negative MAZE_ERROR_* code on invalid args.
MAZE_API int query_gpu_info(char* out_buffer, int out_buffer_size);

#ifdef __cplusplus
}  // extern "C"
#endif

