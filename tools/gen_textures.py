"""Generate 256x256 placeholder textures for the 3D maze.

These are intentionally larger and patterned so that the GPU actually does
non-trivial texture sampling work (bandwidth + filtering), which is the
whole point of the 3D mode for this PoC.

Writes:
  assets/textures/wall.png     - brick pattern
  assets/textures/floor.png    - checkerboard
  assets/textures/ceiling.png  - grid lines

Uses only the Python standard library (no Pillow required) via the built-in
`zlib` module to write a minimal RGB PNG.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path
from typing import Callable, Tuple

SIZE = 256
RGB = Tuple[int, int, int]


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_rgb_png(path: Path, size: int, shader: Callable[[int, int], RGB]) -> None:
    """Write an RGB PNG using only stdlib (zlib + struct)."""
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter byte: None
        for x in range(size):
            r, g, b = shader(x, y)
            raw.append(r & 0xFF)
            raw.append(g & 0xFF)
            raw.append(b & 0xFF)

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit RGB
    idat = zlib.compress(bytes(raw), 6)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(signature)
        f.write(_png_chunk(b"IHDR", ihdr))
        f.write(_png_chunk(b"IDAT", idat))
        f.write(_png_chunk(b"IEND", b""))


def brick_shader(x: int, y: int) -> RGB:
    brick_w, brick_h = 64, 32
    mortar = 4
    row = y // brick_h
    col_offset = (brick_w // 2) if row % 2 else 0
    local_y = y % brick_h
    local_x = (x + col_offset) % brick_w

    if local_y < mortar or local_x < mortar:
        return (80, 80, 80)  # mortar

    # Brick color with a little variation per brick
    brick_id = (row * 31) ^ ((x + col_offset) // brick_w) * 17
    base = (140, 50, 40)
    jitter = (brick_id % 25) - 12
    return (
        max(0, min(255, base[0] + jitter)),
        max(0, min(255, base[1] + jitter // 2)),
        max(0, min(255, base[2] + jitter // 2)),
    )


def checker_shader(x: int, y: int) -> RGB:
    tile = 32
    if ((x // tile) + (y // tile)) % 2 == 0:
        return (180, 180, 170)
    return (100, 100, 95)


def grid_shader(x: int, y: int) -> RGB:
    cell = 32
    line = 2
    if x % cell < line or y % cell < line:
        return (40, 40, 50)
    return (200, 200, 220)


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    out_dir = project_root / "assets" / "textures"

    jobs = [
        ("wall.png", brick_shader),
        ("floor.png", checker_shader),
        ("ceiling.png", grid_shader),
    ]

    for name, shader in jobs:
        out = out_dir / name
        write_rgb_png(out, SIZE, shader)
        print(f"Wrote {out.relative_to(project_root)} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
