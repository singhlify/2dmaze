cmake_minimum_required(VERSION 3.15)
project(maze_server LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SERVER_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(NATIVE_DIR ${SERVER_DIR}/../native)

add_executable(maze_server
  maze_main.cpp
  ${NATIVE_DIR}/maze_lib.cpp
)

target_include_directories(maze_server PRIVATE
  ${NATIVE_DIR}
  ${SERVER_DIR}/third_party
)

# Static link: maze_lib symbols are internal to the executable (no DLL export).
target_compile_definitions(maze_server PRIVATE MAZE_STATIC)

if(MSVC)
  target_compile_options(maze_server PRIVATE /W4 /permissive-)
else()
  target_compile_options(maze_server PRIVATE -Wall -Wextra -Wpedantic)
endif()

# Windows: link Winsock for httplib
if(WIN32)
  target_link_libraries(maze_server PRIVATE ws2_32)
endif()
