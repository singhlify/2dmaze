# Build C++ maze_lib to WebAssembly using Emscripten.
# Requires Emscripten SDK: https://emscripten.org/docs/getting_started/downloads.html
# Run from repo root: .\tools\build_wasm.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path "$RepoRoot\native\maze_lib.cpp")) {
    Write-Error "Repo root not found (expected native/maze_lib.cpp). Repo root: $RepoRoot"
}

$emcc = Get-Command emcc -ErrorAction SilentlyContinue
if (-not $emcc) {
    Write-Error "emcc not in PATH. Install Emscripten SDK and run 'emsdk activate'."
}

$OutDir = Join-Path $RepoRoot "web" "wasm"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$NativeDir = Join-Path $RepoRoot "native"
$OutJs = Join-Path $OutDir "maze.js"
$OutWasm = Join-Path $OutDir "maze.wasm"

# Build with MAZE_STATIC so no DLL export macros; export C symbols via Emscripten.
# MODULARIZE=1 + EXPORT_NAME so the script defines createMazeModule() (async factory).
# EXPORTED_FUNCTIONS: C entry points + _malloc,_free for buffer allocation from JS.
& emcc "$NativeDir\maze_lib.cpp" -I "$NativeDir" -DMAZE_STATIC -std=c++17 -O2 `
    -sMODULARIZE=1 -sEXPORT_NAME=createMazeModule `
    -sEXPORTED_FUNCTIONS=_generate_maze,_astar_path,_malloc,_free `
    -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,HEAPU8,HEAP32 -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=256KB -o "$OutJs"

if ($LASTEXITCODE -ne 0) {
    Write-Error "emcc failed with exit code $LASTEXITCODE"
}

# Append our wrapper that exposes window.MazeWasm (initMazeWasm, generateMaze, astarPath, createUint8Array)
$WrapperPath = Join-Path $OutDir "maze_wrapper.js"
if (Test-Path $WrapperPath) {
    Add-Content -Path $OutJs -Value (Get-Content -Raw $WrapperPath)
} else {
    Write-Warning "maze_wrapper.js not found; maze.js may not expose MazeWasm API. Create web/wasm/maze_wrapper.js"
}

Write-Host "WASM build done: $OutJs, $OutWasm"
