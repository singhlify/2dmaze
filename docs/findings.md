## Overview

This proof-of-concept evaluates Flutter as a Windows-first desktop UI for a local simulator by:

- Offloading maze generation and A* pathfinding to a native C++ DLL loaded via `dart:ffi`.
- Stress‑testing Flutter’s desktop rendering of a dynamic 2D maze (20×20, 50×50, 100×100).
- Investigating what Flutter uses for graphics on Windows and how to validate GPU usage in practice.

All statements below are split into **documentation‑verified** versus **observed / inferred** behavior.

## Rendering Stack on Windows

### Documentation-verified facts

- **Flutter uses Skia as its rendering engine**: The Flutter engine architecture describes Skia as the 2D graphics library responsible for drawing Flutter scenes, and Skia’s own documentation lists Flutter among the products using Skia as its graphics engine.[^flutter-engine-arch][^skia-products]
- **Skia supports multiple GPU backends and ANGLE on Windows**:
  - Skia can target GPU backends such as OpenGL and Vulkan.[^skia-specialized-builds]
  - Skia provides explicit support for ANGLE, an OpenGL ES implementation that translates to Direct3D 9/11 on Windows.[^skia-angle]
  - Building Skia with `skia_use_angle = true` allows configurations like `angle_d3d11_es2` for Direct3D 11 rendering.[^skia-angle]
- **Flutter’s Windows desktop support uses the same engine as mobile**: Flutter’s official desktop docs state that Windows desktop apps are built using the same Flutter framework and engine that power mobile apps, but with a Windows-specific “runner” embedding.[^flutter-desktop]

### Observed / inferred behavior (Windows desktop)

These are *strongly supported in practice* but not exhaustively specified in a single official “Windows rendering backend” document:

- **Skia is the rendering layer Flutter uses on Windows desktop as well**:
  - Since Flutter’s engine uses Skia for rendering across platforms and the Windows embedding does not replace the rendering engine, it is reasonable to treat Skia as the concrete rendering backend on Windows.
- **GPU backend on Windows is typically a Skia GPU backend (OpenGL/ANGLE over Direct3D)**:
  - Skia’s documented Windows configuration emphasizes the ANGLE + Direct3D route for broad GPU compatibility.[^skia-angle]
  - Flutter does not expose a public API to choose a specific Skia backend (e.g., `angle_d3d11_es2` vs native OpenGL) at runtime on Windows.
  - In current stable releases, the default Flutter engine build for Windows is expected to use a GPU-accelerated Skia backend rather than pure software rasterization for normal builds.
- **DirectX usage is likely mediated by ANGLE**:
  - ANGLE translates OpenGL ES calls to Direct3D 9/11 on Windows.[^skia-angle]
  - Because Flutter’s rendering is Skia‑driven and Skia supports ANGLE for Windows GPU acceleration, the most plausible stack is:
    - Flutter framework → Flutter engine → Skia → ANGLE → Direct3D → GPU.

These inferences are consistent with public Skia docs and Flutter’s engine architecture but are not explicitly enumerated as a “formal stack diagram” in Flutter’s Windows docs.

## GPU Acceleration Behavior

### What the docs support

- **Skia is designed to be GPU-accelerated**:
  - Skia provides GPU backends for efficient rendering and is used in other GPU‑accelerated products (Chrome, Android, etc.).[^skia-overview]
- **Flutter’s rendering pipeline is built around GPU usage**:
  - Flutter’s engine converts widget trees into Skia draw commands and sends them to the GPU via Skia’s chosen backend (OpenGL/Vulkan/Metal/ANGLE depending on platform).[^flutter-skia-article]

From this, it is safe to state:

- A normal release‑mode Flutter Windows build **should** be GPU‑accelerated via Skia.
- A fully software‑only path is not the typical configuration and would be considered a fallback (e.g., when no suitable GPU backend is available).

### What cannot be confirmed purely from docs

- There is **no stable, documented Flutter API** that:
  - Reports which exact Skia backend (ANGLE+Direct3D vs native OpenGL vs Vulkan) is in use at runtime on Windows.
  - Reports which physical GPU (integrated vs discrete) the engine bound to.
- Official Flutter docs do not provide a single, Windows‑specific “Skia backend = X” statement for all versions; backend details can change across engine releases.

Therefore, any statement like “Flutter always uses ANGLE + Direct3D 11 on Windows” must be treated as an **implementation detail**, not a hard contract, and should be validated empirically for the specific engine build in use.

## Practical Verification Steps (Discrete GPU, Backend Clues)

The following checks can be used with this PoC to gather evidence about GPU use on Windows:

