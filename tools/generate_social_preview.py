"""Render the GitHub social preview (1280x640) and README logo from the icon SVG.

Needs ImageMagick (`convert`) for the SVG and Pillow for the layout.
Output: assets/branding/social-preview.png and assets/branding/logo-256.png
"""
from pathlib import Path
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'assets/branding'
NAVY, SLATE, MINT, WHITE = '#101A2A', '#273C56', '#96DCC1', '#F2F6FA'
MUTED = '#9FB0C3'
BOLD = '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'
REGULAR = '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf'


def icon(size):
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / 'icon.png'
        subprocess.run(['convert', '-background', 'none', '-density', '600',
                        str(BRAND / 'icon.svg'), '-resize', f'{size}x{size}', str(out)], check=True)
        return Image.open(out).convert('RGBA')


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *img.size], radius, fill=255)
    img.putalpha(mask)
    return img


icon(256).save(BRAND / 'logo-256.png')

W, H = 1280, 640
canvas = Image.new('RGB', (W, H), NAVY)
draw = ImageDraw.Draw(canvas)
# Soft slate panel behind the icon keeps it readable at small preview sizes.
draw.rounded_rectangle([80, 140, 440, 500], 64, fill=SLATE)
logo = rounded(icon(320), 56)
canvas.paste(logo, (100, 160), logo)

x = 500
draw.text((x, 150), 'Allowance Privacy', font=ImageFont.truetype(BOLD, 78), fill=WHITE)
draw.text((x, 258), 'Tu presupuesto, solo tuyo', font=ImageFont.truetype(BOLD, 36), fill=MINT)
draw.text((x, 304), 'Your budget, only yours', font=ImageFont.truetype(REGULAR, 32), fill=MINT)

chip_font = ImageFont.truetype(REGULAR, 25)
cx, cy = x, 384
for label in ['PIN + huella / fingerprint', '•••• importes / amounts',
              'Backups AES-256', 'Sin internet / No network']:
    w = draw.textlength(label, font=chip_font) + 36
    if cx + w > W - 60:
        cx, cy = x, cy + 58
    draw.rounded_rectangle([cx, cy, cx + w, cy + 44], 22, outline=MINT, width=2)
    draw.text((cx + 18, cy + 7), label, font=chip_font, fill=WHITE)
    cx += w + 14

draw.text((x, 548), 'Fork de Allowance · GPL-3.0 · github.com/D4vRAM369/AllowancePrivacy',
          font=ImageFont.truetype(REGULAR, 22), fill=MUTED)
canvas.save(BRAND / 'social-preview.png', optimize=True)
print('written', BRAND / 'social-preview.png', BRAND / 'logo-256.png')
