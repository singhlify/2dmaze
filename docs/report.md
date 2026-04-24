# Flutter PoC

**Test host:** Windows 11, Flutter 3.38.9 stable (Dart 3.10.8), Intel integrated graphics only (no discrete GPU), MSVC 14.44.

---

## Q1. Can Flutter integrate with native C++ shared libraries on desktop?

**Yes.**

The maze generator and A\* solver (*A\* = a classic shortest-path algorithm over grid cells*) live in `native/maze_lib.cpp` — 310 lines of C++. **CMake** (*a cross-platform build-system generator*) produces `maze_lib.dll` on Windows and `libmaze_lib.so` on Linux.

Flutter's Dart code talks to this library through **`dart:ffi`** (*FFI = Foreign Function Interface: a way for Dart to call C functions in a shared library directly, with no network hop or serialization in between*). The C functions are exported with `extern "C"` (*a C++ keyword that turns off name mangling so other languages can find the function by its plain name*).

The Windows and Linux Flutter runners each pull `native/` in as a CMake subdirectory and install the library next to the app executable automatically — no manual copy step. On Windows the loader finds `maze_lib.dll` next to the `.exe`; on Linux the runner's `RPATH` (*a baked-in library search path*) of `$ORIGIN/lib` finds `libmaze_lib.so`.

**Evidence:** `dart run tools/ffi_smoke.dart` loads the release DLL and exercises both C functions:

```
[ffi_smoke] Loaded ".../build/windows/x64/runner/Release/maze_lib.dll"
[ffi_smoke] generate_maze ok: 10x10, seed=42, 163 us
[ffi_smoke] perfect-maze invariant ok (open edges = 99)
[ffi_smoke] astar_path ok: length=59, 205 us, (0,0) -> (9,9)
[ffi_smoke] error-code contract ok (invalid args -> -1)
[ffi_smoke] ALL PASS
```

**Perf** (`dart run tools/ffi_perf.dart`) — all timings are for the C++ work itself; the Dart→C++ call overhead is too small to measure:

|    size | generate |    A\* | path length |
| ------: | -------: | -----: | ----------: |
|   20×20 |    85 µs | 190 µs |         227 |
|   50×50 |   350 µs | 313 µs |         595 |
| 100×100 |  1.45 ms | 238 µs |        2245 |
| 200×200 |  6.04 ms | 985 µs |        6521 |

---

## Q2. Can Flutter render non-trivial 2D and 3D graphics using the GPU?

**Yes for both.**

The app has a **`View`** toggle between:

- **2D top-down** — drawn with Flutter's built-in `CustomPainter` (*a low-level 2D drawing API: you tell it "draw this line, fill this rect", it hands the calls off to Flutter's renderer which puts them on the GPU*).
- **3D first-person** — built with the `three_js` package (*a Dart port of three.js, the popular 3D scene-graph library*). It has textured walls (1×1×0.1 boxes), floor and ceiling planes, a perspective camera, and emissive yellow floor tiles for the "path hint" overlay.

Both views read the same `MazeState`, so switching between them preserves player position, maze layout, and path snapshot.

**Evidence:** run the release binary and toggle 2D ↔ 3D.

```bash
./build/windows/x64/runner/Release/maze_runner_windows.exe
```

---

## Q3. What rendering backend does Flutter use on Windows?

**Direct3D 11 via ANGLE.** Let's unpack each piece of that:

- **Direct3D 11 (D3D11)** — Microsoft's graphics API, the Windows equivalent of OpenGL/Vulkan. Every recent Windows GPU supports it.
- **ANGLE** — short for *Almost Native Graphics Layer Engine*. A translation library that takes OpenGL ES calls (the mobile subset of OpenGL) and implements them on top of Direct3D 11. Flutter's rendering engine internally talks OpenGL-ish; ANGLE converts those calls to Direct3D so Windows can run them. This way Flutter has a single rendering path that works on many platforms.

**Why not Vulkan?**

Vulkan is a newer, lower-overhead graphics API — also cross-platform (Windows, Linux, Android). Flutter's rendering engine *has* a Vulkan path (it's used on Android). But the **Flutter embedder for Windows is not wired to it.** The engine binary the Flutter tool ships for Windows is configured to use ANGLE (GLES→D3D11) instead. You'd have to build a custom Flutter engine from source with Vulkan enabled to change that, and Flutter does not expose a runtime flag to pick.

The Impeller engine (which is replacing the old Skia+ANGLE path across Flutter, gradually) *does* have a native D3D11 backend on Windows and a native Vulkan backend on Android. On Windows, Impeller's current target remains D3D11 — there is no Vulkan-on-Windows path in Flutter today.