### 1. Task Manager GPU Engine column

1. Build and run the Flutter Windows app (see top-level `README.md`).
2. Open **Task Manager**.
3. Go to the **Details** tab.
4. Right‑click on the column header → **Select columns…** → enable **GPU**, **GPU engine**.
5. Find the Flutter Windows runner process (e.g., `maze_runner_windows.exe`):
   - If you see something like `GPU 0 - 3D` or `GPU 1 - 3D` in the **GPU engine** column while the app is animating (e.g., moving through the maze), that strongly indicates that:
     - The app is using a 3D GPU engine and
     - The indicated GPU (e.g., `GPU 1`) is doing rendering work.
   - If the engine remains `GPU 0 - Copy` or shows no significant activity, the app may not be GPU‑accelerated or may be using a fallback path.

### 2. GPU utilization graphs

1. In Task Manager, open the **Performance** tab and select each available GPU (integrated and discrete).
2. With the Maze Runner app running a large maze (e.g., 100×100) and moving the player or continuously redrawing:
   - Look for increased utilization in the **3D** graph for one of the GPUs.
   - If you have a discrete GPU, confirm that its utilization rises relative to idle.

### 3. Vendor tooling (optional, not strictly required)

- For NVIDIA, AMD, or Intel discrete GPUs, vendor tools (e.g., NVIDIA’s performance overlay) can show which process is using the GPU and sometimes the graphics API (Direct3D, Vulkan, etc.).
- These tools are **implementation-specific** and not part of Flutter itself but can provide an extra data point about the presence of Direct3D activity originating from the Flutter Windows process.

### 4. Forcing or preferring the discrete GPU (optional)

While not Flutter‑specific, Windows allows you to steer which GPU is used:

1. Open **Settings → System → Display → Graphics** (path may vary slightly by Windows version).
2. Add the Flutter runner executable (built Windows app) to the list.
3. Set its preference to **High performance**.
4. Re‑launch the Maze Runner app and re‑check Task Manager’s **GPU engine** column and utilization graphs.

This does not change Flutter APIs, but it gives additional confidence that the discrete GPU is selected when available.

## Summary for This PoC

From a practical standpoint for the Maze Runner PoC:

- **What we can state confidently**
  - Flutter uses **Skia** as its rendering engine across platforms, including Windows desktop.[^flutter-engine-arch][^skia-products]
  - Skia supports GPU backends and **ANGLE** to translate OpenGL ES calls into **Direct3D 9/11** on Windows.[^skia-angle]
  - The typical Flutter Windows engine build is expected to use a GPU‑accelerated Skia backend rather than software rendering.
  - Using Task Manager’s **GPU engine** column and GPU utilization graphs, we can verify that the Flutter Windows runner process is using a 3D GPU and (if configured) the discrete GPU.

- **What remains implementation detail / requires empirical testing**
  - The exact Skia backend in use on a specific Flutter engine build for Windows (e.g., `angle_d3d11_es2` vs native OpenGL).
  - Whether a given machine’s integrated vs discrete GPU is selected by default without explicit Windows graphics‑settings overrides.

For the simulator UI feasibility study, the practical takeaway is that Flutter’s Windows desktop embedding:

- Is **GPU‑accelerated via Skia** in typical configurations.
- Likely relies on **ANGLE + Direct3D** under the hood on Windows, though exact details are not part of a stable public API.
- Can be validated on target hardware using repeatable steps (Task Manager GPU engine and utilization checks) while this Maze Runner PoC is running with large mazes.

## References

- [^flutter-desktop]: Flutter docs – *Desktop support for Flutter* (`https://docs.flutter.dev/platform-integration/desktop`).
- [^flutter-engine-arch]: Flutter wiki – *The Engine architecture* (`https://github.com/flutter/flutter/wiki/The-Engine-architecture`).
- [^skia-overview]: Skia docs – *Welcome to Skia: The 2D Graphics Library* (`https://skia.org/`).
- [^skia-products]: Skia docs – *Skia is used in Chrome, ChromeOS, Android, Flutter, and others* (`https://skia.org/docs`).
- [^skia-angle]: Skia docs – *ANGLE backend* (`https://skia.org/docs/user/special/angle`).
- [^skia-specialized-builds]: Skia docs – *Specialized Builds* (`https://skia.org/docs/user/special`).
- [^flutter-skia-article]: High‑level article explaining Flutter’s use of Skia and GPU acceleration (e.g., *Flutter & Skia: Driving High‑Performance UI Rendering* – `https://medium.com/@ronakofficial/flutter-skia-driving-high-performance-ui-rendering-fcbc6d8ac9ec`).

