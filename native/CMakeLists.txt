cmake_minimum_required(VERSION 3.15)

project(maze_lib LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(maze_lib SHARED
  maze_lib.cpp
)

target_compile_definitions(maze_lib PRIVATE MAZE_LIB_BUILD)

# Match MSVC's default (symbols hidden unless explicitly exported) on GCC/Clang.
# MAZE_API in maze_lib.h marks the exported C ABI.
set_target_properties(maze_lib PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  POSITION_INDEPENDENT_CODE ON
)

if(MSVC)
  target_compile_options(maze_lib PRIVATE /W4 /permissive-)
else()
  target_compile_options(maze_lib PRIVATE -Wall -Wextra -Wpedantic)
endif()

# query_gpu_info uses DXGI + Direct3D 11 on Windows to enumerate GPUs.
# These come with the Windows SDK, no extra deps.
if(WIN32)
  target_link_libraries(maze_lib PRIVATE dxgi d3d11)
endif()

