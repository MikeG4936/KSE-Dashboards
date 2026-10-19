#!/usr/bin/env python3
"""Check complete dashboard callback instruction margins using the pinned host."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SCENARIOS = ("auto-type-change", "auto-type-change-theme9",
             "auto-initial-electric", "auto-initial-electric-theme9",
             "model-takeover-20", "model-takeover-200", "counter-switch",
             "counter-switch-max-bytes", "comment-heavy-max-bytes",
             "backup-recovery", "loading-handoff")


def instrument(source):
    marker = source.rfind('\nreturn {')
    if marker < 0 or 'useLvgl' not in source[marker:]:
        raise ValueError('Expected final widget descriptor')
    exports = ('AUTO_HELI=AUTO_HELI,OPT=OPT,A=A,D=D,S=S,FC=FC,'
               'owner=WidgetOwner,profiles=batteryProfiles,Storage=Storage,'
               'store=function()return flightStore end,name=getModelName,'
               'cache=getFlightCache,count=getFlightCount,'
               'view=function()return V end,geometry=G')
    return source[:marker] + source[marker:].replace('return {', 'return {\n audit={' + exports + '},', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--source-dir', type=Path, help='Optional frozen KSE4.lua/KSE5.lua baseline directory')
    parser.add_argument('--measure-only', action='store_true', help='Report baseline without budget gates')
    parser.add_argument('--target', type=int, default=15000, help='Dashboard margin (0 disables the margin gate)')
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    if args.target < 0:
        parser.error('--target must be nonnegative')
    rows, failures = [], []
    sources = {}
    with tempfile.TemporaryDirectory(prefix='kse-cpu-budget-') as directory:
        work = Path(directory)
        mocks = (ROOT / 'tests/behavior/mock.lua').read_text() + '\n' + (ROOT / 'tests/storage/mock.lua').read_text()
        for variant in ('KSE4', 'KSE5'):
            source = args.source_dir / (variant + '.lua') if args.source_dir else ROOT / variant / 'main.lua'
            sources[variant] = dict(path=str(source), sha256=hashlib.sha256(source.read_bytes()).hexdigest())
            dashboard = work / (variant + '.lua')
            dashboard.write_text(instrument(source.read_text()))
            data = (ROOT / variant / 'default.png').read_bytes()
            image = 'defaultImage="' + ''.join('\\%03d' % byte for byte in data[:54]) + '"..string.rep("X",' + str(len(data)-54) + ')\n'
            for width, height in ((800, 480), (480, 320), (480, 272)):
                scenarios = SCENARIOS
                if variant == 'KSE4' and width == 800:
                    scenarios += ('partial-zone', 'partial-zone-theme9')
                for scenario in scenarios:
                    fixture = work / 'fixture.lua'
                    fixture.write_text(mocks + '\n' + image
                        + f'LCD_W={width};LCD_H={height}\n'
                        + 'dashboardPath=' + json.dumps(str(dashboard)) + '\n'
                        + 'variant=' + json.dumps(variant) + '\n'
                        + 'scenario=' + json.dumps(scenario) + '\n'
                        + f'cpuBudget={0 if args.measure_only else 20200};cpuTarget={0 if args.measure_only else args.target}\n'
                        + (HERE / 'fixture.lua').read_text() + '\n' + (HERE / 'contracts.lua').read_text())
                    result = subprocess.run([str(args.runner.resolve()), str(fixture)], capture_output=True, text=True, timeout=60)
                    case = f'{variant}/{width}x{height}/{scenario}'
                    for line in result.stdout.splitlines():
                        if line.startswith('CPU|'):
                            _, label, callback, instructions = line.split('|')
                            rows.append(dict(variant=variant, width=width, height=height,
                                             scenario=label, callback=callback, instructions=int(instructions)))
                    if result.returncode:
                        failures.append(case + ':\n' + result.stdout + result.stderr)
                    else:
                        peak = max(row['instructions'] for row in rows if row['variant'] == variant
                                   and row['width'] == width and row['height'] == height and row['scenario'] == scenario)
                        print(f'PASS {case}: peak {peak} dashboard instructions')
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(dict(measure_only=args.measure_only,
            target=0 if args.measure_only else args.target,
            hard_budget=0 if args.measure_only else 20200,
            sources=sources, measurements=rows, failures=failures), indent=2)+'\n')
    if failures:
        raise SystemExit('\n'.join(failures))


if __name__ == '__main__':
    main()
