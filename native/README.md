# Native C++ Maze Library (`maze_lib`)

This directory contains the C++ implementation of the maze generation and A* shortest-path algorithms, built as a shared library (`maze_lib.dll`) for Windows.

## Files

- `maze_lib.h` — C ABI header, error codes, and function declarations.
- `maze_lib.cpp` — implementation of maze generation and A*.
- `CMakeLists.txt` — CMake configuration to build the DLL.

## Exported C API

```c
int generate_maze(
  int width,
  int height,
  int seed,
  uint8_t* out_cells,
  int out_cells_len);

int astar_path(
  const uint8_t* cells,
  int width,
  int height,
  int sx,
  int sy,
  int tx,
  int ty,
  int32_t* out_path_xy,
  int out_path_xy_len);
```

### Error Codes

- `0` — success.
- `-1` — invalid arguments.
- `-2` — output buffer too small.
- `-3` — no path exists between start and target.
- `-4` — internal error.

### Maze Cell Encoding

Each cell in `out_cells` is a single `uint8_t` where wall presence is encoded as bit flags:

- `1` — wall up
- `2` — wall right
- `4` — wall down
- `8` — wall left

The grid is stored in row-major order: index = `y * width + x`.

### Path Encoding

`astar_path` writes a sequence of `(x, y)` integer pairs into `out_path_xy`, representing a shortest path from start to target (inclusive). The return value on success is the number of cells in the path.

## Building the DLL (Windows)

Prerequisites:

- CMake 3.15+
- A C++17-capable compiler (e.g., MSVC via Visual Studio)

Example using an out-of-source build with Ninja:

```bash
cd native
cmake -S . -B build -G "Ninja"
cmake --build build --config Release
```

The resulting DLL will typically be located at:

- `native/build/Release/maze_lib.dll` (for a Release build)

Copy `maze_lib.dll` next to the Flutter Windows runner executable (see the top-level README for exact paths) so that `dart:ffi` can load it with `DynamicLibrary.open("maze_lib.dll")`.

