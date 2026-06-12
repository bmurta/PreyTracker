#!/usr/bin/env python3
"""PreyTracker texture pack: SVG -> 32-bit RGBA TGA (power-of-two, WoW-ready)."""
import io, os, struct
import cairosvg
from PIL import Image

OUT = "media"
os.makedirs(OUT, exist_ok=True)

def make(name, w, h, body):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
    png = cairosvg.svg2png(bytestring=svg.encode())
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    assert img.size == (w, h), f"{name}: got {img.size}"
    path = os.path.join(OUT, name)
    img.save(path, format="TGA", rle=False)
    return path

W = "#ffffff"

# ---------------------------------------------------------------- chrome (white = tintable)
# Nine-slice rounded panel/card background. Use SetTextureSliceMargins(16,16,16,16).
make("panel_bg.tga", 64, 64,
     f'<rect x="0" y="0" width="64" height="64" rx="16" fill="{W}"/>')

# Nine-slice rounded border (3px stroke, inset so the stroke isn't clipped).
make("panel_border.tga", 64, 64,
     f'<rect x="1.5" y="1.5" width="61" height="61" rx="15" fill="none" stroke="{W}" stroke-width="3"/>')

# Pill background / border (fully rounded ends). Slice margins 16/8.
make("pill_bg.tga", 64, 32,
     f'<rect x="0" y="0" width="64" height="32" rx="16" fill="{W}"/>')
make("pill_border.tga", 64, 32,
     f'<rect x="1.25" y="1.25" width="61.5" height="29.5" rx="14.75" fill="none" stroke="{W}" stroke-width="2.5"/>')

# Soft radial glow (status dots, hover halos; use BLEND "ADD").
make("glow_radial.tga", 128, 128, (
    '<defs><radialGradient id="g"><stop offset="0" stop-color="#ffffff" stop-opacity="1"/>'
    '<stop offset="0.45" stop-color="#ffffff" stop-opacity="0.55"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>'
    '<circle cx="64" cy="64" r="64" fill="url(#g)"/>'))

# Rounded-rect outer glow ring for the selected card (nine-slice margins 32).
rings = "".join(
    f'<rect x="{16 + i*2.2}" y="{16 + i*2.2}" width="{96 - i*4.4}" height="{96 - i*4.4}" '
    f'rx="{20 - i*1.5}" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-opacity="{0.34 - i*0.055}"/>'
    for i in range(6))
make("card_glow.tga", 128, 128, rings)

# ---------------------------------------------------------------- model stage
# Elliptical zone-color backdrop (tint with zone color, BLEND "ADD" or alpha).
make("zone_glow.tga", 256, 128, (
    '<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/>'
    '<stop offset="0.6" stop-color="#ffffff" stop-opacity="0.35"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>'
    '<ellipse cx="128" cy="64" rx="128" ry="64" fill="url(#g)"/>'))

# Pedestal platform: soft fill + brighter rim.
make("platform.tga", 256, 64, (
    '<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>'
    '<stop offset="0.8" stop-color="#ffffff" stop-opacity="0.18"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>'
    '<ellipse cx="128" cy="32" rx="120" ry="26" fill="url(#g)"/>'
    '<ellipse cx="128" cy="32" rx="118" ry="24" fill="none" stroke="#ffffff" stroke-opacity="0.85" stroke-width="2.5"/>'))

# ---------------------------------------------------------------- silhouettes (white = tintable)
SC = 'fill="#ffffff"'
SS = 'stroke="#ffffff"'
sils = {
"sil_stag.tga": (
    f'<g transform="translate(8,0) scale(2)">'
    f'<path {SC} d="M24 28 C22 22 28 18 33 21 L38 24 C50 19 66 19 76 23 C86 21 93 26 93 33 C93 40 88 42 86 47 L85 60 L80 60 L80 48 C70 52 56 52 47 48 L45 60 L40 60 L40 46 C32 44 26 40 26 34 Z"/>'
    f'<path fill="none" {SS} stroke-width="2.6" stroke-linecap="round" d="M30 21 C26 12 18 10 16 4 M30 21 C31 11 38 8 40 3 M30 20 C27 13 21 11 19 5 M30 20 C32 12 37 10 38 6"/></g>'),
"sil_cat.tga": (
    f'<g transform="translate(8,0) scale(2)">'
    f'<path {SC} d="M14 42 C10 36 15 31 22 33 L30 35 C42 29 60 29 71 33 C82 31 92 35 94 42 C96 49 89 52 85 50 L88 60 L83 60 L79 51 C68 55 54 55 45 51 L43 60 L38 60 L36 49 C26 49 18 48 14 42 Z"/>'
    f'<path fill="none" {SS} stroke-width="3.5" stroke-linecap="round" d="M94 43 C103 40 108 32 107 24"/>'
    f'<path {SC} d="M20 34 L15 26 L25 30 Z"/></g>'),
"sil_bat.tga": (
    f'<g transform="translate(8,0) scale(2)">'
    f'<path {SC} d="M60 28 C50 16 30 12 12 18 C24 24 28 25 32 33 C40 29 46 31 50 37 C54 33 66 33 70 37 C74 31 80 29 88 33 C92 25 96 24 108 18 C90 12 70 16 60 28 Z"/>'
    f'<path {SC} d="M60 26 C55 30 53 38 55 46 L60 56 L65 46 C67 38 65 30 60 26 Z"/>'
    f'<path {SC} d="M54 24 L50 15 L58 20 Z M66 24 L70 15 L62 20 Z"/></g>'),
"sil_void.tga": (
    f'<g transform="translate(8,0) scale(2)">'
    f'<path {SC} d="M60 30 C75 30 86 38 86 47 C86 55 74 58 60 58 C46 58 34 55 34 47 C34 38 45 30 60 30 Z"/>'
    f'<path fill="none" {SS} stroke-width="3.4" stroke-linecap="round" d="M42 34 C36 26 38 18 31 13 M52 30 C50 20 44 16 44 9 M68 30 C70 20 76 16 76 9 M78 34 C84 26 82 18 89 13"/></g>'),
}
for n, body in sils.items():
    make(n, 256, 128, body)

