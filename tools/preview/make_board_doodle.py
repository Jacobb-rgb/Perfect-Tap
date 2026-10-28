"""
Paints the Terra Forge Custom hoverboard's deck art (owner 2026-10-25: "make it
look like you painted it, no regular shapes", after Pet Simulator's doodle
deck): a hand-drawn marker doodle covering the whole skateboard deck.

  python3 tools/preview/make_board_doodle.py [out.png]
  -> build/preview/textures/hoverboard_custom_deck.png (1024 x 416, alpha
     outside the rounded deck) and a copy for the owner to upload in
     NAHRAJ_DO_ROBLOXU/hoverboard/ (one Decal; its id goes in
     IconAssets.Textures.board_custom_deck).

Orientation (HoverboardBuilder.terraForgeCustom puts it on the deck's top as a
Front-face decal): the image's right edge = the board's nose. The board points
where the rider goes (Pet Simulator 99 style), so the doodles are painted
upright with their tops toward the nose (painted tall, then turned a quarter
clockwise): they stand upright in the game camera behind the rider.

Everything is wobbly on purpose: blobs are noisy circles, every line is drawn
twice with jitter like a marker, fills get diagonal marker strokes. Seeded, so
the art is the same on every run.
"""

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 1024, 416
SS = 2  # supersampling
rng = random.Random(25)

INK = (28, 24, 34)
PAPER = (252, 248, 238)
PALETTE = {
    "red": (255, 78, 92),
    "orange": (255, 146, 36),
    "yellow": (255, 214, 38),
    "lime": (172, 232, 52),
    "green": (66, 204, 96),
    "teal": (30, 206, 196),
    "blue": (64, 150, 255),
    "purple": (164, 92, 255),
    "pink": (255, 104, 196),
    "sky": (120, 210, 255),
}


def S(v):
    return int(round(v * SS))


def shade(color, k):
    """k < 0 darker, k > 0 lighter."""
    if k < 0:
        return tuple(max(0, int(c * (1 + k))) for c in color)
    return tuple(min(255, int(c + (255 - c) * k)) for c in color)


def wobbly_circle(cx, cy, r, points=56, amount=0.16, harmonics=3, squash=1.0, turn=0.0):
    """A noisy closed outline around (cx, cy)."""
    phases = [rng.uniform(0, math.tau) for _ in range(harmonics)]
    amps = [amount * rng.uniform(0.4, 1.0) / (i + 1) for i in range(harmonics)]
    out = []
    for i in range(points):
        a = math.tau * i / points
        k = 1.0
        for h in range(harmonics):
            k += amps[h] * math.sin((h + 2) * a + phases[h])
        k += rng.uniform(-0.02, 0.02)
        x = math.cos(a) * r * k
        y = math.sin(a) * r * k * squash
        out.append((cx + x * math.cos(turn) - y * math.sin(turn), cy + x * math.sin(turn) + y * math.cos(turn)))
    return out


def jitter(points, amount):
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in points]


def scaled(points):
    return [(S(x), S(y)) for x, y in points]


