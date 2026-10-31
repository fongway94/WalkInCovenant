"""Canvas — pixel primitives with a deterministic RNG.

Everything is integer grid coordinates. There is no anti-aliasing anywhere in
this file and there never should be: sub-pixel blending is what makes generated
art look soft and amateur next to real pixel art.

Determinism matters. Covenant's field.js used a hash() function specifically so
tile texture "never crawls" between frames. Same principle: pass a seed derived
from the asset name and the output is byte-identical on every run, so git diffs
stay clean and the art director can trust what they see.
"""

import random
from PIL import Image

from .palette import hexrgb, OUTLINE, SHADOW


class Canvas:
    """A 2D grid of hex-colour-or-None pixels."""

    __slots__ = ("w", "h", "buf")

    def __init__(self, w, h, fill=None):
        self.w, self.h = int(w), int(h)
        self.buf = [[fill] * self.w for _ in range(self.h)]

    # ── basic access ────────────────────────────────────────────────────
    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def get(self, x, y):
        return self.buf[y][x] if self.inside(x, y) else None

    def px(self, x, y, col):
        if col is not None and self.inside(x, y):
            self.buf[y][x] = col
        return self

    def clear_px(self, x, y):
        if self.inside(x, y):
            self.buf[y][x] = None

    def rect(self, x, y, w, h, col):
        for yy in range(int(y), int(y + h)):
            row = self.buf[yy] if 0 <= yy < self.h else None
            if row is None:
                continue
            for xx in range(int(x), int(x + w)):
                if 0 <= xx < self.w:
                    row[xx] = col
        return self

    def frame(self, x, y, w, h, col):
        self.hline(x, y, w, col); self.hline(x, y + h - 1, w, col)
        self.vline(x, y, h, col); self.vline(x + w - 1, y, h, col)
        return self

    def hline(self, x, y, w, col):
        if 0 <= y < self.h:
            row = self.buf[y]
            for xx in range(int(x), int(x + w)):
                if 0 <= xx < self.w:
                    row[xx] = col
        return self

    def vline(self, x, y, h, col):
        for yy in range(int(y), int(y + h)):
            if 0 <= yy < self.h and 0 <= x < self.w:
                self.buf[yy][x] = col
        return self

    def line(self, x0, y0, x1, y1, col):
        """Bresenham. Integer pixels only."""
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.px(x0, y0, col)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy
        return self

    def ellipse(self, cx, cy, rx, ry, col, fill=False):
        cx, cy, rx, ry = float(cx), float(cy), float(rx), float(ry)
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
                if fill:
                    if d <= 1.0:
                        self.px(x, y, col)
                else:
                    if 0.72 <= d <= 1.28:
                        self.px(x, y, col)
        return self

    def circle(self, cx, cy, r, col, fill=True):
        return self.ellipse(cx, cy, r, r, col, fill)

    def tri(self, x0, y0, x1, y1, x2, y2, col):
        """Filled triangle by scanline. Used for roofs, sails, mountain silhouettes."""
        ys = [int(y0), int(y1), int(y2)]
        for y in range(min(ys), max(ys) + 1):
            xs = []
            for (ax, ay), (bx, by) in (((x0, y0), (x1, y1)), ((x1, y1), (x2, y2)), ((x2, y2), (x0, y0))):
                if (ay <= y < by) or (by <= y < ay):
                    xs.append(ax + (y - ay) * (bx - ax) / float(by - ay))
            if len(xs) >= 2:
                self.hline(int(min(xs)), y, int(max(xs)) - int(min(xs)) + 1, col)
        return self

    # ── texture ─────────────────────────────────────────────────────────
    def dither(self, x, y, w, h, col_a, col_b, pattern=1):
        """Checkerboard / Bayer-ish dither. pattern 1 = 50%, 2 = 25% b."""
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                if pattern == 1:
                    pick = (xx + yy) & 1
                else:
                    pick = 1 if ((xx & 3) == 0 and (yy & 3) == 0) else 0
                self.px(xx, yy, col_b if pick else col_a)
        return self

    def noise(self, x, y, w, h, cols, density=0.25, seed=0):
        """Scatter single pixels. Deterministic via seed."""
        rnd = random.Random(seed)
        n = int(w * h * density)
        for _ in range(n):
            self.px(x + rnd.randrange(int(w)), y + rnd.randrange(int(h)),
                    rnd.choice(cols))
        return self

    def speckle(self, x, y, w, h, col, density=0.18, seed=0, size=1):
        rnd = random.Random(seed)
        for _ in range(int(w * h * density)):
            sx, sy = x + rnd.randrange(int(w)), y + rnd.randrange(int(h))
            if size == 1:
                self.px(sx, sy, col)
            else:
                self.rect(sx, sy, size, size, col)
        return self

    # ── composition ─────────────────────────────────────────────────────
    def paste(self, other, x, y, alpha_skip=True):
        """Stamp another canvas. None pixels are transparent by default."""
        for yy in range(other.h):
            for xx in range(other.w):
                col = other.get(xx, yy)
                if col is None and alpha_skip:
                    continue
                self.px(x + xx, y + yy, col)
        return self

    def flip_h(self):
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            out.buf[y] = self.buf[y][::-1]
        return out

    def flip_v(self):
        out = Canvas(self.w, self.h)
        out.buf = [row[:] for row in reversed(self.buf)]
        return out

    def crop(self, x, y, w, h):
        out = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                out.px(xx, yy, self.get(x + xx, y + yy))
        return out

    def outline(self, col=OUTLINE, inside=False):
        """Draw a 1px outline around every filled pixel adjacent to empty space.

        This is the single highest-leverage operation for making generated pixel
        art read as intentional rather than noisy. Real pixel artists outline
        everything; skipping it is why procedural art looks flat.
        """
        src = [row[:] for row in self.buf]
        for y in range(self.h):
            for x in range(self.w):
                filled = src[y][x] is not None
                if inside and not filled:
                    continue
                if not inside and filled:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    nb = src[ny][nx] if self.inside(nx, ny) else None
                    if inside and nb is None:
                        self.px(x, y, col)
                    elif not inside and nb is not None:
                        self.px(x, y, col)
        return self

    def drop_shadow(self, col=SHADOW, dy=1):
        """Ambient-occlusion shadow beneath the sprite. Never pure black."""
        src = [row[:] for row in self.buf]
        for y in range(self.h - 1, -1, -1):
            for x in range(self.w):
                if src[y][x] is None and self.inside(x, y - dy) and src[y - dy][x] is not None:
                    self.px(x, y, col)
        return self

    def remap(self, mapping):
        for y in range(self.h):
            for x in range(self.w):
                v = self.buf[y][x]
                if v in mapping:
                    self.buf[y][x] = mapping[v]
        return self

    # ── output ──────────────────────────────────────────────────────────
    def to_image(self):
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        p = img.load()
        for y in range(self.h):
            row = self.buf[y]
            for x in range(self.w):
                if row[x] is not None:
                    r, g, b = hexrgb(row[x])
                    p[x, y] = (r, g, b, 255)
        return img

    def save(self, path):
        import os
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        self.to_image().save(path)
        return path

    def used_colors(self):
        return {v for row in self.buf for v in row if v is not None}


def atlas(cells, cols, tile_w, tile_h):
    """Pack a list of Canvases into a sheet, `cols` per row.

    Godot's SpriteFrames / TileSet both want one atlas PNG with uniform cells,
    so every generator emits through here.
    """
    rows = (len(cells) + cols - 1) // cols
    out = Canvas(cols * tile_w, rows * tile_h)
    for i, cv in enumerate(cells):
        x, y = (i % cols) * tile_w, (i // cols) * tile_h
        # centre smaller cells inside the grid slot
        ox = x + (tile_w - cv.w) // 2
        oy = y + (tile_h - cv.h)
        out.paste(cv, ox, oy)
    return out


def save_atlas(cells, path, cols, tile_w, tile_h):
    return atlas(cells, cols, tile_w, tile_h).save(path)
