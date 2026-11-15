import math, sys
from PIL import Image, ImageDraw
OUT = sys.argv[1]
RED = (215, 38, 61, 255); WHITE = (255, 255, 255, 255)
SS = 4; N = 1024 * SS

def glyph(d, cx, cy, scale):
    """Yen sign + circular 'return' arrow, centred at (cx,cy). scale=1 -> fits ~760px box at 1024."""
    s = scale * SS
    w = int(54 * s)  # stroke width
    # circular arrow: arc from 200deg sweeping clockwise to 140deg (gap at left-bottom)
    R = 350 * s
    box = [cx - R, cy - R, cx + R, cy + R]
    start, end = -40, 228  # PIL angles: clockwise from 3 o'clock
    d.arc(box, start, end, fill=WHITE, width=w)
    # round cap at the tail
    a = math.radians(start); r = w / 2
    tx, ty = cx + (R - w / 2) * math.cos(a), cy + (R - w / 2) * math.sin(a)
    d.ellipse([tx - r, ty - r, tx + r, ty + r], fill=WHITE)
    # arrowhead at the end (pointing along clockwise direction)
    a = math.radians(end)
    px, py = cx + (R - w / 2) * math.cos(a), cy + (R - w / 2) * math.sin(a)
    tang = (-math.sin(a), math.cos(a))  # clockwise tangent
    norm = (math.cos(a), math.sin(a))
    L, H = 150 * s, 80 * s
    tip = (px + tang[0] * L * 0.75, py + tang[1] * L * 0.75)
    b1 = (px + norm[0] * H - tang[0] * L * 0.25, py + norm[1] * H - tang[1] * L * 0.25)
    b2 = (px - norm[0] * H - tang[0] * L * 0.25, py - norm[1] * H - tang[1] * L * 0.25)
    d.polygon([tip, b1, b2], fill=WHITE)
    # yen sign
    yw = int(52 * s)
    top = cy - 175 * s; mid = cy + 5 * s; bot = cy + 190 * s; half = 125 * s
    for x0 in (cx - half, cx + half):
        d.line([(x0, top), (cx, mid)], fill=WHITE, width=yw)
    d.line([(cx, mid - 10 * s), (cx, bot)], fill=WHITE, width=yw)
    for y in (cy + 40 * s, cy + 115 * s):
        d.rectangle([cx - 110 * s, y - 22 * s, cx + 110 * s, y + 22 * s], fill=WHITE)
    d.ellipse([cx - yw / 2, mid - yw / 2, cx + yw / 2, mid + yw / 2], fill=WHITE)
    # round the arm tops
    for x0 in (cx - half, cx + half):
        d.ellipse([x0 - yw / 2, top - yw / 2, x0 + yw / 2, top + yw / 2], fill=WHITE)
    d.rectangle([cx - yw / 2, bot - yw / 2, cx + yw / 2, bot], fill=WHITE)

def save(img, name, size=1024):
    img.resize((size, size), Image.LANCZOS).save(f"{OUT}/{name}")

# 1) full icon (iOS / legacy Android / store): opaque red square, glyph
img = Image.new("RGBA", (N, N), RED); glyph(ImageDraw.Draw(img), N / 2, N / 2, 1.0)
save(img.convert("RGB"), "app_icon.png")
# 2) adaptive foreground: transparent, glyph inside safe zone (66% of 108dp)
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0)); glyph(ImageDraw.Draw(fg), N / 2, N / 2, 0.80)
save(fg, "app_icon_foreground.png")
# 3) Play Store 512 icon
save(img.convert("RGB"), "play_icon_512.png", 512)
