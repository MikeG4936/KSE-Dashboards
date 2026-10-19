#!/usr/bin/env python3
"""Exercise incremental history loading through production widget callbacks.

Rendering and RF servicing are stubbed, as in integration.py. This suite checks
storage/lifecycle behavior, not full callback CPU, native UI, SD, or RF timing.
Every load step is reached through one real background/refresh callback; only
the test driver loops between callbacks.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CASES = ("expired", "simulation", "counter_change", "save_simulation", "save_counter_change")


def instrument(source):
    marker = source.rfind("\nreturn {")
    if marker < 0 or "useLvgl" not in source[marker:]:
        raise ValueError("Final widget descriptor not found")
    hooks = """
local __asyncMetrics={rf=0,build=0,draw=0}
-- Keep actual ownership, initialization, option changes, telemetry, timers,
-- and storage wiring. The complete renderer/RF budget has a separate suite.
buildUi=function(widget)
  __asyncMetrics.build=__asyncMetrics.build+1
  if widget then widget.uiBuilt=true; widget.ui=widget.ui or {} end
end
updateUiState=function() __asyncMetrics.draw=__asyncMetrics.draw+1 end
batteryProfiles.service=function() __asyncMetrics.rf=__asyncMetrics.rf+1 end
batteryProfiles.flightSourceChanged=function() end
batteryProfiles.reset=function() end
"""
    exports = ("return { audit={state=function() return flightStore end,"
               "count=getFlightCount,A=A,OPT=OPT,metrics=__asyncMetrics},")
    return source[:marker] + hooks + source[marker:].replace("return {", exports, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    args = parser.parse_args()
    traces = {}
    with tempfile.TemporaryDirectory(prefix="kse-storage-async-") as temp:
        work = Path(temp)
        for variant in ("KSE4", "KSE5"):
            work.joinpath(variant + ".lua").write_text(
                instrument(ROOT.joinpath(variant, "main.lua").read_text()))
        runs = [(case, variant, variant) for case in CASES
                for variant in ("KSE4", "KSE5")]
        runs.extend(("handoff", owner, contender) for owner, contender in
                    (("KSE4", "KSE5"), ("KSE5", "KSE4")))
        runs.extend(("save_handoff", owner, contender) for owner, contender in
                    (("KSE4", "KSE5"), ("KSE5", "KSE4")))
        for scenario, owner, contender in runs:
            label = f"{scenario}/{owner}/{contender}"
            fixture = work / "contracts.lua"
            fixture.write_text("dashboardDir=" + json.dumps(str(work))
                + "\nownerVariant=" + json.dumps(owner)
                + "\ncontenderVariant=" + json.dumps(contender)
                + "\nscenario=" + json.dumps(scenario) + "\n"
                + ROOT.joinpath("tests/behavior/mock.lua").read_text() + "\n"
                + HERE.joinpath("mock.lua").read_text() + "\n"
                + HERE.joinpath("async.lua").read_text())
            result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                    capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise SystemExit(f"{label}:\n{result.stdout}{result.stderr}")
            observations = [line for line in result.stdout.splitlines()
                            if line.startswith("PASS|")]
            if "PASS|complete" not in observations:
                raise SystemExit(f"Missing completion: {label}\n{result.stdout}")
            if scenario in traces and traces[scenario] != observations:
                raise SystemExit(f"Async callback parity failed: {label}")
            traces[scenario] = observations
            print(f"PASS {label}: {len(observations)-1} async assertions")
    print("PASS async storage callback and cross-variant handoff parity")


if __name__ == "__main__":
    main()
