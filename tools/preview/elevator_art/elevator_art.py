#!/usr/bin/env python3
"""
Elevator window floor pictures (ui/elevator-v2): preview renders of the six mine floors
(art/meshy-models look) + the COMING SOON banner -> one 1024 x 1024 upload sheet and single files.

  python3 elevator_art.py <shots dir> <sheet .png> <single files dir> [contact sheet .jpg]

<shots dir>: the renders of tools/preview/render.mjs (README.md next to this file):
  elev_1 .. elev_6 (.jpg, 16:9) and elev_soon (.jpg, 6.4:1)
Sheet layout (px, top-left origin): floor N at ((N-1) % 2 * 512, (N-1) // 2 * 288), 512 x 288;
the banner at (0, 864), 1024 x 160. Every cell is RGB (fully opaque) and made on its own, so
nothing crosses a cell edge. Needs Pillow + numpy.

Per picture (numbers in BASE / LOOK / SOON): Lanczos down-scale of the whole render to its cell,
exposure in linear light to a mean-luma target (bisection within ev_range) with a soft filmic
shoulder, saturation, a gentle S-curve, extra bloom on the highlights, a vignette, a darker top
band ("sky") and top-left corner (the card's title area), a 3 px darker rim, a 1 px unsharp mask.
The banner instead maps its luma through a night ramp and darkens a band where its text goes.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

FLOORS = ["Quarry", "EmberCaves", "DeepHollow", "SunkenPalace", "StormglassRift", "HeartstoneCore"]
CELL = (512, 288)
BANNER = (1024, 160)

BASE = dict(
    crop=(0.0, 0.0, 1.0, 1.0),  # left, top, right, bottom (fractions of the render; keep the cell's aspect)
    target=0.0,  # mean luma (0..1, sRGB) after the exposure, found by search (0 = no auto exposure)
    ev_range=(-1.0, 1.0),  # the auto exposure stays within these stops (the renders carry the big changes)
    ev=0.0,  # extra exposure (stops) on top
    shoulder=0.75,  # filmic roll-off: linear light above this compresses softly instead of clipping
    sat=1.12,  # saturation round the luma
    contrast=0.10,  # S-curve strength through mid grey
    glow=0.20,  # extra bloom: the highlights over glow_from, blurred, screened on top
    glow_from=0.62,
    glow_radius=7.0,  # px at cell size
    tint=(1.0, 1.0, 1.0),  # multiplies RGB in linear light (balances a cast)
    vignette=0.30,  # corner darkening 0..1 (the centre is untouched)
    sky=(0.22, 0.40),  # top-edge graduated darkening: (strength at the top edge, reach down 0..1)
    corner=(0.22, 0.55),  # top-left corner darkening: (strength, reach as a fraction of the card's width / height)
    edge=(3.0, 0.8),  # outer px darkened: (px, factor at the very edge)
    sharpen=55,  # UnsharpMask percent (radius 1 px)
)

LOOK = {
    "Quarry": dict(target=0.40, sat=1.2, contrast=0.14, sky=(0.28, 0.45)),
    "EmberCaves": dict(target=0.26),
    "DeepHollow": dict(target=0.27),
    "SunkenPalace": dict(target=0.28, sat=1.16, contrast=0.16),
    "StormglassRift": dict(target=0.27),
    "HeartstoneCore": dict(target=0.20, ev_range=(-1.0, 1.5)),
}
SOON = dict(
    target=0.17,
    ev_range=(-1.0, 3.0),
    sat=1.0,
    contrast=0.06,
    glow=0.30,
    glow_from=0.45,
    glow_radius=6.0,
    vignette=0.35,
    sky=(0.0, 0.4),
    corner=(0.0, 0.5),
    sharpen=30,
    # the luma through a night ramp (rows: luma, r, g, b 0..255); the brightest saturated bits keep `keep` of their colour
    night=[(0.0, 4, 5, 18), (0.2, 20, 20, 64), (0.45, 58, 50, 150), (0.75, 124, 104, 226), (1.0, 204, 180, 255)],
    keep=0.28,
    calm=(0.45, 0.3, 0.3),  # a darker band where the window writes COMING SOON: (centre x 0..1, half width, strength)
)

LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


def params(over: dict) -> dict:
    p = dict(BASE)
    p.update(over)
    return p


def to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def tonemap(lin, shoulder):
    # identity below the shoulder, a soft exponential roll-off to 1 above it
    over = np.maximum(lin - shoulder, 0)
    top = 1 - shoulder
    return np.where(lin <= shoulder, lin, shoulder + top * (1 - np.exp(-over / top)))


def expose(lin, ev, shoulder):
    return to_srgb(tonemap(lin * (2.0**ev), shoulder))


def crop_resize(im: Image.Image, crop, size) -> Image.Image:
    w, h = im.size
    box = (round(crop[0] * w), round(crop[1] * h), round(crop[2] * w), round(crop[3] * h))
    return im.crop(box).resize(size, Image.LANCZOS, reducing_gap=3.0)


def grade(im: Image.Image, p: dict) -> tuple[Image.Image, float]:
    a = np.asarray(im).astype(np.float32) / 255.0
    lin = to_lin(a) * np.array(p["tint"], np.float32)
    ev = 0.0
    if p["target"] > 0:  # the exposure that brings the mean luma to the target (bisection, within ev_range)
        lo, hi = p["ev_range"]
        for _ in range(28):
            mid = (lo + hi) / 2
            if float((expose(lin, mid, p["shoulder"]) @ LUMA).mean()) < p["target"]:
                lo = mid
            else:
                hi = mid
        ev = (lo + hi) / 2
    a = expose(lin, ev + p["ev"], p["shoulder"]).astype(np.float32)
    luma = (a @ LUMA)[..., None]
    a = np.clip(luma + (a - luma) * p["sat"], 0, 1)
    if p.get("night"):
        # the COMING SOON banner: the luma through a dark indigo -> violet -> lavender ramp; the
        # brightest saturated bits (crystals, the tunnel's glow) keep some of their own colour
        stops = np.array(p["night"], np.float32)  # rows: luma, r, g, b (0..255)
        l = (a @ LUMA).astype(np.float32)
        ramp = np.stack([np.interp(l, stops[:, 0], stops[:, c] / 255.0) for c in (1, 2, 3)], -1)
        mx, mn = a.max(-1), a.min(-1)
        keep = p.get("keep", 0.35) * np.clip((mx - mn) / np.maximum(mx, 1e-4), 0, 1) * np.clip(l / 0.5, 0, 1)
        a = ramp * (1 - keep[..., None]) + a * keep[..., None]
    if p.get("calm"):
        # a darker, quieter band where the window writes its text: (centre x 0..1, half width, strength)
        cx, cw, cs = p["calm"]
        xs = (np.arange(a.shape[1], dtype=np.float32) + 0.5) / a.shape[1]
        a = a * (1 - cs * np.exp(-(((xs - cx) / cw) ** 2)))[None, :, None]
    if p.get("sky"):
        # a graduated filter from the top edge: (strength at the top, how far down 0..1), a deeper
        # sky that also sits calmer under the card's title
        gs, ge = p["sky"]
        ys = (np.arange(a.shape[0], dtype=np.float32) + 0.5) / a.shape[0]
        a = a * (1 - gs * np.clip(1 - ys / ge, 0, 1) ** 1.5)[:, None, None]
    k = p["contrast"]
    a = np.clip(a + k * (a - 0.5) * (1 - np.abs(2 * a - 1)) * 2, 0, 1)
    if p["glow"] > 0:
        hi_a = np.clip((a - p["glow_from"]) / (1 - p["glow_from"]), 0, 1)
        hi_im = Image.fromarray((hi_a * 255 + 0.5).astype(np.uint8)).filter(ImageFilter.GaussianBlur(p["glow_radius"]))
        g = np.asarray(hi_im).astype(np.float32) / 255.0
        a = 1 - (1 - a) * (1 - p["glow"] * g)  # screen
    h, w = a.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
    r2 = np.clip((nx * nx + ny * ny) / 2, 0, 1)
    a = a * (1 - p["vignette"] * r2**1.6)[..., None]
    if p["corner"][0] > 0:
        # the top-left, where the card writes its number, name and chips: a soft darker corner
        cs, cr = p["corner"]
        d = np.sqrt(((x + 0.5) / w) ** 2 + ((y + 0.5) / h) ** 2)
        a = a * (1 - cs * np.clip(1 - d / cr, 0, 1) ** 1.5)[..., None]
    if p["edge"][0] > 0:
        # the outermost px of the cell a little darker: GPU filtering at a cell's edge (ImageRect)
        # then blends dark into dark, never a bright line from the neighbour cell
        ep, ef = p["edge"]
        ex = np.minimum(np.minimum(x + 0.5, w - x - 0.5), np.minimum(y + 0.5, h - y - 0.5))
        a = a * (ef + (1 - ef) * np.clip(ex / ep, 0, 1))[..., None]
    out = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))
    if p["sharpen"]:
        out = out.filter(ImageFilter.UnsharpMask(radius=1.0, percent=p["sharpen"], threshold=2))
    return out, ev


def make(shots: str):
    cards = []
    for i, fid in enumerate(FLOORS):
        p = params(LOOK[fid])
        im = Image.open(os.path.join(shots, f"elev_{i + 1}.jpg")).convert("RGB")
        card, ev = grade(crop_resize(im, p["crop"], CELL), p)
        cards.append((fid, card))
        print(f"{fid}: auto exposure {ev:+.2f} EV")
    p = params(SOON)
    im = Image.open(os.path.join(shots, "elev_soon.jpg")).convert("RGB")
    soon, ev = grade(crop_resize(im, p["crop"], BANNER), p)
    print(f"ComingSoon: auto exposure {ev:+.2f} EV")
    return cards, soon


def main():
    shots, sheet_path, singles = sys.argv[1], sys.argv[2], sys.argv[3]
    contact = sys.argv[4] if len(sys.argv) > 4 else None
    cards, soon = make(shots)
    os.makedirs(os.path.dirname(os.path.abspath(sheet_path)), exist_ok=True)
    os.makedirs(singles, exist_ok=True)
    sheet = Image.new("RGB", (1024, 1024), (0, 0, 0))
    for i, (fid, card) in enumerate(cards):
        card.save(os.path.join(singles, f"elevator_{fid}.png"))
        sheet.paste(card, ((i % 2) * 512, (i // 2) * 288))
    soon.save(os.path.join(singles, "elevator_ComingSoon.png"))
    sheet.paste(soon, (0, 864))
    sheet.save(sheet_path)
    print("sheet", sheet_path, sheet.size, sheet.mode)
    if contact:
        pad, lab = 16, 22
        cs = Image.new("RGB", (2 * 512 + 3 * pad, 3 * (288 + lab + pad) + 160 + lab + 2 * pad), (24, 24, 30))
        d = ImageDraw.Draw(cs)
        for i, (fid, card) in enumerate(cards):
            x = pad + (i % 2) * (512 + pad)
            y = pad + (i // 2) * (288 + lab + pad)
            d.text((x, y + 4), f"{i + 1}  {fid}", fill=(235, 235, 235))
            cs.paste(card, (x, y + lab))
        y = pad + 3 * (288 + lab + pad)
        d.text((pad, y + 4), "Coming soon", fill=(235, 235, 235))
        cs.paste(soon, (pad, y + lab))
        cs.save(contact, quality=92)
        print("contact", contact, cs.size)


if __name__ == "__main__":
    main()
