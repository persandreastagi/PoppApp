#!/usr/bin/env python3
"""Genera le icone PNG dell'app (nessuna dipendenza esterna).

Uso: python3 tools/make_icons.py
"""
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def write_png(path, width, height, pixel_fn):
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0
        for x in range(width):
            raw.extend(pixel_fn(x, y))
    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def mix(c1, c2, t):
    return tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))


def rounded_rect(x, y, cx, cy, w, h, r):
    """Distanza con segno (<=0 = dentro) da un rettangolo con angoli arrotondati."""
    dx = abs(x - cx) - (w / 2 - r)
    dy = abs(y - cy) - (h / 2 - r)
    ax, ay = max(dx, 0.0), max(dy, 0.0)
    return math.hypot(ax, ay) + min(max(dx, dy), 0.0) - r


def make_icon(size, path, padding_ratio=0.0):
    """Icona: sfondo sfumato + biberon bianco stilizzato."""
    top = (0x7C, 0x6C, 0xF0)
    bottom = (0x4F, 0x9D, 0xF7)
    white = (255, 255, 255)

    s = size
    pad = s * padding_ratio
    inner = s - 2 * pad

    # geometria del biberon, in coordinate 0..1 dell'area interna
    body_w, body_h = 0.40, 0.46
    body_cx, body_cy = 0.50, 0.635
    neck_w, neck_h = 0.24, 0.075
    neck_cy = 0.345
    teat_cy, teat_r = 0.235, 0.105

    def px(x, y):
        t = y / max(s - 1, 1)
        bg = mix(top, bottom, t)

        u = (x + 0.5 - pad) / inner
        v = (y + 0.5 - pad) / inner
        aa = 1.5 / inner  # antialiasing

        if not (0 <= u <= 1 and 0 <= v <= 1):
            return bytes(bg) + b"\xff"

        d_body = rounded_rect(u, v, body_cx, body_cy, body_w, body_h, 0.085)
        d_neck = rounded_rect(u, v, body_cx, neck_cy, neck_w, neck_h, 0.03)
        d_teat = math.hypot(u - body_cx, (v - teat_cy) * 0.85) - teat_r
        d = min(d_body, d_neck, d_teat)

        cov = max(0.0, min(1.0, 0.5 - d / (2 * aa)))
        col = mix(bg, white, cov)

        # tacche di misurazione sul corpo
        if cov > 0.5:
            for i, line_v in enumerate((0.545, 0.635, 0.725)):
                half_len = (0.085, 0.115, 0.085)[i]
                if abs(v - line_v) < 0.011 and abs(u - (body_cx + 0.045)) < half_len / 2 + 0.02:
                    if u > body_cx - 0.09:
                        col = mix(col, bg, 0.75)
        return bytes(col) + b"\xff"

    write_png(path, s, s, px)
    print(f"scritto {path.relative_to(ROOT)} ({s}x{s})")


if __name__ == "__main__":
    icons = ROOT / "icons"
    icons.mkdir(exist_ok=True)
    # icona maskable/standard per il manifest
    make_icon(512, icons / "icon-512.png")
    make_icon(192, icons / "icon-192.png")
    # apple-touch-icon: iOS applica da solo la maschera arrotondata
    make_icon(180, icons / "apple-touch-icon.png")