def marker_line(draw, points, width, color=INK, closed=False, passes=2):
    """A hand-drawn line: drawn `passes` times with a little jitter, round joints."""
    pts = list(points) + ([points[0]] if closed else [])
    for p in range(passes):
        j = jitter(pts, 1.6 if p else 0.6)
        w = width * (1.0 if p == 0 else 0.7)
        draw.line(scaled(j), fill=color, width=S(w), joint="curve")
        for x, y in j[:: max(1, len(j) // 12)]:
            r = w / 2
            draw.ellipse([S(x - r), S(y - r), S(x + r), S(y + r)], fill=color)


def marker_fill(layer, polygon, color, strokes=True):
    """Fills a polygon like coloured with a marker: the colour, then diagonal strokes."""
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).polygon(scaled(polygon), fill=255)
    fill = Image.new("RGBA", layer.size, color + (255,))
    if strokes:
        d = ImageDraw.Draw(fill)
        xs = [p[0] for p in polygon]
        ys = [p[1] for p in polygon]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        span = (x1 - x0) + (y1 - y0)
        step = rng.uniform(7, 10)
        t = -span
        while t < span:
            c = shade(color, rng.choice([-0.12, -0.08, 0.1, 0.16]))
            a = rng.randint(70, 150)
            x = x0 + t
            d.line([(S(x), S(y1 + 4)), (S(x + (y1 - y0) + 8), S(y0 - 4))], fill=c + (a,), width=S(rng.uniform(2, 4)))
            t += step + rng.uniform(-2, 3)
    layer.paste(fill, (0, 0), mask)


def blob(layer, draw, cx, cy, r, color, squash=1.0, outline=7):
    poly = wobbly_circle(cx, cy, r, squash=squash, turn=rng.uniform(0, math.tau))
    marker_fill(layer, poly, color)
    marker_line(draw, poly, outline, closed=True)
    return poly


def sparkle(draw, cx, cy, r, color=(255, 255, 255)):
    pts = []
    for i in range(8):
        a = math.tau * i / 8 + rng.uniform(-0.1, 0.1)
        rr = r if i % 2 == 0 else r * 0.32
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    draw.polygon(scaled(pts), fill=color + (255,))
    marker_line(draw, pts, 3, closed=True, passes=1)


def dot(draw, cx, cy, r, color):
    draw.ellipse([S(cx - r), S(cy - r), S(cx + r), S(cy + r)], fill=color + (255,))


# ------------------------------------------------------------------ doodles


def golem(layer, draw, cx, cy, s):
    """A cute stone golem head: rounded rocky face, big eyes, a smile, blush, a crack."""
    face = wobbly_circle(cx, cy, 52 * s, amount=0.09, squash=0.9)
    marker_fill(layer, face, (170, 182, 210))
    marker_line(draw, face, 7, closed=True)
    # a moss tuft on top
    moss = wobbly_circle(cx - 10 * s, cy - 44 * s, 20 * s, amount=0.25, squash=0.55)
    marker_fill(layer, moss, PALETTE["green"])
    marker_line(draw, moss, 5, closed=True)
    for side in (-1, 1):
        ex, ey = cx + side * 20 * s, cy - 6 * s
        eye = wobbly_circle(ex, ey, 13 * s, amount=0.06, squash=1.15)
        draw.polygon(scaled(eye), fill=(255, 255, 255, 255))
        marker_line(draw, eye, 4, closed=True, passes=1)
        dot(draw, ex + side * 2 * s, ey + 3 * s, 7 * s, INK)
        dot(draw, ex - 2 * s, ey - 2 * s, 3 * s, (255, 255, 255))
        dot(draw, cx + side * 34 * s, cy + 16 * s, 7 * s, shade(PALETTE["pink"], 0.25))
    smile = [(cx - 14 * s + i * 2.8 * s, cy + 18 * s + math.sin(i / 10 * math.pi) * 9 * s) for i in range(11)]
    marker_line(draw, smile, 5)
    crack = [(cx + 30 * s, cy - 34 * s), (cx + 22 * s, cy - 24 * s), (cx + 30 * s, cy - 16 * s), (cx + 24 * s, cy - 8 * s)]
    marker_line(draw, crack, 3, passes=1)


def gem(layer, draw, cx, cy, s, color):
    """A crystal: a pointy hexagon with facet lines and a shine."""
    w, h = 26 * s, 44 * s
    pts = [(cx, cy - h), (cx + w, cy - h * 0.45), (cx + w * 0.85, cy + h * 0.55), (cx, cy + h), (cx - w * 0.85, cy + h * 0.55), (cx - w, cy - h * 0.45)]
    pts = jitter(pts, 2.5 * s)
    marker_fill(layer, pts, color)
    marker_line(draw, [pts[0], pts[3]], 3, passes=1)
    marker_line(draw, [pts[5], (cx, cy - h * 0.05), pts[1]], 3, passes=1)
    marker_line(draw, pts, 6, closed=True)
    shine = [(cx - w * 0.55, cy - h * 0.3), (cx - w * 0.3, cy - h * 0.6), (cx - w * 0.2, cy - h * 0.1)]
    draw.polygon(scaled(shine), fill=(255, 255, 255, 230))


def bolt(layer, draw, cx, cy, s):
    pts = [(-6, -46), (22, -46), (8, -10), (26, -10), (-14, 48), (-2, 4), (-20, 4)]
    pts = jitter([(cx + x * s, cy + y * s) for x, y in pts], 2 * s)
    marker_fill(layer, pts, PALETTE["yellow"])
    marker_line(draw, pts, 6, closed=True)


def star(layer, draw, cx, cy, s, color, face=True):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + math.tau * i / 10 + rng.uniform(-0.06, 0.06)
        r = (40 if i % 2 == 0 else 18) * s * rng.uniform(0.92, 1.08)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    marker_fill(layer, pts, color)
    marker_line(draw, pts, 6, closed=True)
    if face:
        for side in (-1, 1):
            dot(draw, cx + side * 7 * s, cy - 2 * s, 3.5 * s, INK)
        smile = [(cx - 6 * s + i * 1.5 * s, cy + 6 * s + math.sin(i / 8 * math.pi) * 4 * s) for i in range(9)]
        marker_line(draw, smile, 3, passes=1)


def heart(layer, draw, cx, cy, s):
    pts = []
    for i in range(48):
        t = math.tau * i / 48
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x * 2.2 * s, cy + y * 2.2 * s))
    pts = jitter(pts, 1.5 * s)
    marker_fill(layer, pts, PALETTE["red"])
    marker_line(draw, pts, 6, closed=True)
    dot(draw, cx - 14 * s, cy - 12 * s, 5 * s, (255, 255, 255))


