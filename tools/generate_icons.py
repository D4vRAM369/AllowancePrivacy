"""Rebuild Android icons from the SVG using ImageMagick (no app dependency)."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/icon.svg'
RES = ROOT / 'budget_simple/android/app/src/main/res'
ANDROID = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ANDROID)
svg = ET.parse(SOURCE).getroot()
group = svg.find('{http://www.w3.org/2000/svg}g')

def vector(monochrome=False):
    output = ET.Element('vector', {f'{{{ANDROID}}}{k}': v for k, v in
        {'width': '108dp', 'height': '108dp', 'viewportWidth': '108', 'viewportHeight': '108'}.items()})
    layer = ET.SubElement(output, 'group', {f'{{{ANDROID}}}{k}': v for k, v in {'scaleX': '0.85', 'scaleY': '0.85', 'translateX': '8.1', 'translateY': '8.1'}.items()})
    for item in group:
        a = item.attrib
        path = a.get('d')
        if path is None:
            x, y, w, h = (float(a[k]) for k in ('x', 'y', 'width', 'height'))
            r = float(a.get('rx', 0))
            path = f'M{x+r},{y}H{x+w-r}Q{x+w},{y} {x+w},{y+r}V{y+h-r}Q{x+w},{y+h} {x+w-r},{y+h}H{x+r}Q{x},{y+h} {x},{y+h-r}V{y+r}Q{x},{y} {x+r},{y}Z'
        attrs = {'pathData': path, 'fillColor': a.get('fill', '#000000').replace('none', '#00000000')}
        if monochrome:
            # A single opaque silhouette provides the launcher theme mask.
            attrs['fillColor'] = '#FFFFFFFF' if a.get('fill') != 'none' else '#00000000'
        for key, android_key in [('stroke', 'strokeColor'), ('stroke-width', 'strokeWidth')]:
            if key in a:
                attrs[android_key] = '#FFFFFFFF' if monochrome and key == 'stroke' else a[key]
        ET.SubElement(layer, 'path', {f'{{{ANDROID}}}{k}': v for k, v in attrs.items()})
    return ET.tostring(output, encoding='unicode')

for kind in ('foreground', 'monochrome'):
    (RES / f'drawable/ic_privacy_{kind}.xml').write_text(vector(kind == 'monochrome') + '\n')
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    folder = RES / f'mipmap-{density}'
    for name in ('ic_launcher', 'ic_launcher_background', 'ic_launcher_foreground', 'ic_launcher_monochrome'):
        target = folder / f'{name}.png'
        if name == 'ic_launcher':
            subprocess.run(['convert', '-background', 'none', str(SOURCE), '-resize', f'{size}x{size}', str(target)], check=True)
        elif target.exists():
            # Remove upstream layers now replaced by vectors, avoiding stale icons.
            target.unlink()
subprocess.run(['convert', '-background', 'none', str(SOURCE), '-resize', '432x432', str(ROOT/'assets/branding/icon-preview.png')], check=True)
