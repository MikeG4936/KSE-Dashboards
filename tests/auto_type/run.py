#!/usr/bin/env python3
"""Run Auto lifecycle contracts with the supported EdgeTX Lua fixture host."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def instrument(source):
    marker = source.rfind('\nreturn {')
    if marker < 0 or 'useLvgl' not in source[marker:]:
        raise ValueError('Expected final widget descriptor')
    exports = ('AUTO_HELI=AUTO_HELI,OPT=OPT,A=A,D=D,S=S,FC=FC,'
               'owner=WidgetOwner,profiles=batteryProfiles,'
               'name=getModelName,cache=getFlightCache,count=getFlightCount,'
               'clear=clearFrameCache,image=resolveModelImagePath')
    return source[:marker] + source[marker:].replace('return {', 'return {\n audit={' + exports + '},', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='kse-auto-') as temp:
        temp = Path(temp)
        for variant in ('KSE4', 'KSE5'):
            dashboard = temp / (variant + '.lua')
            dashboard.write_text(instrument((ROOT / variant / 'main.lua').read_text()))
        for variant in ('KSE4', 'KSE5'):
            for width, height in ((800, 480), (480, 320), (480, 272)):
                fixture = temp / 'fixture.lua'
                fixture.write_text((ROOT / 'tests/behavior/mock.lua').read_text() + '\n'
                    + (ROOT / 'tests/storage/mock.lua').read_text() + '\n'
                    + f'LCD_W={width};LCD_H={height}\n'
                    + 'dashboardPath=' + json.dumps(str(temp / (variant + '.lua'))) + '\n'
                    + 'otherDashboardPath=' + json.dumps(str(temp / ('KSE5.lua' if variant == 'KSE4' else 'KSE4.lua'))) + '\n'
                    + 'variant=' + json.dumps(variant) + '\n'
                    + HERE.joinpath('contracts.lua').read_text())
                result = subprocess.run([str(args.runner.resolve()), str(fixture)], capture_output=True, text=True, timeout=60)
                if result.returncode:
                    raise SystemExit(f'{variant}/{width}x{height}:\n{result.stdout}{result.stderr}')
                print(f'PASS {variant}/{width}x{height}: ' + result.stdout.strip())


if __name__ == '__main__':
    main()
