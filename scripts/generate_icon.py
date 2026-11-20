"""Generate a soft gradient app icon with a tapered sound-wave motif, using stdlib only."""
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Assets.xcassets" / "AppIcon.appiconset"
ROOT.mkdir(parents=True, exist_ok=True)


def segment_distance(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - a[0] - t * dx, y - a[1] - t * dy)


def pixel(x, y):
    u, v = x / 1024, y / 1024
    # Rounded square with a subtle violet-to-blue diagonal gradient.
    qx, qy = max(abs(u - .5) - .39, 0), max(abs(v - .5) - .39, 0)
    if math.hypot(qx, qy) > .11:
        return (0, 0, 0, 0)
    mix = .52 * u + .48 * v
    base = (int(102 - 42 * mix), int(111 - 49 * mix), int(192 + 34 * mix))
    glow = max(0, 1 - math.hypot(u - .25, v - .22) / .8) * 28
    base = tuple(min(255, int(c + glow)) for c in base)
    # Speaker body and three decreasing waves.
    polygon = [(u >= .22 and u <= .34 and .43 <= v <= .57),
               (.32 <= u <= .49 and abs(v - .5) <= .19 - (u - .32) * .35)]
    sound = any(polygon)
    for cx, radius, width in [(.45, .19, .018), (.45, .29, .015), (.45, .38, .012)]:
        if u >= cx and abs(math.hypot(u - cx, v - .5) - radius) < width and abs(v - .5) < radius * .87:
            sound = True
    if sound:
        return (248, 248, 255, 255)
    return (*base, 255)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def write_png(path, size):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            rows.extend(pixel((x + .5) * 1024 / size, (y + .5) * 1024 / size))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">2I5B", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


if __name__ == "__main__":
    for n in (16, 32, 64, 128, 256, 512, 1024):
        write_png(ROOT / f"icon-{n}.png", n)