**Evidence:** enumerate the loaded libraries in the running process.

| Module loaded                       | What it is                         |
| ----------------------------------- | ---------------------------------- |
| `d3d11.dll`, `d3d9.dll`, `dxgi.dll` | Direct3D 11 runtime + DXGI (*the Windows service that enumerates GPUs and creates rendering surfaces*) |
| `d3dcompiler_47.dll`                | The HLSL shader compiler — proves the programmable pipeline is in use (more on this in Q5) |
| `libEGL.dll`, `libGLESv2.dll`       | ANGLE (GLES → D3D11 translator)     |
| `flutter_windows.dll`               | Flutter engine                     |

Notable absences:

- No `vulkan-1.dll` → **Vulkan is not used.**
- No Impeller-specific engine modules in the default build.

Reproduce (PowerShell, while the app is open):

```powershell
Get-Process -Name maze_runner_windows |
  Select -Expand Modules |
  ? { $_.ModuleName -match '(?i)(d3d|dxgi|egl|gles|vulkan|impeller)' } |
  Sort ModuleName
```

---

## Q4. Does Flutter use the discrete GPU?

**Yes, when a discrete GPU is reachable through DXGI — but Flutter itself doesn't pick; Windows does. The app ends up on whichever adapter DXGI returns as the default, and a user can steer that to the dGPU through Windows's standard per-app graphics preference.**

**How Flutter ends up on a specific GPU:**

Flutter's Windows rendering stack (Q3) terminates at a Direct3D 11 device. ANGLE / Impeller create that device by calling `D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, ...)` — passing `nullptr` for the adapter argument. Microsoft's documentation for that call is explicit: a `nullptr` adapter means **"the default adapter, which is the first adapter enumerated by `IDXGIFactory1::EnumAdapters`"**. That adapter choice is made by DXGI, not by Flutter.

On a multi-GPU system DXGI picks the default adapter using Windows's own rules:

1. If the user has set a per-app graphics preference in **Settings → System → Display → Graphics**, DXGI returns that GPU.
2. Otherwise, the default is Windows's system-wide graphics preference — which for ordinary windowed apps biases toward the power-saving GPU (the iGPU on a hybrid laptop), unless the app's executable has been classified (e.g. as a game) or the vendor driver injects its own override.

**Evidence — the `[GPU]` log confirms the binding:**

The native library exposes a `query_gpu_info()` function (`native/maze_lib.cpp`) that replicates what ANGLE/Impeller are doing — create a default D3D11 device with a null adapter, then read back which physical adapter that device got. Dart calls it at startup and writes one `[GPU]` block into the terminal / `windows.logs.txt`:

```
[GPU] DXGI adapter enumeration:
  [0] Intel(R) Graphics (vendor=0x8086 device=0x7D45, 128 MB dedicated, 9009 MB shared)
  [1] Microsoft Basic Render Driver (vendor=0x1414 device=0x008C, SOFTWARE)
[GPU]   High-performance preference: Intel(R) Graphics
[GPU]   Low-power        preference: Intel(R) Graphics
[GPU]   Default D3D11 device (what ANGLE/Flutter sees): Intel(R) Graphics (feature level 11_1)
```

The `Default D3D11 device` line is the concrete answer for this process: it names the physical adapter Flutter is rendering on, with no guesswork. On this host (Intel Core Ultra iGPU, device `0x8086 / 0x7D45`) there is one hardware GPU plus the always-present Microsoft software fallback; Flutter correctly binds to the hardware one and ignores the software one. On a hybrid iGPU + dGPU system the same log will list both hardware adapters, the `High-performance preference` line will point to the dGPU, and the `Default D3D11 device` line will show which one Flutter actually received.

**Flutter has no built-in knob to pick the GPU.** The Flutter SDK's public Windows-desktop API surface has no runtime flag, no build flag, and no Dart API to force a specific adapter. Flutter relies on Windows's DXGI default-adapter selection and on user-level Windows settings. This matches Flutter's broader design: the engine treats the host OS as the authority for hardware selection.

**To target the discrete GPU on a hybrid machine:**

1. Open **Settings → System → Display → Graphics**.
2. Click **Browse**, pick `build/windows/x64/runner/Release/maze_runner_windows.exe`.
3. Open the entry → **Options** → **High performance** → **Save**.
4. Re-launch the app.

After that, the `[GPU] Default D3D11 device` line in the log will name the dGPU, and Task Manager → Performance → GPU 1 will show the 3D engine active. No code changes, no custom engine build.

