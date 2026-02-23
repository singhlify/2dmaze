#include "maze_lib.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <queue>
#include <random>
#include <utility>
#include <vector>

namespace {

inline int index_of(int x, int y, int width) {
  return y * width + x;
}

bool in_bounds(int x, int y, int width, int height) {
  return x >= 0 && x < width && y >= 0 && y < height;
}

// Internal helper: can move between two adjacent cells given wall flags.
bool can_move_between(
  int x,
  int y,
  int nx,
  int ny,
  int width,
  int height,
  const uint8_t* cells) {
  if (!in_bounds(x, y, width, height) || !in_bounds(nx, ny, width, height)) {
    return false;
  }
  const int idx = index_of(x, y, width);
  const int nidx = index_of(nx, ny, width);
  const uint8_t cell = cells[idx];
  const uint8_t ncell = cells[nidx];

  if (nx == x + 1 && ny == y) {
    // Right
    if (cell & MAZE_WALL_RIGHT) return false;
    if (ncell & MAZE_WALL_LEFT) return false;
    return true;
  }
  if (nx == x - 1 && ny == y) {
    // Left
    if (cell & MAZE_WALL_LEFT) return false;
    if (ncell & MAZE_WALL_RIGHT) return false;
    return true;
  }
  if (nx == x && ny == y + 1) {
    // Down
    if (cell & MAZE_WALL_DOWN) return false;
    if (ncell & MAZE_WALL_UP) return false;
    return true;
  }
  if (nx == x && ny == y - 1) {
    // Up
    if (cell & MAZE_WALL_UP) return false;
    if (ncell & MAZE_WALL_DOWN) return false;
    return true;
  }

  // Diagonals not supported.
  return false;
}

}  // namespace

int generate_maze(
  int width,
  int height,
  int seed,
  uint8_t* out_cells,
  int out_cells_len) {
  if (width <= 0 || height <= 0 || !out_cells) {
    return MAZE_ERROR_INVALID_ARGS;
  }

  const int cell_count = width * height;
  if (out_cells_len < cell_count) {
    return MAZE_ERROR_BUFFER_TOO_SMALL;
  }

  // Initialize all cells with all four walls present.
  std::vector<uint8_t> cells(cell_count, static_cast<uint8_t>(
    MAZE_WALL_UP | MAZE_WALL_RIGHT | MAZE_WALL_DOWN | MAZE_WALL_LEFT));

  std::vector<bool> visited(cell_count, false);
  std::vector<std::pair<int, int>> stack;
  stack.reserve(cell_count);

  std::mt19937 rng(static_cast<uint32_t>(seed));

  auto neighbors = [&](int x, int y) {
    std::vector<std::pair<int, int>> result;
    result.reserve(4);
    if (in_bounds(x + 1, y, width, height)) result.emplace_back(x + 1, y);
    if (in_bounds(x - 1, y, width, height)) result.emplace_back(x - 1, y);
    if (in_bounds(x, y + 1, width, height)) result.emplace_back(x, y + 1);
    if (in_bounds(x, y - 1, width, height)) result.emplace_back(x, y - 1);
    return result;
  };

  auto carve_between = [&](int x, int y, int nx, int ny) {
    const int idx = index_of(x, y, width);
    const int nidx = index_of(nx, ny, width);
    if (nx == x + 1 && ny == y) {
      // Carve right
      cells[idx] &= static_cast<uint8_t>(~MAZE_WALL_RIGHT);
      cells[nidx] &= static_cast<uint8_t>(~MAZE_WALL_LEFT);
    } else if (nx == x - 1 && ny == y) {
      // Carve left
      cells[idx] &= static_cast<uint8_t>(~MAZE_WALL_LEFT);
      cells[nidx] &= static_cast<uint8_t>(~MAZE_WALL_RIGHT);
    } else if (nx == x && ny == y + 1) {
      // Carve down
      cells[idx] &= static_cast<uint8_t>(~MAZE_WALL_DOWN);
      cells[nidx] &= static_cast<uint8_t>(~MAZE_WALL_UP);
    } else if (nx == x && ny == y - 1) {
      // Carve up
      cells[idx] &= static_cast<uint8_t>(~MAZE_WALL_UP);
      cells[nidx] &= static_cast<uint8_t>(~MAZE_WALL_DOWN);
    }
  };

  // Recursive backtracker implemented iteratively.
  int start_x = 0;
  int start_y = 0;
  stack.emplace_back(start_x, start_y);
  visited[index_of(start_x, start_y, width)] = true;

  while (!stack.empty()) {
    int x = stack.back().first;
    int y = stack.back().second;

    auto nbrs = neighbors(x, y);
    std::vector<std::pair<int, int>> unvisited;
    for (const auto& n : nbrs) {
      int nx = n.first;
      int ny = n.second;
      if (!visited[index_of(nx, ny, width)]) {
        unvisited.emplace_back(nx, ny);
      }
    }

    if (unvisited.empty()) {
      stack.pop_back();
      continue;
    }

    std::uniform_int_distribution<std::size_t> dist(
      0, unvisited.size() - 1);
    auto next = unvisited[dist(rng)];
    int nx = next.first;
    int ny = next.second;

    carve_between(x, y, nx, ny);
    visited[index_of(nx, ny, width)] = true;
    stack.emplace_back(nx, ny);
  }

  // Copy to caller buffer.
  std::copy(cells.begin(), cells.end(), out_cells);
  return MAZE_SUCCESS;
}

