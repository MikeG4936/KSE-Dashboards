#!/usr/bin/env python3
"""Gate complete dashboard callbacks with real, officially minimized RF Tool Lua."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

from minimize import transform

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PIN = "aaacfe68407c09d49a26c5aa326c00119b378bb0"
CASES = ("normal", "burst", "drop175", "drop176", "save200", "save200max", "save200quiet", "save200open")
MODES = ("combined", "dashboard", "rf", "all")
HARD_BUDGET = 20200


def quote(text):
    """Preserve Lua source bytes without JSON's non-Lua escape sequences."""
    equals = "="
    while "]" + equals + "]" in text:
        equals += "="
    return "[" + equals + "[" + text + "]" + equals + "]"


def read_upstream(source):
    archive = subprocess.check_output(["git", "-C", str(source), "archive", PIN, "src"])
    result = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for item in tar:
            if item.isfile() and item.name.endswith(".lua"):
                name = "/" + item.name.removeprefix("src/")
                result[name] = tar.extractfile(item).read().decode()
    return result


def run(args, work):
    source = read_upstream(args.rf_source)
    # Use the official release transform by default, not a hand-written subset.
    minimizer = None
    if not args.raw_rf:
        source, minimizer = transform(source, args.runner, args.rf_source, PIN, work)
    hashes = {name: hashlib.sha256(text.encode()).hexdigest() for name, text in source.items()}
    bundle = "RF_SOURCE={}\n" + "\n".join(
        "RF_SOURCE[ " + quote(name) + " ]=" + quote(text) for name, text in sorted(source.items()))
    (work / "rf-source.lua").write_text(bundle)
    spec = importlib.util.spec_from_file_location("cpu", ROOT / "tests/cpu_budget/run.py")
    cpu = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cpu)
    mocks = (ROOT / "tests/behavior/mock.lua").read_text() + "\n" + (ROOT / "tests/storage/mock.lua").read_text()
    rows, failures, completed = [], [], []
    dashboard_hashes = {}
    for variant in args.variants:
        source_path = args.source_dir / (variant + ".lua") if args.source_dir else ROOT / variant / "main.lua"
        dashboard_hashes[variant] = hashlib.sha256(source_path.read_bytes()).hexdigest()
        dashboard = work / (variant + ".lua")
        dashboard.write_text(cpu.instrument(source_path.read_text()))
        raw_image = (ROOT / variant / "default.png").read_bytes()
        image = 'defaultImage="' + ''.join('\\%03d' % byte for byte in raw_image[:54]) + '"..string.rep("X",' + str(len(raw_image)-54) + ')\n'
        for case in args.cases:
            for mode in args.modes:
                label = f"{variant}-{case}-{mode}"
                fixture = work / (label + ".lua")
                fixture.write_text(mocks + "\n" + image
                    + "dashboardPath=" + quote(str(dashboard)) + "\n"
                    + "rfLabel=" + quote(str(work / "rf-production.lua")) + "\n"
                    + "variant=" + quote(variant) + ";scenario=" + quote(case) + ";mode=" + quote(mode) + "\n"
                    + "productionBudget=" + str(0 if args.measure_only else HARD_BUDGET) + "\n"
                    + "saveTarget=" + str(0 if args.measure_only else args.save_target) + "\n"
                    + "dofile(" + quote(str(work / "rf-source.lua")) + ")\n"
                    + (HERE / "fixture.lua").read_text())
                result = subprocess.run([str(args.runner), str(fixture)], capture_output=True, text=True, timeout=60)
                (work / (label + ".log")).write_text(result.stdout + result.stderr)
                case_rows = []
                for line in result.stdout.splitlines():
                    if line.startswith("CPU|"):
                        _, step, callback, cost, state, command, shown, decoded, peak_fifo = line.split("|")
                        row = dict(variant=variant, scenario=case, mode=mode, step=int(step),
                            callback=callback, instructions=int(cost), state=state, reply=command,
                            dialogs=int(shown), decoded=int(decoded), peak_fifo=int(peak_fifo))
                        rows.append(row)
                        case_rows.append(row)
                if result.returncode or "COMPLETE|" not in result.stdout:
                    failures.append(label + ":\n" + result.stdout + result.stderr)
                    print("FAIL", label, (result.stderr.strip().splitlines() or ["missing COMPLETE"])[-1])
                else:
                    completed.append(label)
                    peak = max(row["instructions"] for row in case_rows if row["callback"] != "press6")
                    saves = [row["instructions"] for row in case_rows if row["callback"] == "save"]
                    print(f"PASS {label}: peak {peak}" + (f", save peak {max(saves)} over {len(saves)} callbacks" if saves else ""))
    # Optional independent attribution must match complete source-filtered totals.
    component_checks = 0
    if all(mode in args.modes for mode in ("dashboard", "rf", "combined")):
        keyed = {(r["variant"], r["scenario"], r["step"], r["callback"], r["mode"]): r for r in rows}
        for row in rows:
            if row["mode"] != "combined":
                continue
            key = (row["variant"], row["scenario"], row["step"], row["callback"])
            if all(key + (mode,) in keyed for mode in ("dashboard", "rf")):
                if row["instructions"] != sum(keyed[key + (mode,)]["instructions"] for mode in ("dashboard", "rf")):
                    failures.append("Attribution mismatch: " + repr(key))
                component_checks += 1
    return dict(rf_pin=PIN, dashboard_hashes=dashboard_hashes, rf_source_hashes=hashes,
                rf_flavor="raw-pinned-source" if args.raw_rf else "official-minimized", minimizer=minimizer,
                cases=args.cases, modes=args.modes, measure_only=args.measure_only,
                hard_budget=0 if args.measure_only else HARD_BUDGET,
                save_target=0 if args.measure_only else args.save_target,
                component_equality_checks=component_checks, completed=completed,
                measurements=rows, failures=failures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    parser.add_argument("--rf-source", required=True, type=Path, help="Git repository containing the pinned RF commit")
    parser.add_argument("--source-dir", type=Path, help="Optional frozen KSE4.lua/KSE5.lua baseline directory")
    parser.add_argument("--modes", nargs="+", choices=MODES, default=["combined"])
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    parser.add_argument("--variants", nargs="+", choices=("KSE4", "KSE5"), default=["KSE4", "KSE5"])
    parser.add_argument("--measure-only", action="store_true", help="Record an ungated baseline")
    parser.add_argument("--save-target", type=int, default=15000, help="Combined save-callback margin (0 disables only this margin)")
    parser.add_argument("--raw-rf", action="store_true", help="Diagnostic raw-source comparison; default uses official minimizer")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--artifacts", type=Path, help="Retain fixtures and per-case logs in this output directory")
    args = parser.parse_args()
    args.runner = args.runner.resolve()
    if args.save_target < 0:
        parser.error("--save-target must be nonnegative")
    if not args.measure_only and "combined" not in args.modes:
        parser.error("gated runs require combined mode; use --measure-only for component diagnostics")
    if args.artifacts:
        work = args.artifacts.resolve()
        work.mkdir(parents=True, exist_ok=True)
        report = run(args, work)
    else:
        with tempfile.TemporaryDirectory(prefix="kse-rf-cpu-") as directory:
            report = run(args, Path(directory))
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n")
    if report["failures"]:
        raise SystemExit("\n".join(report["failures"]))
    print(f"PASS {len(report['completed'])} complete RF callback scenarios")


if __name__ == "__main__":
    main()
