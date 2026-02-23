#include "maze_lib.h"

#include <nlohmann/json.hpp>
#include <httplib.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

// Minimal base64 encode (RFC 4648). Output length is 4 * ((input_len + 2) / 3).
std::string base64_encode(const uint8_t* data, size_t len) {
  static const char table[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  out.reserve(4 * ((len + 2) / 3));
  for (size_t i = 0; i < len; i += 3) {
    uint32_t n = static_cast<uint32_t>(data[i]) << 16;
    if (i + 1 < len) n |= static_cast<uint32_t>(data[i + 1]) << 8;
    if (i + 2 < len) n |= static_cast<uint32_t>(data[i + 2]);
    out += table[(n >> 18) & 63];
    out += table[(n >> 12) & 63];
    out += (i + 1 < len) ? table[(n >> 6) & 63] : '=';
    out += (i + 2 < len) ? table[n & 63] : '=';
  }
  return out;
}

// Minimal base64 decode. Returns empty vector on invalid input.
std::vector<uint8_t> base64_decode(const std::string& encoded) {
  static const int T[256] = {
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63, 52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,
    -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
    -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
  };
  std::vector<uint8_t> out;
  size_t n = encoded.size();
  if (n % 4 != 0) return out;
  out.reserve(3 * (n / 4));
  for (size_t i = 0; i + 4 <= n; i += 4) {
    int a = T[static_cast<unsigned char>(encoded[i])];
    int b = T[static_cast<unsigned char>(encoded[i + 1])];
    int c = T[static_cast<unsigned char>(encoded[i + 2])];
    int d = T[static_cast<unsigned char>(encoded[i + 3])];
    if (a < 0 || b < 0) return {};
    out.push_back(static_cast<uint8_t>((a << 2) | (b >> 4)));
    if (c >= 0) out.push_back(static_cast<uint8_t>((b << 4) | (c >> 2)));
    if (d >= 0) out.push_back(static_cast<uint8_t>((c << 6) | d));
  }
  return out;
}

void set_cors(httplib::Response& res) {
  res.set_header("Access-Control-Allow-Origin", "*");
  res.set_header("Access-Control-Allow-Headers", "Content-Type");
  res.set_header("Access-Control-Allow-Methods", "POST, OPTIONS");
}

void json_error(httplib::Response& res, int status, const std::string& message) {
  set_cors(res);
  res.status = status;
  res.set_content(nlohmann::json{{"error", message}}.dump(), "application/json");
}

}  // namespace

int main(int argc, char** argv) {
  int port = 8080;
  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    if (arg == "--port" && i + 1 < argc) {
      port = std::atoi(argv[++i]);
      if (port <= 0 || port > 65535) port = 8080;
      break;
    }
  }

  httplib::Server svr;

  // CORS preflight
  svr.Options("/api/maze/generate", [](const httplib::Request&, httplib::Response& res) {
    set_cors(res);
    res.status = 204;
  });
  svr.Options("/api/maze/astar", [](const httplib::Request&, httplib::Response& res) {
    set_cors(res);
    res.status = 204;
  });

  // POST /api/maze/generate
  svr.Post("/api/maze/generate", [](const httplib::Request& req, httplib::Response& res) {
    set_cors(res);
    nlohmann::json body;
    try {
      body = nlohmann::json::parse(req.body);
    } catch (const std::exception& e) {
      json_error(res, 400, std::string("Invalid JSON: ") + e.what());
      return;
    }
    int width = body.value("width", 0);
    int height = body.value("height", 0);
    int seed = body.value("seed", 0);
    if (width <= 0 || height <= 0 || width > 500 || height > 500) {
      json_error(res, 400, "width and height must be in range 1..500");
      return;
    }
    int cell_count = width * height;
    std::vector<uint8_t> cells(static_cast<size_t>(cell_count));
    int ret = generate_maze(width, height, seed, cells.data(), cell_count);
    if (ret != MAZE_SUCCESS) {
      json_error(res, 400, "generate_maze failed");
      return;
    }
    std::string cells_b64 = base64_encode(cells.data(), cells.size());
    nlohmann::json out = {
      {"width", width},
      {"height", height},
      {"seed", seed},
      {"cells_base64", cells_b64}
    };
    res.status = 200;
    res.set_content(out.dump(), "application/json");
  });

  // POST /api/maze/astar
  svr.Post("/api/maze/astar", [](const httplib::Request& req, httplib::Response& res) {
    set_cors(res);
    nlohmann::json body;
    try {
      body = nlohmann::json::parse(req.body);
    } catch (const std::exception& e) {
      json_error(res, 400, std::string("Invalid JSON: ") + e.what());
      return;
    }
    int width = body.value("width", 0);
    int height = body.value("height", 0);
    int sx = body.value("sx", -1);
    int sy = body.value("sy", -1);
    int tx = body.value("tx", -1);
    int ty = body.value("ty", -1);
    std::string cells_b64 = body.value("cells_base64", "");
    if (width <= 0 || height <= 0 || width > 500 || height > 500) {
      json_error(res, 400, "width and height must be in range 1..500");
      return;
    }
    int cell_count = width * height;
    std::vector<uint8_t> cells = base64_decode(cells_b64);
    if (static_cast<int>(cells.size()) != cell_count) {
      json_error(res, 400, "cells_base64 length does not match width*height");
      return;
    }
    if (sx < 0 || sx >= width || sy < 0 || sy >= height ||
        tx < 0 || tx >= width || ty < 0 || ty >= height) {
      json_error(res, 400, "start and target coordinates must be in bounds");
      return;
    }
    std::vector<int32_t> path_xy(static_cast<size_t>(cell_count * 2));
    int path_len = astar_path(
        cells.data(), width, height, sx, sy, tx, ty,
        path_xy.data(), static_cast<int>(path_xy.size()));
    if (path_len == MAZE_ERROR_NO_PATH) {
      json_error(res, 400, "no path");
      return;
    }
    if (path_len < 0) {
      json_error(res, 400, "astar_path failed");
      return;
    }
    nlohmann::json path_arr = nlohmann::json::array();
    for (int i = 0; i < path_len; i++) {
      path_arr.push_back(path_xy[2 * i]);
      path_arr.push_back(path_xy[2 * i + 1]);
    }
    nlohmann::json out = {
      {"path_xy", path_arr},
      {"path_len", path_len}
    };
    res.status = 200;
    res.set_content(out.dump(), "application/json");
  });

  std::cout << "Maze server listening on 0.0.0.0:" << port << std::endl;
  if (!svr.listen("0.0.0.0", static_cast<int>(port))) {
    std::cerr << "Failed to bind port " << port << std::endl;
    return 1;
  }
  return 0;
}
