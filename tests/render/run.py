#!/usr/bin/env python3
"""Run real widget lifecycle/render functions with lightweight LVGL objects."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='kse-render-') as temp:
        for variant in ('KSE4', 'KSE5'):
            for width, height in ((800,480),(480,320),(480,272)):
                path = Path(temp) / 'run.lua'
                path.write_text((ROOT/'tests/behavior/mock.lua').read_text() + '\n'
                    + f'LCD_W={width};LCD_H={height}\n'
                    + 'dashboardPath=' + json.dumps(str(ROOT/variant/'main.lua')) + '\n'
                    + HERE.joinpath('contracts.lua').read_text())
                result = subprocess.run([str(args.runner.resolve()),str(path)], capture_output=True,text=True,timeout=60)
                if result.returncode:
                    raise SystemExit(f'{variant}/{width}x{height}:\n{result.stdout}{result.stderr}')
                print(f'PASS {variant}/{width}x{height}: '+result.stdout.strip())


if __name__ == '__main__':
    main()
