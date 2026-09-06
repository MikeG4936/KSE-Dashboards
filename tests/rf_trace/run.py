#!/usr/bin/env python3
"""Compare RF transaction traces across a behavior-preserving refactor."""
import argparse
import difflib
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PIN = "aaacfe68407c09d49a26c5aa326c00119b378bb0"


def lua_string(path):
    return '"' + str(path).replace('\\', '\\\\').replace('"', '\\"') + '"'


def instrument(source):
    marker = "  service=serviceBatteryProfileFeature,"
    if source.count(marker) != 1:
        raise ValueError("Cannot locate RF service exports")
    source = source.replace(marker, "  begin=profileBeginOperation,\n" + marker)
    pos = source.rindex("\nreturn {")
    return (source[:pos] + source[pos:].replace("return {",
            "return { audit={OPT=OPT, FC=FC, profiles=batteryProfiles},", 1))


def capture(runner, source_dir, work, upstream):
    work.mkdir()
    for name in ("KSE4", "KSE5"):
        (work / (name + ".lua")).write_text(instrument((source_dir / name / "main.lua").read_text()))
    fixture = work / "trace.lua"
    fixture.write_text("local dashboardDir=" + lua_string(work) + "\nlocal upstreamDir="
                       + lua_string(upstream) + "\n" + (HERE / "trace.lua").read_text())
    result = subprocess.run([str(runner), str(fixture)], check=True, text=True,
                            capture_output=True, timeout=60)
    rows = [line for line in result.stdout.splitlines() if line.startswith("TRACE|")]
    if sum("|count|" in line for line in rows) != 14:
        raise ValueError("Expected all 14 scenarios to report traces")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    parser.add_argument("--rf-source", required=True, type=Path,
                        help="Rotorflight Lua Git checkout containing the pinned commit")
    parser.add_argument("--baseline-dir", required=True, type=Path,
                        help="Baseline tree containing KSE4/main.lua and KSE5/main.lua")
    parser.add_argument("--candidate-dir", type=Path, default=ROOT,
                        help="Candidate tree for historical structural comparisons")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="kse-rf-trace-") as tmp:
        work = Path(tmp)
        upstream = work / "upstream"
        upstream.mkdir()
        for name in ("mspQueue", "mspHelper", "mspStatus", "mspFlightStats"):
            content = subprocess.check_output(["git", "-C", str(args.rf_source), "show",
                f"{PIN}:src/SCRIPTS/RF2/MSP/{name}.lua"])
            (upstream / (name + ".lua")).write_bytes(content)
        before = capture(args.runner.resolve(), args.baseline_dir, work / "before", upstream)
        after = capture(args.runner.resolve(), args.candidate_dir, work / "after", upstream)
        if before != after:
            raise SystemExit("RF traces changed:\n" + "\n".join(difflib.unified_diff(
                before, after, fromfile="baseline", tofile="current", lineterm="")))
        print("PASS 14 unchanged RF transaction scenarios using pinned Rotorflight queue/APIs")
        print("Characterization includes known armed sends; this is NOT a flight-safety test.")


if __name__ == "__main__":
    main()