def flame(layer, draw, cx, cy, s):
    outer = [(0, -54), (14, -26), (30, -36), (34, 4), (22, 34), (0, 42), (-22, 34), (-34, 6), (-24, -22), (-12, -6)]
    outer = jitter([(cx + x * s, cy + y * s) for x, y in outer], 2.5 * s)
    marker_fill(layer, outer, PALETTE["orange"])
    inner = [(0, -18), (12, 6), (8, 28), (-8, 28), (-12, 6)]
    inner = jitter([(cx + x * s, cy + y * s) for x, y in inner], 1.5 * s)
    marker_fill(layer, inner, PALETTE["yellow"], strokes=False)
    marker_line(draw, outer, 6, closed=True)


def pickaxe(layer, draw, cx, cy, s):
    handle = [(cx - 34 * s, cy + 34 * s), (cx + 18 * s, cy - 18 * s)]
    marker_line(draw, handle, 15 * s, color=INK, passes=1)
    marker_line(draw, handle, 8 * s, color=(178, 112, 58), passes=1)
    head = []
    for i in range(13):
        t = i / 12
        a = math.pi * 1.05 + t * math.pi * 0.9
        head.append((cx + 18 * s + math.cos(a + 0.8) * 40 * s, cy - 18 * s + math.sin(a + 0.8) * 22 * s))
    marker_line(draw, head, 18 * s, color=INK, passes=1)
    marker_line(draw, head, 10 * s, color=(196, 206, 226), passes=1)


def orb(layer, draw, cx, cy, s):
    poly = wobbly_circle(cx, cy, 34 * s, amount=0.07)
    marker_fill(layer, poly, PALETTE["purple"])
    spiral = []
    for i in range(40):
        t = i / 39
        a = t * math.tau * 2.2
        r = 4 * s + t * 24 * s
        spiral.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    marker_line(draw, spiral, 4, color=shade(PALETTE["purple"], 0.55), passes=1)
    marker_line(draw, poly, 6, closed=True)
    dot(draw, cx - 12 * s, cy - 14 * s, 6 * s, (255, 255, 255))


def slime(layer, draw, cx, cy, s, color):
    """A little blob buddy with a drip."""
    body = [(cx + math.cos(a) * 34 * s * (1 + 0.08 * math.sin(3 * a)), cy + min(0, math.sin(a)) * 30 * s + max(0, math.sin(a)) * 12 * s) for a in [math.tau * i / 40 for i in range(40)]]
    body = jitter(body, 1.5 * s)
    marker_fill(layer, body, color)
    marker_line(draw, body, 6, closed=True)
    for side in (-1, 1):
        dot(draw, cx + side * 11 * s, cy - 6 * s, 5 * s, INK)
        dot(draw, cx + side * 11 * s - 1.5 * s, cy - 8 * s, 1.8 * s, (255, 255, 255))
    marker_line(draw, [(cx - 5 * s, cy + 3 * s), (cx, cy + 6 * s), (cx + 5 * s, cy + 3 * s)], 3, passes=1)


def coin(layer, draw, cx, cy, s):
    poly = wobbly_circle(cx, cy, 26 * s, amount=0.05)
    marker_fill(layer, poly, (255, 200, 40))
    inner = wobbly_circle(cx, cy, 17 * s, amount=0.05)
    marker_line(draw, inner, 3, color=shade((255, 200, 40), -0.35), closed=True, passes=1)
    marker_line(draw, poly, 6, closed=True)
    # a little T F mark: two strokes, hand drawn
    marker_line(draw, [(cx - 9 * s, cy - 8 * s), (cx + 1 * s, cy - 8 * s)], 4, passes=1)
    marker_line(draw, [(cx - 4 * s, cy - 8 * s), (cx - 4 * s, cy + 10 * s)], 4, passes=1)
    marker_line(draw, [(cx + 5 * s, cy - 8 * s), (cx + 5 * s, cy + 10 * s)], 4, passes=1)
    marker_line(draw, [(cx + 5 * s, cy - 8 * s), (cx + 12 * s, cy - 8 * s)], 4, passes=1)
    marker_line(draw, [(cx + 5 * s, cy + 1 * s), (cx + 10 * s, cy + 1 * s)], 4, passes=1)