int astar_path(
  const uint8_t* cells,
  int width,
  int height,
  int sx,
  int sy,
  int tx,
  int ty,
  int32_t* out_path_xy,
  int out_path_xy_len) {
  if (!cells || !out_path_xy || width <= 0 || height <= 0) {
    return MAZE_ERROR_INVALID_ARGS;
  }
  if (!in_bounds(sx, sy, width, height) ||
      !in_bounds(tx, ty, width, height)) {
    return MAZE_ERROR_INVALID_ARGS;
  }
  if (out_path_xy_len < 2) {
    return MAZE_ERROR_BUFFER_TOO_SMALL;
  }

  const int node_count = width * height;
  const float inf = std::numeric_limits<float>::infinity();
  std::vector<float> g_score(node_count, inf);
  std::vector<float> f_score(node_count, inf);
  std::vector<int> came_from(node_count, -1);

  auto heuristic = [&](int x, int y) -> float {
    return static_cast<float>(std::abs(x - tx) + std::abs(y - ty));
  };

  struct QueueNode {
    float f;
    int idx;
  };
  struct CompareNode {
    bool operator()(const QueueNode& a, const QueueNode& b) const {
      return a.f > b.f;
    }
  };

  std::priority_queue<QueueNode, std::vector<QueueNode>, CompareNode> open;
  std::vector<bool> in_open(node_count, false);
  std::vector<bool> closed(node_count, false);

  const int start_idx = index_of(sx, sy, width);
  const int target_idx = index_of(tx, ty, width);

  g_score[start_idx] = 0.0f;
  f_score[start_idx] = heuristic(sx, sy);
  open.push({f_score[start_idx], start_idx});
  in_open[start_idx] = true;

  const int dirs[4][2] = {
    {1, 0},
    {-1, 0},
    {0, 1},
    {0, -1},
  };

  bool found = false;

  while (!open.empty()) {
    const int current = open.top().idx;
    open.pop();

    if (closed[current]) {
      continue;
    }
    closed[current] = true;

    if (current == target_idx) {
      found = true;
      break;
    }

    const int cx = current % width;
    const int cy = current / width;

    for (const auto& d : dirs) {
      const int nx = cx + d[0];
      const int ny = cy + d[1];
      if (!in_bounds(nx, ny, width, height)) {
        continue;
      }

      if (!can_move_between(cx, cy, nx, ny, width, height, cells)) {
        continue;
      }

      const int nidx = index_of(nx, ny, width);
      if (closed[nidx]) {
        continue;
      }

      const float tentative_g = g_score[current] + 1.0f;
      if (tentative_g < g_score[nidx]) {
        came_from[nidx] = current;
        g_score[nidx] = tentative_g;
        f_score[nidx] = tentative_g + heuristic(nx, ny);
        open.push({f_score[nidx], nidx});
        in_open[nidx] = true;
      }
    }
  }

  if (!found) {
    return MAZE_ERROR_NO_PATH;
  }

  // Reconstruct path from target back to start.
  std::vector<int> path_indices;
  int current = target_idx;
  while (current != -1) {
    path_indices.push_back(current);
    if (current == start_idx) {
      break;
    }
    current = came_from[current];
  }

  if (path_indices.empty() || path_indices.back() != start_idx) {
    return MAZE_ERROR_INTERNAL;
  }

  std::reverse(path_indices.begin(), path_indices.end());

  const int path_len = static_cast<int>(path_indices.size());
  const int required_slots = path_len * 2;
  if (out_path_xy_len < required_slots) {
    return MAZE_ERROR_BUFFER_TOO_SMALL;
  }

  for (int i = 0; i < path_len; ++i) {
    const int idx = path_indices[i];
    const int x = idx % width;
    const int y = idx / width;
    out_path_xy[2 * i] = static_cast<int32_t>(x);
    out_path_xy[2 * i + 1] = static_cast<int32_t>(y);
  }

  return path_len;
}

