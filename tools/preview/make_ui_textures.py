"""
Makes the Pop UI textures (owner 2026-10-21: "everything must glow, light
edges, cool backgrounds" like the Roblox shop photos). Pure PIL, no inputs.

  python3 tools/preview/make_ui_textures.py <outDir>

  ui_studs.png     128 x 128 tile: raised square studs (white highlight top /
                   left, dark shadow bottom / right, faint fill): laid over any
                   colour with ScaleType.Tile (cards, headers, buttons, bodies)
  ui_lattice.png   128 x 128 tile: thin white diagonal lines both ways (the
                   pixel reels' lattice, owner 2026-10-22), two a way per tile
  ui_fx.png        1024 x 1024 sheet: rays (0,0 512), glow (512,0 256),
                   sparkle (768,0 128), shine (512,256 512x128)
Upload both (NAHRAJ_DO_ROBLOXU/ikony_ui) and paste the ids into
IconAssets.Textures.
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)
SS = 4  # supersampling

def studs():
    n = 128 * SS
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cell = 64 * SS
    pad = 12 * SS
    r = 6 * SS
    w = 4 * SS
    for cy in range(2):
        for cx in range(2):
            x0, y0 = cx * cell + pad, cy * cell + pad
            x1, y1 = x0 + cell - 2 * pad, y0 + cell - 2 * pad
            # faint fill
            d.rounded_rectangle([x0, y0, x1, y1], r, fill=(255, 255, 255, 9))
            # shadow: an L along the bottom and the right
            d.line([(x0 + r, y1 + w // 2), (x1 - r // 2, y1 + w // 2)], fill=(0, 0, 0, 48), width=w)
            d.line([(x1 + w // 2, y0 + r), (x1 + w // 2, y1 - r // 2)], fill=(0, 0, 0, 48), width=w)
            # highlight: an L along the top and the left
            d.line([(x0 + r, y0), (x1 - r, y0)], fill=(255, 255, 255, 80), width=w)
            d.line([(x0, y0 + r), (x0, y1 - r)], fill=(255, 255, 255, 80), width=w)
    return im.resize((128, 128), Image.LANCZOS)

def rays(size=512, count=14):
    n = size * SS
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    c = n / 2
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    for i in range(count):
        a0 = (i / count) * 2 * math.pi
        a1 = a0 + (2 * math.pi / count) * 0.5
        pts = [(c, c)]
        for k in range(9):
            a = a0 + (a1 - a0) * k / 8
            pts.append((c + math.cos(a) * n, c + math.sin(a) * n))
        d.polygon(pts, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(3 * SS))
    # radial falloff
    fall = Image.new("L", (n, n), 0)
    fd = fall.load()
    for y in range(0, n, 2):
        for x in range(0, n, 2):
            rr = math.hypot(x - c, y - c) / c
            v = max(0.0, 1.0 - rr) ** 1.3
            val = int(255 * v)
            fd[x, y] = val
            if x + 1 < n: fd[x + 1, y] = val
            if y + 1 < n: fd[x, y + 1] = val
            if x + 1 < n and y + 1 < n: fd[x + 1, y + 1] = val
    from PIL import ImageChops
    alpha = ImageChops.multiply(mask, fall)
    white = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    white.putalpha(alpha)
    return white.resize((size, size), Image.LANCZOS)

def glow(size=256):
    im = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    p = im.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            rr = math.hypot(x - c + 0.5, y - c + 0.5) / c
            a = max(0.0, 1.0 - rr) ** 2
            p[x, y] = (255, 255, 255, int(255 * a))
    return im

def sparkle(size=128):
    n = size * SS
    im = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    L, W = n * 0.48, n * 0.07
    for ang in (0, math.pi / 2):
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [(c + ca * L, c + sa * L), (c - sa * W, c + ca * W), (c - ca * L, c - sa * L), (c + sa * W, c - ca * W)]
        d.polygon(pts, fill=(255, 255, 255, 255))
    im = im.resize((size, size), Image.LANCZOS)
    g = glow(size)
    g.putalpha(g.getchannel("A").point(lambda v: int(v * 0.55)))
    base = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    base.alpha_composite(g)
    base.alpha_composite(im)
    return base

def lattice():
    # two lines each way per tile, through the corners and the middle: seamless when tiled
    n = 128 * SS
    im = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    d = ImageDraw.Draw(im)
    w = 3 * SS
    for k in range(-2, 3):
        o = k * n // 2
        d.line([(o, 0), (o + n, n)], fill=(255, 255, 255, 255), width=w)
        d.line([(o, n), (o + n, 0)], fill=(255, 255, 255, 255), width=w)
    return im.resize((128, 128), Image.LANCZOS)

def shine(w=512, h=128):
    im = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    p = im.load()
    for y in range(h):
        for x in range(w):
            # a diagonal band: distance to the line x = w/2 + (y - h/2)*0.6
            dx = (x - (w / 2 + (y - h / 2) * 0.6)) / (w * 0.12)
            a = math.exp(-dx * dx) * 0.9
            p[x, y] = (255, 255, 255, int(255 * a))
    return im

studs().save(os.path.join(out, "ui_studs.png"))
lattice().save(os.path.join(out, "ui_lattice.png"))
sheet = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
sheet.alpha_composite(rays(), (0, 0))
sheet.alpha_composite(glow(), (512, 0))
sheet.alpha_composite(sparkle(), (768, 0))
sheet.alpha_composite(shine(), (512, 256))
sheet.save(os.path.join(out, "ui_fx.png"))
# single pictures for the preview renderer
rays().save(os.path.join(out, "fx_rays.png"))
glow().save(os.path.join(out, "fx_glow.png"))
sparkle().save(os.path.join(out, "fx_sparkle.png"))
shine().save(os.path.join(out, "fx_shine.png"))
print("textures ->", out)