def squiggle(draw, x0, y0, length, color=INK):
    pts = [(x0 + i * length / 14, y0 + math.sin(i * 1.3) * 6) for i in range(15)]
    marker_line(draw, pts, 4, color=color, passes=1)


# ------------------------------------------------------------------ the deck


def paint(out_path):
    # painted upright on a tall canvas (the top = the board's nose, ahead of a rider seen from
    # behind), then turned a quarter clockwise so the top lands on the image's right edge
    PW, PH = H, W
    art = Image.new("RGBA", (S(PW), S(PH)), PAPER + (255,))
    draw = ImageDraw.Draw(art, "RGBA")
    # paper grain
    for _ in range(9000):
        x, y = rng.uniform(0, PW), rng.uniform(0, PH)
        c = shade(PAPER, rng.uniform(-0.05, 0.0))
        draw.point((S(x), S(y)), fill=c + (255,))

    # the background: big wobbly paint blobs all over, overlapping (no white left but thin gaps)
    colors = ["blue", "orange", "green", "pink", "yellow", "purple", "teal", "red", "lime", "sky"]
    spots = []
    cols, rows = 3, 7
    for gx in range(cols):
        for gy in range(rows):
            x = (gx + 0.5) * PW / cols + rng.uniform(-24, 24)
            y = (gy + 0.5) * PH / rows + rng.uniform(-30, 30)
            spots.append((x, y))
    rng.shuffle(spots)
    for i, (x, y) in enumerate(spots):
        blob(art, draw, x, y, rng.uniform(78, 104), PALETTE[colors[i % len(colors)]], squash=rng.uniform(0.75, 1.05), outline=6)

    # doodles on top, upright for a rider seen from behind (the feet stand near y 340 and 680)
    star(art, draw, 208, 125, 1.5, PALETTE["yellow"])
    coin(art, draw, 92, 225, 1.15)
    orb(art, draw, 322, 235, 1.0)
    bolt(art, draw, 300, 365, 1.2)
    golem(art, draw, 190, 490, 1.6)
    gem(art, draw, 110, 640, 1.3, PALETTE["sky"])
    gem(art, draw, 160, 590, 0.85, PALETTE["purple"])
    heart(art, draw, 305, 650, 1.2)
    slime(art, draw, 125, 790, 1.15, PALETTE["lime"])
    flame(art, draw, 305, 820, 1.2)
    pickaxe(art, draw, 235, 925, 1.0)
    slime(art, draw, 110, 940, 0.8, PALETTE["pink"])
    star(art, draw, 330, 965, 0.65, PALETTE["orange"], face=False)
    for _ in range(16):
        sparkle(draw, rng.uniform(40, PW - 40), rng.uniform(60, PH - 60), rng.uniform(9, 16))
    for _ in range(30):
        dot(draw, rng.uniform(30, PW - 30), rng.uniform(40, PH - 40), rng.uniform(3, 6), (255, 255, 255))

    # the deck's shape: a rounded skateboard with a thick wobbly marker edge
    mask = Image.new("L", art.size, 0)
    md = ImageDraw.Draw(mask)
    inset = 6
    md.rounded_rectangle([S(inset), S(inset), S(PW - inset), S(PH - inset)], radius=S(PW / 2 - inset), fill=255)
    edge = []
    r = PW / 2 - 16
    side = PH - PW
    perimeter = 2 * side + 2 * math.pi * r
    for i in range(120):
        d = i / 120 * perimeter
        # walk the capsule: right side down, bottom cap, left side up, top cap
        if d < side:
            p = (PW - 16, PW / 2 + d)
        elif d < side + math.pi * r:
            a = (d - side) / r
            p = (PW / 2 + math.cos(a) * r, PH - PW / 2 + math.sin(a) * r)
        elif d < 2 * side + math.pi * r:
            p = (16, PH - PW / 2 - (d - side - math.pi * r))
        else:
            a = math.pi + (d - 2 * side - math.pi * r) / r
            p = (PW / 2 + math.cos(a) * r, PW / 2 + math.sin(a) * r)
        edge.append(p)
    marker_line(draw, edge, 16, closed=True)
    art.putalpha(mask)
    art = art.resize((PW, PH), Image.LANCZOS)
    # a touch of softness like real marker ink
    art = art.filter(ImageFilter.SMOOTH)
    # the nose (the top) to the right edge
    art = art.rotate(-90, expand=True)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    art.save(out_path)
    return art


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", ".."))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(repo, "build", "preview", "textures", "hoverboard_custom_deck.png")
    paint(out)
    print("deck art ->", out)
