#!/usr/bin/env python3
"""Exercise full dashboard callback ownership with radio/rendering mocks."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PAIRS = (("KSE4", "KSE4", True), ("KSE5", "KSE5", True),
         ("KSE4", "KSE4", False), ("KSE5", "KSE5", False),
         ("KSE4", "KSE5", False), ("KSE5", "KSE4", False))


def instrument(source):
    anchor = "  service=serviceBatteryProfileFeature,"
    if source.count(anchor) != 1:
        raise ValueError("Profile-controller export boundary not found")
    source = source.replace(anchor, "  admission=MspAdmission,\n  begin=profileBeginOperation,\n"
                            "  picker=showBatteryProfileMenu,\n" + anchor)
    marker = source.rfind("\nreturn {")
    if marker < 0 or "useLvgl" not in source[marker:]:
        raise ValueError("Final widget descriptor not found")
    hooks = """
local __ownershipMetrics={rf=0,build=0,draw=0}
-- The real top-level callbacks and their initialization paths remain intact.
buildUi=function(widget)
  __ownershipMetrics.build=__ownershipMetrics.build+1
  if widget then widget.uiBuilt=true; widget.ui=widget.ui or {} end
end
updateUiState=function() __ownershipMetrics.draw=__ownershipMetrics.draw+1 end
batteryProfiles.service=function() __ownershipMetrics.rf=__ownershipMetrics.rf+1 end
"""
    exports = ("return { audit={OPT=OPT,A=A,D=D,S=S,G=G,store=flightStore,"
               "count=getFlightCount,profiles=batteryProfiles,metrics=__ownershipMetrics},")
    return source[:marker] + hooks + source[marker:].replace("return {", exports, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="kse-ownership-") as temp:
        work = Path(temp)
        for variant in ("KSE4", "KSE5"):
            work.joinpath(variant + ".lua").write_text(instrument(ROOT.joinpath(variant, "main.lua").read_text()))
        failures = []
        for owner, contender, same_api in PAIRS:
            label = f"{owner}/{contender}/" + ("same-module" if same_api else "separate-modules")
            fixture = work / "contracts.lua"
            fixture.write_text("dashboardDir=" + json.dumps(str(work))
                + "\nownerVariant=" + json.dumps(owner)
                + "\ncontenderVariant=" + json.dumps(contender)
                + "\nsameModule=" + ("true" if same_api else "false") + "\n"
                + ROOT.joinpath("tests/behavior/mock.lua").read_text() + "\n"
                + ROOT.joinpath("tests/storage/mock.lua").read_text() + "\n"
                + HERE.joinpath("contracts.lua").read_text())
            result = subprocess.run([str(args.runner.resolve()), str(fixture)], text=True,
                                    capture_output=True, timeout=60)
            if result.returncode:
                failures.append(f"{label}:\n{result.stdout}{result.stderr}")
                continue
            observations = [line for line in result.stdout.splitlines() if line.startswith("PASS|")]
            if "PASS|complete" not in observations:
                raise SystemExit(f"No completion marker for {label}")
            print(f"PASS {label}: {len(observations)-1} ownership assertions")
        if failures:
            raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