**Implications for a GPU-heavy app:**

- The default (no-override) adapter is typically the iGPU on a hybrid laptop. An app that needs the dGPU can't request it from inside Flutter; it relies on the end user (or an installer setting `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`) to steer Windows.
- The app *can* tell which adapter it ended up on — the `query_gpu_info` output is proof the information is reachable at runtime — but it can't reinitialize Flutter's renderer onto a different adapter without forking the engine.
- For a workstation-class product that ships to users with discrete cards, plan on a first-run installer step that writes the per-app graphics preference, plus an in-app sanity check that logs the bound adapter and warns if a faster one is available.

---

## Q5. Does Flutter support a programmable pipeline / custom shaders?

**Yes, for fragment shaders.**

- **Shader** = a small program that runs on the GPU instead of the CPU. Used for graphics effects (coloring, lighting, post-processing).
- **Fragment shader** (also called pixel shader) = the shader that decides the color of each pixel. This is what Flutter's public API exposes.
- **Vertex shader** = the shader that positions each point of 3D geometry. **Not exposed** by Flutter's public API.
- **Compute shader** = a GPU program for parallel number-crunching unrelated to drawing. **Not exposed** by Flutter's public API.

For this PoC, a custom GLSL (*OpenGL Shading Language — the standard language for OpenGL/Vulkan shaders*) fragment shader lives at `shaders/maze_heatmap.frag` and is declared in `pubspec.yaml` so Flutter compiles it on every build.

**Build-time proof:**

```bash
$ flutter build windows --release
$ xxd -l 4 build/windows/x64/runner/Release/data/flutter_assets/shaders/maze_heatmap.frag
00000000: 1c00 0000 4950 4c52                     ....IPLR
```

