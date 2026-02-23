cmake_minimum_required(VERSION 3.15)

project(maze_lib LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(maze_lib SHARED
  maze_lib.cpp
)

target_compile_definitions(maze_lib PRIVATE MAZE_LIB_BUILD)

if(MSVC)
  target_compile_options(maze_lib PRIVATE /W4 /permissive-)
else()
  target_compile_options(maze_lib PRIVATE -Wall -Wextra -Wpedantic)
endif()

