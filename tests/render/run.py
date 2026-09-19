#!/usr/bin/env python3
"""Run real widget lifecycle/render functions with lightweight LVGL objects."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
from html import escape

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def save_previews(output, destination, variant, width, height):
    """Render actual retained rectangle properties; no native LVGL rasterizer."""
    groups = {}
    for line in output.splitlines():
        if not line.startswith('ICON|'):
            continue
        theme, rssi, bg, x, y, w, h, color, filled, radius = map(float, line.split('|')[1:])
        groups.setdefault((int(theme), int(rssi), int(bg)), []).append(
            (x, y, w, h, int(color), int(filled), radius))
    destination.mkdir(parents=True, exist_ok=True)
    for (theme, rssi, bg), shapes in groups.items():
        left = min(s[0] for s in shapes) - 5
        top = min(s[1] for s in shapes) - 5
        right = max(s[0]+s[2] for s in shapes) + 5
        bottom = max(s[1]+s[3] for s in shapes) + 5
        title = f'{variant} {width}x{height}, theme {theme}, RSSI {rssi}'
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{(right-left)*4}" '
               f'height="{(bottom-top)*4}" viewBox="{left} {top} {right-left} {bottom-top}">',
               f'<title>{escape(title)} — retained geometry preview</title>',
               f'<rect x="{left}" y="{top}" width="{right-left}" height="{bottom-top}" fill="#{bg:06x}"/>']
        for x, y, w, h, color, filled, radius in shapes:
            style = f'fill="#{color:06x}"' if filled else f'fill="none" stroke="#{color:06x}" stroke-width="1"'
            svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" {style}/>')
        svg.append('</svg>')
        (destination/f'{variant}-{width}x{height}-theme{theme}-rssi{rssi}.svg').write_text('\n'.join(svg))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--preview-dir', type=Path,
                        help='Optional SVG previews of actual retained status-icon geometry')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='kse-render-') as temp:
        for variant in ('KSE4', 'KSE5'):
            source = (ROOT/variant/'main.lua').read_text()
            marker = source.rfind('\nreturn {')
            assert marker >= 0 and 'useLvgl' in source[marker:]
            ui = 'V' if variant == 'KSE4' else 'w.ui'
            inactive = 'C_LINE' if variant == 'KSE4' else 'C_BORDER'
            background = 'C_BG' if variant == 'KSE4' else 'C_TOP'
            dashboard = Path(temp) / f'{variant}.lua'
            dashboard.write_text(source[:marker]
                + f'\n__txTestUi=function(w) return {ui}, G, C_TEXT, {inactive}, {background} end\n'
                + source[marker:])
            for width, height in ((800,480),(480,320),(480,272)):
                path = Path(temp) / 'run.lua'
                path.write_text((ROOT/'tests/behavior/mock.lua').read_text() + '\n'
                    + f'LCD_W={width};LCD_H={height}\n'
                    + 'dashboardPath=' + json.dumps(str(dashboard)) + '\n'
                    + HERE.joinpath('contracts.lua').read_text())
                result = subprocess.run([str(args.runner.resolve()),str(path)], capture_output=True,text=True,timeout=60)
                if result.returncode:
                    raise SystemExit(f'{variant}/{width}x{height}:\n{result.stdout}{result.stderr}')
                if args.preview_dir:
                    save_previews(result.stdout, args.preview_dir, variant, width, height)
                summary = '\n'.join(line for line in result.stdout.splitlines()
                                    if not line.startswith('ICON|'))
                print(f'PASS {variant}/{width}x{height}: '+summary.strip())


if __name__ == '__main__':
    main()