# ---------------------------------------------------------------- icons (16-grid scaled to 64)
G = '<g transform="scale(4)">'

make("icon_paw.tga", 64, 64, G +
     '<g fill="#ffffff"><ellipse cx="8" cy="10.2" rx="3.6" ry="2.9"/>'
     '<circle cx="3.8" cy="6.6" r="1.6"/><circle cx="6.6" cy="4.7" r="1.6"/>'
     '<circle cx="9.4" cy="4.7" r="1.6"/><circle cx="12.2" cy="6.6" r="1.6"/></g></g>')

make("icon_trophy.tga", 64, 64, G +
     '<path d="M4.5 2h7v4a3.5 3.5 0 01-7 0V2z" fill="#e8c558" stroke="#9a7b1e" stroke-width="0.9"/>'
     '<path d="M4.5 3H2.6c0 2.2 1 3.4 2.4 3.7M11.5 3h1.9c0 2.2-1 3.4-2.4 3.7" fill="none" stroke="#9a7b1e" stroke-width="1.1"/>'
     '<rect x="7" y="9.3" width="2" height="2.2" fill="#caa84f"/>'
     '<rect x="4.8" y="11.5" width="6.4" height="2" rx="0.7" fill="#e8c558" stroke="#9a7b1e" stroke-width="0.8"/></g>')

make("icon_gem.tga", 64, 64, G +
     '<path d="M8 1l5 5.5L8 15 3 6.5 8 1z" fill="#ff5555" stroke="#a32222" stroke-width="1"/>'
     '<path d="M8 1L5.5 6.5 8 15" fill="none" stroke="#ffaaaa" stroke-width="0.5" stroke-opacity="0.8"/></g>')

make("icon_check.tga", 64, 64, G +
     '<path d="M3 8.5 L6.5 12 L13 4.5" fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></g>')

make("icon_reload.tga", 64, 64, G +
     '<g fill="none" stroke="#ffffff" stroke-width="1.7" stroke-linecap="round">'
     '<path d="M13 8a5 5 0 11-1.5-3.6"/><path d="M13 1.8v3h-3" stroke-linejoin="round"/></g></g>')

make("icon_close.tga", 32, 32,
     '<path d="M8 8 L24 24 M24 8 L8 24" fill="none" stroke="#ffffff" stroke-width="3.5" stroke-linecap="round"/>')

make("icon_dot.tga", 32, 32, (
    '<defs><radialGradient id="g"><stop offset="0" stop-color="#ffffff"/>'
    '<stop offset="0.75" stop-color="#ffffff"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>'
    '<circle cx="16" cy="16" r="15" fill="url(#g)"/>'))

make("icon_skull.tga", 64, 64, G +
     '<g fill="#ffffff"><path d="M8 2a5 5 0 00-5 5c0 1.8.9 3.2 2.2 4.1V13a1 1 0 001 1h3.6a1 1 0 001-1v-1.9A5 5 0 0013 7a5 5 0 00-5-5z"/></g>'
     '<circle cx="6" cy="7" r="1.2" fill="#000000" fill-opacity="0"/></g>')

make("icon_target.tga", 64, 64, G +
     '<circle cx="8" cy="8" r="5.5" fill="none" stroke="#ffffff" stroke-width="1.6"/>'
     '<circle cx="8" cy="8" r="2" fill="#ffffff"/></g>')

make("pin.tga", 64, 64,
     '<g transform="translate(10,4) scale(2)">'
     '<path d="M11 0C17 0 22 5 22 11 22 17 11 26 11 26 11 26 0 17 0 11 0 5 5 0 11 0z" fill="#ffffff"/></g>')

