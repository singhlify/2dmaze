# Project goal

I wanted to find out what Flutter can and cannot do as the UI framework for a GPU-heavy, cross-platform app that also has to call native C++ code and run on the web. This repo is a proof-of-concept I built to answer that question with evidence instead of opinions. The answers live in `docs/report.md`.

The maze game is not the point — it's a controlled experiment designed to force Flutter through the exact technical challenges I wanted to evaluate: native code integration, 2D and 3D rendering on the GPU, custom shaders, and portability between desktop and web.

## What I built

- A **2D maze runner** drawn with Flutter's graphics pipeline (not just widgets).
- A **3D first-person view** of the same maze with textured walls, floor, and ceiling, so the GPU actually has real work to do.
- A **C++ shared library** (`maze_lib.dll` / `libmaze_lib.so` / `libmaze_lib.dylib`) that holds the two computational algorithms — random maze generation (recursive backtracker) and A\* shortest-path — exported with a `extern "C"` boundary. No re-implementation in Dart.
- A **Dart ↔ C++ bridge**: `dart:ffi` on desktop, two independent paths on web (local HTTP server running the same C++, or the same C++ compiled to WebAssembly and called through JS interop).
- A **custom GLSL fragment shader** wired into the Flutter build so the programmable graphics pipeline is actually exercised end-to-end.
- **Keyboard navigation, wall collision, Solve (A\* hint), Toggle Path, Reset, win detection** — enough interactivity that the app is a real interactive workload, not a static demo.

## The nine questions this PoC answers

Each of these has a direct answer with supporting evidence in `docs/report.md`:

1. Can Flutter integrate with native C++ shared libraries on desktop?
2. Can Flutter render non-trivial 2D and 3D graphics using the GPU?
3. What rendering backend does Flutter use on Windows (OpenGL, DirectX, Vulkan, ANGLE)?
4. Does Flutter use the discrete GPU when one is available?
5. Does Flutter support a programmable graphics pipeline and custom shaders?
6. Can Flutter web call C++ algorithms (via a local server, via WebAssembly, or both)?
7. Does Flutter web support WebGL? Does it support WebGPU? What does it actually use?
8. Can Flutter sustain interactive frame rates under a GPU-heavy 3D textured workload?
9. What are the architectural limitations and risks of using Flutter for a large GPU-intensive app?
