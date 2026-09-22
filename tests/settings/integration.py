#!/usr/bin/env python3
"""Exercise actual dashboard lifecycle, settings and rendering together."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def instrument(source):
    boundary = source.rfind('\nreturn {')
    exports = 'OPT=OPT,A=A,D=D,S=S,G=G,sensors=sensors,owner=WidgetOwner,profiles=batteryProfiles,store=SettingsStore,menu=SettingsMenu,count=getFlightCount'
    return source[:boundary] + source[boundary:].replace('return {', 'return {audit={' + exports + '},', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='kse-settings-integration-') as directory:
        work = Path(directory)
        for variant in ('KSE4', 'KSE5'):
            (work / (variant + '.lua')).write_text(instrument((ROOT / variant / 'main.lua').read_text()))
        for variant in ('KSE4', 'KSE5'):
            for width, height in ((800, 480), (480, 320), (480, 272)):
                fixture = work / 'run.lua'
                fixture.write_text((ROOT / 'tests/behavior/mock.lua').read_text()
                    + '\nlocal originalFieldInfo=getFieldInfo\n' + (HERE / 'mock.lua').read_text()
                    + '\ngetFieldInfo=originalFieldInfo\n'
                    + f'LCD_W={width};LCD_H={height}\n'
                    + 'dashboardPath=' + json.dumps(str(work / (variant + '.lua'))) + '\n'
                    + 'otherDashboardPath=' + json.dumps(str(work / ('KSE5.lua' if variant == 'KSE4' else 'KSE4.lua'))) + '\n'
                    + (HERE / 'integration.lua').read_text())
                result = subprocess.run([str(args.runner.resolve()), str(fixture)], capture_output=True, text=True, timeout=60)
                if result.returncode:
                    raise SystemExit(f'{variant}/{width}x{height}:\n{result.stdout}{result.stderr}')
                assert 'PASS|complete' in result.stdout, result.stdout
                print(f'PASS {variant}/{width}x{height}: ' + '\n'.join(line for line in result.stdout.splitlines() if line.startswith('PROFILE|')))


if __name__ == '__main__':
    main()
