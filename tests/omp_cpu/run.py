#!/usr/bin/env python3
"""Check OMP Auto retained UI and complete callback CPU margins."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SCENARIOS = (
    'fresh-m1', 'fresh-m2', 'connected-create-m1', 'connected-create-m2',
    'transition-visible', 'transition-hidden',
    'transition-visible-theme9', 'transition-hidden-theme9',
    'reconnect-visible', 'reconnect-hidden',
    'save-retry-candidate-visible', 'save-retry-confirm-visible',
    'save-retry-confirm-hidden',
)


def instrument(source):
    # Reuse the complete-callback suite's exports and boundary fixture.
    spec = importlib.util.spec_from_file_location('cpu_budget', ROOT / 'tests/cpu_budget/run.py')
    cpu = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cpu)
    result = cpu.instrument(source)
    marker = 'audit={AUTO_HELI='
    if result.count(marker) != 1:
        raise ValueError('Expected CPU audit export')
    return result.replace(marker, 'audit={OMP_AUTO=OMP_AUTO,AUTO_HELI=', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--source-dir', type=Path,
                        help='Optional frozen KSE4.lua/KSE5.lua baseline directory')
    parser.add_argument('--measure-only', action='store_true',
                        help='Disable CPU gates; semantic assertions still apply')
    parser.add_argument('--target', type=int, default=15000,
                        help='Dashboard instruction margin (0 disables the margin gate)')
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    if args.target < 0:
        parser.error('--target must be nonnegative')
    budget = 0 if args.measure_only else 20200
    target = 0 if args.measure_only else args.target
    rows, failures, sources = [], [], {}
    mocks = (ROOT / 'tests/behavior/mock.lua').read_text() + '\n' + (ROOT / 'tests/storage/mock.lua').read_text()
    boundaries = (ROOT / 'tests/cpu_budget/fixture.lua').read_text()
    contracts = (HERE / 'contracts.lua').read_text()
    with tempfile.TemporaryDirectory(prefix='kse-omp-cpu-') as directory:
        work = Path(directory)
        for variant in ('KSE4', 'KSE5'):
            source = args.source_dir / (variant + '.lua') if args.source_dir else ROOT / variant / 'main.lua'
            sources[variant] = dict(path=str(source), sha256=hashlib.sha256(source.read_bytes()).hexdigest())
            dashboard = work / (variant + '.lua')
            dashboard.write_text(instrument(source.read_text()))
            data = (ROOT / variant / 'default.png').read_bytes()
            image = 'defaultImage="' + ''.join('\\%03d' % byte for byte in data[:54]) + '"..string.rep("X",' + str(len(data)-54) + ')\n'
            for width, height in ((800, 480), (480, 320), (480, 272)):
                for slots in (60, 75):
                    for scenario in SCENARIOS:
                        fixture = work / 'fixture.lua'
                        fixture.write_text(mocks + '\n' + image
                            + f'LCD_W={width};LCD_H={height};sensorSlots={slots}\n'
                            + 'dashboardPath=' + json.dumps(str(dashboard)) + '\n'
                            + 'variant=' + json.dumps(variant) + '\n'
                            + 'scenario=' + json.dumps(scenario) + '\n'
                            + f'cpuBudget={budget};cpuTarget={target}\n'
                            + boundaries + '\n' + contracts)
                        result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                                capture_output=True, text=True, timeout=60)
                        case = f'{variant}/{width}x{height}/{slots}-slots/{scenario}'
                        case_rows = []
                        for line in result.stdout.splitlines():
                            if line.startswith('CPU|'):
                                _, phase, callback, instructions = line.split('|')
                                row = dict(variant=variant, width=width, height=height,
                                           sensor_slots=slots, scenario=scenario, phase=phase,
                                           callback=callback, instructions=int(instructions))
                                rows.append(row)
                                case_rows.append(row)
                        if result.returncode:
                            failures.append(case + ':\n' + result.stdout + result.stderr)
                            print('FAIL', case)
                        else:
                            print(f'PASS {case}: peak {max(row["instructions"] for row in case_rows)} dashboard instructions')
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(dict(measure_only=args.measure_only, target=target,
            hard_budget=budget, sources=sources, measurements=rows, failures=failures), indent=2)+'\n')
    if failures:
        raise SystemExit('\n'.join(failures))


if __name__ == '__main__':
    main()