The first four bytes of the compiled output are `IPLR` — the magic number for **Impeller** (*Flutter's newer rendering engine*) shader bundles. The build tool invokes Flutter's shader compiler (`impellerc`), which compiles the GLSL source (1,636 bytes) to a platform-agnostic intermediate form (5,408 bytes). At runtime the Flutter engine translates this to:

- **HLSL** on Windows (DirectX's shading language — that's why `d3dcompiler_47.dll` shows up in the Q3 module list)
- **Metal Shading Language** on Apple platforms
- **GLSL ES** on Android and web

All from the same `.frag` source. That's the programmable pipeline end-to-end.

**Runtime:** the Dart API is `ui.FragmentProgram.fromAsset(...)`, which returns a shader you can bind uniforms to (`float`, `vec2`, textures) and draw with `CustomPainter`. Takes ~30 lines of Dart.

**Caveats to plan around:**

- Fragment shaders only. Vertex shading is not exposed from user code — any 3D geometry shading happens through the scene graph (`three_js` in our case) or inside Flutter's engine.
- No compute shaders. GPU compute (e.g., physics solvers) would need to be done through an FFI plugin, not Flutter's shader API.

---

## Q6. Can Flutter web work with C++ algorithms?

**Yes, via two independent paths. Both build and work end-to-end.**

- **WebAssembly (WASM)** — *a portable binary instruction format that browsers run at near-native speed, originally designed for C/C++ code to run alongside JavaScript.* We use **Emscripten** (*the Clang-based toolchain that compiles C/C++ to WASM*) to compile the same `native/maze_lib.cpp` into a browser module.

  ```bash
  $ ./tools/build_wasm.sh
  # produces:
  #   web/wasm/maze.wasm     14,769 bytes  (the compiled C++ code)
  #   web/wasm/maze.js       12,899 bytes  (glue code that loads it)
  ```

  The Dart side (`lib/maze/web_wasm/maze_wasm_interop.dart`) calls into `window.MazeWasm.initMazeWasm / generateMaze / astarPath` via `dart:js_interop` (*Dart's API for calling JavaScript functions from Dart*).

- **HTTP server** — a separate C++ process under `server_cpp/` that statically links the same `maze_lib.cpp` source and exposes `/api/maze/generate` and `/api/maze/astar` as HTTP endpoints. The Flutter web app calls those endpoints over normal fetch/XHR. Launch both processes with `./tools/run_web.sh server` (or `.\tools\run_web.ps1 server` on Windows PowerShell).

Select which backend the web build uses via a build flag:

```bash
flutter build web --release --dart-define=MAZE_MODE=wasm
# or
flutter build web --release --dart-define=MAZE_MODE=server
```

The **same C++ source** therefore runs in three environments with no modifications: Windows DLL, Linux `.so`, and browser WASM.

---

## Q7. Does Flutter web support WebGL? WebGPU?

**Flutter web uses WebGL 2 under the hood. It does not use WebGPU in the stable channel (Flutter 3.38.9 as tested).**

Terms first:

- **WebGL** — a JavaScript API for rendering 3D graphics in a browser. WebGL 2 = the current widely-supported version, available in ~all modern browsers.
- **WebGPU** — a newer browser graphics API, the browser equivalent of Vulkan/D3D12. More modern, lower-overhead. Still rolling out in browsers (Chrome full support, Firefox/Safari partial as of early 2026).
- **CanvasKit** — Google's 2D graphics library Skia compiled to WebAssembly. This is what Flutter web uses to draw; it talks to the browser via WebGL 2.
- **Skwasm** — a newer, Flutter-specific Skia-in-WASM renderer. The long-term path to WebGPU on Flutter web.

**Evidence from the build output** (`build/web/` after `flutter build web --release`):

- `flutter_bootstrap.js` hard-codes `"renderer":"canvaskit"`.
- `grep -ci webgpu build/web/flutter*.js` → **zero matches.** The built bundle has no way to initialize WebGPU even if the browser supports it.
- `three_js` on web also uses WebGL 2 (via an ANGLE plugin).

**About Skwasm (and the future WebGPU path):** attempting to build this codebase with Flutter's newer WASM-compiled renderer fails:

```
$ flutter build web --wasm
Found incompatibilities with WebAssembly.
  package:maze_runner_windows/native/maze_ffi.dart 1:1 —
    'dart:ffi' can't be imported when compiling to Wasm.
```

Our `maze_ffi.dart` file is only reached on desktop platforms via conditional imports, but Flutter's WASM compiler scans the entire source tree. To adopt Skwasm (and eventually WebGPU) later, any `dart:ffi`-using code would have to move into a separately-compiled package that the web target doesn't pull in.

---

## Q8. Can Flutter handle GPU-heavy workloads (3D textured)?

**Yes at small scene sizes; no at 100×100+. The bottleneck is scene-graph complexity, not compute.**

The 3D mode has textured walls, floor, and ceiling (256×256 procedural PNGs repeating per cell), a perspective camera, smooth tile-based animated movement (~120 ms ease per step), and an emissive floor-tile overlay for the A* path hint. Every `[FPS]` line below is straight from the in-app logger (`lib/ui/maze_screen.dart` emits it once per second with context), running on an Intel integrated GPU on Meteor Lake (device `0x8086 / 0x7D45`).

**Measured — 20×20 maze, three backends, same host:**

| Backend | Build | View | Path | n | min | max | avg FPS |
|---|---|---|---:|---:|---:|---:|---:|
| Windows FFI | release | 2D | off | 4  | 39.7 | 53.1 | **45.8** |
| Windows FFI | release | 2D | on  | 19 | 35.4 | 52.6 | **45.0** |
| Windows FFI | release | 3D | off | 2  | 27.6 | 31.9 | **29.8** |
| Windows FFI | release | 3D | on  | 43 | 21.7 | 46.3 | **32.3** |
| Web Server  | debug   | 2D | off | 3  | 31.5 | 49.4 | **37.6** |
| Web Server  | debug   | 2D | on  | 12 | 18.4 | 57.1 | **36.8** |
| Web Server  | debug   | 3D | on  | 60 | 9.4  | 58.0 | **34.4** |
| Web WASM    | debug   | 2D | off | 5  | 56.0 | 59.1 | **57.2** |
| Web WASM    | debug   | 2D | on  | 25 | 3.4  | 53.1 | **29.3** |
| Web WASM    | debug   | 3D | on  | 58 | 11.8 | 50.0 | **27.1** |

**Takeaways from the 20×20 numbers:**

- **Windows release (FFI)** is the steadiest frame pacing: its 3D minimum is ~22 FPS; the web modes both dip to single-digit FPS under load. Interactive end-to-end.
- **Web WASM in idle 2D** hits 60 FPS. The moment a path overlay is added, it drops to ~29 FPS — the overlay adds ~100 extra draw calls per frame, and CanvasKit + the browser event loop magnifies any stutter.
- **Web Server mode** has the same rendering path as WASM (both are CanvasKit + `three_js`), so its FPS is in the same range; the HTTP round-trip only shows up in the `solve` / `new_maze` timings (~400 ms per request vs ~0.1 ms for FFI or ~1 ms for WASM).
- Web runs are in Flutter's **debug** mode (that's what `flutter run -d chrome` defaults to). A release web build would close part of the gap, but 3D at 20×20 was already "borderline smooth" in debug — any release lift is a bonus, not a fix.

**Measured vs observed at larger sizes:**

50×50 and 100×100 weren't captured in the log file (the test runs stayed on 20×20), but the behaviour at 100×100 was observed directly on the same host:

- **100×100 in 3D on Windows FFI release: effectively unusable.** The app nearly hangs — frame times climb into hundreds of milliseconds and the tile-step animation stops being interactive. This matches what the architecture predicts: a 100×100 maze generates ~400 wall box meshes plus the floor / ceiling / target / optional path overlay. `three_js` issues one draw call per mesh without batching, so the per-frame CPU cost of walking the scene graph becomes the bottleneck long before the GPU itself is saturated.
- The 2D view at 100×100 stays interactive — Flutter's `Canvas` is a retained-ops path that Skia can batch internally.
- Extrapolating from this and from the 20×20 ranking, the qualitative ordering at larger sizes is **Windows FFI > WASM > Web Server**, with all three modes becoming unusable in 3D once the wall count crosses a few thousand.

**Where the budget goes (confirmed by the other evidence):**

- Maze generation / A\* compute is effectively free: `[EVENT] event=solve ... solveMs=0.034` on Windows FFI at 20×20, up to ~1–7 ms at 100–200×100–200 (see Q1 perf table). Compute is not the bottleneck, even at 200×200.
- HTTP round-trip adds ~400 ms per `new_maze` / `solve` call in server mode but does not touch the render loop.
- The render loop's per-frame cost is dominated by `three_js` scene-graph traversal and draw-call emission. Flutter's own 2D rendering is cheap.

**Headline answer for a GPU-heavy UI:**

Flutter can drive interactive 3D rendering at small scene complexity (~100 meshes) on an integrated GPU, at ~30 FPS with no headroom to spare. It cannot hold interactive FPS once the scene approaches ~10,000 objects in `three_js` on the same GPU. For a visualization-heavy UI (many meshes, continuous motion), you need either a batching-aware first-party renderer (plan on building one) or a discrete GPU — and still expect `three_js` to be the constraint, not Flutter's engine. The compute path (Dart ↔ C++ over FFI or WASM) is never the bottleneck.

---

## Q9. Architectural limitations and risks for a large-scale GPU-intensive application

Not evidence per se — the things I learned that would shape a "should I commit to Flutter" decision:

- **No Vulkan on Windows.** See Q3. Flutter's Windows rendering path is ANGLE→D3D11 (now) or Impeller D3D11/D3D12 (future). If cross-platform Vulkan parity with Linux matters to you, Flutter does not provide it without a custom engine build.
- **No GPU adapter selection API.** On a workstation with multiple GPUs (e.g., Intel + Quadro), Flutter takes whatever Windows hands it. Users must manually set "High performance" per app in Windows Graphics Settings to steer to the dGPU.
- **Fragment shaders only.** The public `FragmentProgram` API does not expose vertex shading (for custom geometry deformation) or compute shading (for GPU-parallel work unrelated to drawing). For custom visualizations like isosurfaces, vector fields, or per-vertex displacement, plan on either `three_js` or a first-party renderer.
- **`three_js` is community software.** It has real rough edges — its scene field is declared immutable after first assignment (so you mutate the scene graph in place rather than replacing it), and its widget is not reliably re-initializable (I keep the 2D and 3D views alive simultaneously in an `IndexedStack` to avoid tearing down and re-creating the 3D engine on every toggle). For a long-lived product you'd want a thin first-party renderer on top of Flutter's own scene primitives, or a licensed engine.
- **Impeller on Windows is still maturing.** The current default backend (ANGLE) is stable but adds a translation layer. Impeller's native D3D11/D3D12 backends promise lower CPU overhead but have had regressions on integrated-GPU machines in recent Flutter versions. Plan to re-evaluate when Impeller becomes the default.
- **WebAssembly compute is constrained.** WASM is single-threaded unless you invest in Web Workers (*browser threads*), memory is capped, and SIMD (*single-instruction-multiple-data vectorization*) requires opt-in build flags. If the web target has heavy compute, the HTTP-to-cloud-backend mode is the realistic story; WASM is a fallback for low-latency / offline use cases.
- **`dart:ffi` incompatibility with Skwasm.** Flutter's future WASM renderer (the WebGPU path) cannot ingest any `dart:ffi`-using code anywhere in the source tree. Long-term web strategy needs the FFI layer in a separate package, gated by compile-time conditional imports.
