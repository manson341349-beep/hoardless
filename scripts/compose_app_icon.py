"""Remakes Sources/Hoardless/Resources/Art/app-icon.png: a squircle plate (824 px on a 1024 canvas, Apple's grid)
with the mascot cutout, clipped to the plate. Needs Pillow. Usage: python3 compose_app_icon.py <cutout.png>
Writes icon-A-ink.png (the one in use), icon-B-paper.png and preview-sizes.png in the current folder.
The cutout is described in docs/design/asset-prompts.md (App icon)."""
import sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

W, BODY = 1024, 824
OFF = (W - BODY) // 2

def squircle_mask(size, scale=4, n=5.0):
    big = size * scale
    m = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(m)
    r = big / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        x = r + r * math.copysign(abs(c) ** (2 / n), c)
        y = r + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def plate(style):
    p = Image.new("RGB", (BODY, BODY))
    px = p.load()
    if style == "ink":
        top, bottom = (0x14, 0x1a, 0x0e), (0x24, 0x3a, 0x12)
    else:
        top, bottom = (0xF6, 0xF4, 0xEC), (0xE2, 0xDE, 0xCF)
    for y in range(BODY):
        c = lerp(top, bottom, y / (BODY - 1))
        for x in range(BODY): px[x, y] = c
    # lime glow behind where the acorn sits (lower left)
    glow = Image.new("L", (BODY, BODY), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy, rad = int(BODY * 0.36), int(BODY * 0.70), int(BODY * 0.42)
    gd.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=200 if style == "ink" else 120)
    glow = glow.filter(ImageFilter.GaussianBlur(BODY * 0.12))
    lime = Image.new("RGB", (BODY, BODY), (0xa3, 0xd2, 0x33))
    p = Image.composite(lime, p, glow.point(lambda v: int(v * (0.55 if style == "ink" else 0.35))))
    return p

def icon(cut_path, style, out):
    canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    mask = squircle_mask(BODY)
    body = plate(style).convert("RGBA")
    cut = Image.open(cut_path).convert("RGBA")
    cut = cut.crop(cut.getchannel("A").getbbox())
    target_w = int(BODY * 0.92)
    h = int(cut.height * target_w / cut.width)
    cut = cut.resize((target_w, h), Image.LANCZOS)
    x = (BODY - target_w) // 2 + int(BODY * 0.02)
    y = BODY - h + int(BODY * 0.06)  # sits on the bottom edge, slightly cut off by the plate
    body.alpha_composite(cut, (x, max(y, int(BODY * 0.03))))
    # thin inner highlight along the edge
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    hl = Image.new("RGBA", (BODY, BODY), (255, 255, 255, 0))
    hl.putalpha(edge.point(lambda v: int(v * (0.18 if style == "ink" else 0.5))))
    body.alpha_composite(hl)
    body.putalpha(mask)
    # soft drop shadow, as in Apple's template
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sm = Image.new("L", (W, W), 0)
    sm.paste(mask, (OFF, OFF + 12))
    shadow.putalpha(sm.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.35)))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(body, (OFF, OFF))
    canvas.save(out)
    return canvas

def preview(icons, labels, out):
    sizes = [16, 32, 64, 128, 256]
    row_h = 300
    sheet = Image.new("RGB", (60 + sum(s + 40 for s in sizes), row_h * len(icons) * 2), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    y = 0
    for im, label in zip(icons, labels):
        for bg in [(236, 236, 236), (40, 40, 40)]:
            d.rectangle((0, y, sheet.width, y + row_h), fill=bg)
            d.text((10, y + 8), label, fill=(128, 128, 128))
            x = 40
            for s in sizes:
                small = im.resize((s, s), Image.LANCZOS)
                sheet.paste(small, (x, y + (row_h - s) // 2), small)
                x += s + 40
            y += row_h
    sheet.save(out)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 compose_app_icon.py <cutout.png>")
    cut = sys.argv[1]
    a = icon(cut, "ink", "icon-A-ink.png")
    b = icon(cut, "paper", "icon-B-paper.png")
    preview([a, b], ["A ink", "B paper"], "preview-sizes.png")
    side = Image.new("RGBA", (W * 2 + 60, W + 40), (128, 128, 128, 255))
    side.alpha_composite(a, (20, 20)); side.alpha_composite(b, (W + 40, 20))
    side.convert("RGB").resize(((W * 2 + 60) // 2, (W + 40) // 2), Image.LANCZOS).save("side-by-side.png")
    print("ok")
