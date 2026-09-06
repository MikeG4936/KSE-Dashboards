#!/usr/bin/env python3
"""Exercise production dashboard counter/storage wiring in the EdgeTX host."""
import argparse
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CASES = ("qualified", "retry", "recreate", "unreadable", "fc", "fc_pending",
         "fc_pending_failure", "simulation", "model_change")


def instrument(source, scenario):
    marker = source.rfind("\nreturn {")
    if marker < 0 or "useLvgl" not in source[marker:]:
        raise ValueError("Final widget descriptor not found")
    exports = """
__integration={create=create,update=update,refresh=refresh,background=background,
  clear=clearFrameCache,count=getFlightCount,state=flightStore,A=A,OPT=OPT}
-- Isolate local-counter wiring from renderer and RF Tool hosting.
buildUi=function() end
updateUiState=function() end
batteryProfiles.service=function() end
batteryProfiles.flightSourceChanged=function() end
batteryProfiles.reset=function() end
"""
    return (ROOT.joinpath("tests/behavior/mock.lua").read_text() + "\n"
            + HERE.joinpath("mock.lua").read_text() + "\n" + source[:marker]
            + exports + '\n__scenario="' + scenario + '"\n'
            + HERE.joinpath("integration.lua").read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    args = parser.parse_args()
    traces = {}
    for variant in ("KSE4", "KSE5"):
        traces[variant] = []
        for scenario in CASES:
            with tempfile.TemporaryDirectory(prefix="kse-storage-integration-") as tmp:
                fixture = Path(tmp) / f"{variant}-{scenario}.lua"
                fixture.write_text(instrument(ROOT.joinpath(variant,"main.lua").read_text(), scenario))
                result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                        capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise SystemExit(f"{variant}/{scenario}:\n{result.stdout}{result.stderr}")
            observations = [line for line in result.stdout.splitlines() if line.startswith("PASS|")]
            if "PASS|complete" not in observations:
                raise SystemExit(f"Missing completion: {variant}/{scenario}")
            traces[variant].extend(f"{scenario}:{line}" for line in observations)
        print(f"PASS {variant} storage integration: {len(traces[variant])-len(CASES)} assertions")
    if traces["KSE4"] != traces["KSE5"]:
        raise SystemExit("Production storage integration parity failed")
    print("PASS production storage integration parity")


if __name__ == "__main__":
    main()
