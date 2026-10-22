#!/usr/bin/env python3
"""Compose the App Store frames described by frames.json, once per output size.

Each frame is a black canvas, a two-line headline, and a device frame (a metal
edge, a black bezel, then the screen) holding one simulator capture from
sources/<device>/<scene>.png. The layout is xMosaique's App Store design,
measured at 1290 x 2796 (`base` in frames.json):

  Scale by the canvas *height*, not by a fit to the new box. The vertical
  composition is the tuned part (where the baselines sit against the top of
  the device frame, and the black below it); a different aspect is absorbed
  by re-centring.

  The screen box takes the capture's aspect, so a capture goes in
  unstretched, and the frame is built out from it by its border and bezel.
  Keep the frame's width even, so it centres on a whole pixel.

  A line's baseline is placed straight from the measured baselines, and the
  headline's size from the measured cap height.

The status bar is painted out in the colour around it (`paintOut`), as the
app draws a flat background there. Frame 01 uses the real camera capture
named by its `real` field once that file is in sources/; until then it uses
the simulator's.

Watch screenshots are not framed: App Store Connect takes them at the
watch's own resolution, so `watch` blocks copy the captures as they are.

    python3 render.py            # every frame, every size
    python3 render.py 03-timed-bulb
"""

from __future__ import annotations

import json
import pathlib
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
CFG = json.loads((HERE / "frames.json").read_text())
SS = 4  # supersampling for the frame's curves


def geometry(w: int, h: int, device: dict) -> dict:
    base = CFG["base"]
    s = h / base["canvas"][1]
    cw, ch = device["capture"]
    fh = round(base["frameH"] * s)
    border = round(base["border"] * s)
    bezel = round(base["bezel"] * s * device["bezelScale"])
    inset = border + bezel
    screen_h = fh - 2 * inset
    fw = 2 * round((screen_h * cw / ch + 2 * inset) / 2)
    if fw > w:
        raise SystemExit(f"a {fw}px frame does not fit a {w}px canvas")
    fx, fy = (w - fw) // 2, round(base["frameY"] * s)
    screen_r = round(device["radiusRatio"] * (fw - 2 * inset))
    return {
        "frame": (fx, fy, fw, fh), "radius": screen_r + inset, "border": border,
        "screen": (fx + inset, fy + inset, fw - 2 * inset, screen_h), "screenRadius": screen_r,
        "capHeight": base["capHeight"] * s, "baselines": [b * s for b in base["baselines"]],
    }


def rounded_mask(size, box, radius) -> Image.Image:
    """An anti-aliased mask of a rounded rectangle, drawn at SS x and reduced."""
    w, h = size
    big = Image.new("L", (w * SS, h * SS), 0)
    x, y, bw, bh = (v * SS for v in box)
    ImageDraw.Draw(big).rounded_rectangle((x, y, x + bw - 1, y + bh - 1), radius * SS, fill=255)
    return big.resize(size, Image.LANCZOS)


def screen_image(path: pathlib.Path, device: dict, size) -> Image.Image:
    im = Image.open(path).convert("RGB")
    if list(im.size) == device["capture"]:
        draw = ImageDraw.Draw(im)
        for x, y, w, h in device["paintOut"]:
            # The colour just below the painted band is the background the app draws.
            colour = im.getpixel((min(x + w // 2, im.width - 1), min(y + h + 2, im.height - 1)))
            draw.rectangle((x, y, x + w - 1, y + h - 1), fill=colour)
    else:
        # A capture from another device (the real camera shot): cover the box.
        print(f"  note: {path.name} is {im.width}x{im.height}, cropped to fit")
        draw = ImageDraw.Draw(im)
        band = round(im.height * 0.055)
        colour = im.getpixel((im.width // 2, band + 2))
        draw.rectangle((0, 0, im.width, band), fill=colour)
    tw, th = size
    scale = max(tw / im.width, th / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    left, top = (im.width - tw) // 2, (im.height - th) // 2
    return im.crop((left, top, left + tw, top + th))


def headline(canvas: Image.Image, lines, geo) -> int:
    h = CFG["headline"]
    font = ImageFont.truetype(str(HERE / h["fontFile"]), round(geo["capHeight"] / h["capHeightRatio"]))
    tracking = h["tracking"] * font.size
    draw = ImageDraw.Draw(canvas)
    widest = 0
    for text, baseline in zip(lines, geo["baselines"]):
        # Prefix lengths keep the font's kerning; tracking is added per glyph.
        width = font.getlength(text) + tracking * (len(text) - 1)
        widest = max(widest, width)
        x0 = (canvas.width - width) / 2
        for i, ch in enumerate(text):
            draw.text((x0 + font.getlength(text[:i]) + tracking * i, baseline), ch,
                      font=font, fill=h["colour"], anchor="ls")
    return round(widest)


def render(out: dict, spec: dict) -> pathlib.Path | None:
    device_name = out["device"]
    if device_name in spec.get("skip", []):
        return None
    device = CFG["devices"][device_name]
    source = HERE / "sources" / device_name / f"{spec['scene']}.png"
    real = spec.get("real")
    if real and device_name == real.split("/")[0] and (HERE / "sources" / real).exists():
        source = HERE / "sources" / real
    if not source.exists():
        print(f"  skip {spec['id']}: no {source.relative_to(HERE)}")
        return None

    w, h = (int(v) for v in out["name"].split("x"))
    geo = geometry(w, h, device)
    canvas = Image.new("RGB", (w, h), "#000000")

    fx, fy, fw, fh = geo["frame"]
    canvas.paste(Image.new("RGB", (w, h), CFG["base"]["borderColour"]), (0, 0),
                 rounded_mask((w, h), geo["frame"], geo["radius"]))
    b = geo["border"]
    canvas.paste(Image.new("RGB", (w, h), "#000000"), (0, 0),
                 rounded_mask((w, h), (fx + b, fy + b, fw - 2 * b, fh - 2 * b), geo["radius"] - b))
    sx, sy, sw, sh = geo["screen"]
    shot = screen_image(source, device, (sw, sh))
    canvas.paste(shot, (sx, sy), rounded_mask((sw, sh), (0, 0, sw, sh), geo["screenRadius"]))

    widest = headline(canvas, spec["lines"], geo)
    if widest > fw:
        print(f"  ! {spec['id']}: a {widest}px line is wider than the {fw}px frame")

    target = ROOT / out["name"] / f"{spec['id']}.png"
    target.parent.mkdir(exist_ok=True)
    canvas.save(target, optimize=True)
    return target


def copy_watch(block: dict) -> int:
    target = ROOT / block["name"]
    target.mkdir(exist_ok=True)
    for i, scene in enumerate(block["scenes"], 1):
        shutil.copyfile(HERE / "sources" / block["device"] / f"{scene}.png", target / f"{i:02d}-{scene}.png")
    return len(block["scenes"])


def main(wanted) -> int:
    specs = [f for f in CFG["frames"] if not wanted or f["id"] in wanted]
    for out in CFG["outputs"]:
        done = [p for spec in specs if (p := render(out, spec))]
        print(f"{out['name']}  {len(done)} frame(s) ({out['device']})")
    if not wanted:
        for block in CFG["watch"]:
            print(f"{block['name']}  {copy_watch(block)} capture(s) ({block['device']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
