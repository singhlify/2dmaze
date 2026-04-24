# One-command launcher for the Flutter web app (PowerShell).
#
#   .\tools\run_web.ps1 wasm     - Build C++ to WebAssembly, run Flutter
#                                  web with MAZE_MODE=wasm. One process.
#
#   .\tools\run_web.ps1 server   - Build + start the C++ HTTP server on
#                                  port 8080, run Flutter web with
#                                  MAZE_MODE=server pointing at it.
#                                  Ctrl+C stops both.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("wasm", "server")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if ($Mode -eq "wasm") {
    Write-Host "==> Building C++ -> WebAssembly..." -ForegroundColor Cyan
    & "$PSScriptRoot\build_wasm.ps1"

    Write-Host ""
    Write-Host "==> Launching Flutter web (WASM mode). Chrome will open." -ForegroundColor Cyan
    Write-Host "    Press Ctrl+C (then 'q' if prompted) to stop."
    Write-Host ""
    flutter run -d chrome --dart-define=MAZE_MODE=wasm
    exit $LASTEXITCODE
}

# --- server mode -------------------------------------------------------

Write-Host "==> Building C++ HTTP server..." -ForegroundColor Cyan
cmake -S server_cpp -B server_cpp/build
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
cmake --build server_cpp/build --config Release
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

$serverExe = Join-Path $RepoRoot "server_cpp\build\Release\maze_server.exe"
if (-not (Test-Path $serverExe)) {
    throw "maze_server.exe not found at $serverExe"
}

Write-Host ""
Write-Host "==> Starting maze_server at http://localhost:8080 ..." -ForegroundColor Cyan
$serverProc = Start-Process -FilePath $serverExe `
    -ArgumentList "--port", "8080" `
    -PassThru -NoNewWindow

try {
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "==> Launching Flutter web (server mode). Chrome will open." -ForegroundColor Cyan
    Write-Host "    Press Ctrl+C (then 'q' if prompted) to stop both processes."
    Write-Host ""
    flutter run -d chrome `
        --dart-define=MAZE_MODE=server `
        --dart-define=MAZE_SERVER_URL=http://localhost:8080
}
finally {
    if ($serverProc -and -not $serverProc.HasExited) {
        Write-Host ""
        Write-Host "==> Stopping maze_server (PID $($serverProc.Id))..." -ForegroundColor Yellow
        Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    }
}