# skull with proper cutout eyes (transparent holes via even-odd path)
make("icon_skull.tga", 64, 64, G +
     '<path fill="#ffffff" fill-rule="evenodd" d="M8 2a5 5 0 00-5 5c0 1.8.9 3.2 2.2 4.1V13a1 1 0 001 1h3.6a1 1 0 001-1v-1.9A5 5 0 0013 7a5 5 0 00-5-5z '
     'M6 5.8a1.2 1.2 0 110 2.4 1.2 1.2 0 010-2.4z M10 5.8a1.2 1.2 0 110 2.4 1.2 1.2 0 010-2.4z '
     'M7.3 9.2h1.4v1.6h-1.4z"/></g>')

# ---------------------------------------------------------------- prey crystal logo
CRYSTAL = (
    '<defs><radialGradient id="aura" cx="0.5" cy="0.52" r="0.5">'
    '<stop offset="0" stop-color="#ff2235" stop-opacity="0.55"/>'
    '<stop offset="0.55" stop-color="#d41830" stop-opacity="0.28"/>'
    '<stop offset="1" stop-color="#d41830" stop-opacity="0"/></radialGradient>'
    '<radialGradient id="wisp" cx="0.5" cy="0.5" r="0.5">'
    '<stop offset="0" stop-color="#ff3346" stop-opacity="0.30"/>'
    '<stop offset="1" stop-color="#ff3346" stop-opacity="0"/></radialGradient>'
    '<linearGradient id="topfacet" x1="0" y1="0" x2="0.4" y2="1">'
    '<stop offset="0" stop-color="#ff8b94"/><stop offset="1" stop-color="#f24557"/></linearGradient></defs>'
    '<circle cx="32" cy="33" r="31" fill="url(#aura)"/>'
    '<ellipse cx="14" cy="40" rx="10" ry="16" fill="url(#wisp)"/>'
    '<ellipse cx="50" cy="26" rx="9" ry="15" fill="url(#wisp)"/>'
    '<path d="M33 4 L46 21 L47 40 C47 51 40 59 32 59 C23 59 17 50 17 40 L19 19 Z" fill="#6b1226"/>'
    '<path d="M33 4 L46 21 L34 26 Z" fill="url(#topfacet)"/>'
    '<path d="M33 4 L34 26 L19 19 Z" fill="#e23a4e"/>'
    '<path d="M19 19 L34 26 L17 40 Z" fill="#a82440"/>'
    '<path d="M46 21 L47 40 L34 26 Z" fill="#c92c44"/>'
    '<path d="M17 40 L34 26 L33 44 Z" fill="#871a32"/>'
    '<path d="M34 26 L47 40 L33 44 Z" fill="#9e2038"/>'
    '<path d="M17 40 C17 50 23 59 32 59 L33 44 Z" fill="#4a0a1c"/>'
    '<path d="M33 44 L32 59 C40 59 47 51 47 40 Z" fill="#5e0f24"/>'
    '<path d="M33 4 L40 13 L35 15 Z" fill="#ffd9dd" fill-opacity="0.85"/>'
    '<path d="M21 21 L31 25 L20 33 Z" fill="#ff6b78" fill-opacity="0.35"/>')
make("icon_prey.tga", 64, 64, CRYSTAL)

# ---------------------------------------------------------------- validate headers
print(f"{'file':<22}{'dims':<12}{'bpp':<5}pow2  bytes")
ok = True
for f in sorted(os.listdir(OUT)):
    if not f.endswith(".tga"):
        continue
    d = open(os.path.join(OUT, f), "rb").read()
    w, h = struct.unpack("<HH", d[12:16])
    bpp = d[16]
    imgtype = d[2]
    p2 = (w & (w - 1) == 0) and (h & (h - 1) == 0)
    ok &= p2 and bpp == 32 and imgtype == 2  # 2 = uncompressed truecolor
    print(f"{f:<22}{f'{w}x{h}':<12}{bpp:<5}{str(p2):<6}{len(d)}")
print("ALL VALID" if ok else "!! INVALID FILES PRESENT")

# ---------------------------------------------------------------- contact sheet
files = sorted(f for f in os.listdir(OUT) if f.endswith(".tga"))
cols = 5
cell = 150
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (90, 90, 100))
from PIL import ImageDraw
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(os.path.join(OUT, f)).convert("RGBA")
    im.thumbnail((cell - 20, cell - 20))
    cx = (i % cols) * cell
    cy = (i // cols) * (cell + 18)
    # checker behind
    for yy in range(0, cell, 10):
        for xx in range(0, cell, 10):
            if (xx // 10 + yy // 10) % 2:
                dr.rectangle([cx + xx, cy + yy, cx + xx + 10, cy + yy + 10], fill=(70, 70, 80))
    sheet.paste(im, (cx + (cell - im.width) // 2, cy + (cell - 18 - im.height) // 2), im)
    dr.text((cx + 6, cy + cell - 14), f, fill=(255, 255, 255))
sheet.save("tga_contact_sheet.png")
print("sheet written")
