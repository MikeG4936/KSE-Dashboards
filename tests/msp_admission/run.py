#!/usr/bin/env python3
"""Exercise KSE admission policy using the pinned unmodified Rotorflight queue."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PIN = "aaacfe68407c09d49a26c5aa326c00119b378bb0"


def instrument(source):
    marker = "  service=serviceBatteryProfileFeature,"
    if source.count(marker) != 1:
        raise ValueError("Cannot locate profile-controller export boundary")
    exports = """
  admission=MspAdmission,
  begin=profileBeginOperation,
  status=profileBeginArmingStatus,
  stats=profileBeginFlightStats,
  snapshot=profileBeginSnapshot,
  unsafe=profileSwitchUnsafe,
  timeout=profileCheckOperationTimeout,
"""
    source = source.replace(marker, exports + marker)
    # Do not require an LVGL object tree to exercise allowUi=true admission.
    source = source.replace("\nreturn {\n" + exports,
        "\nprofileSetEntryPrompt=function() end\nprofileShowArmingBanner=function() end\n"
        "showBatteryProfileMenu=function() return false end\nreturn {\n" + exports)
    pos = source.rindex("\nreturn {")
    return source[:pos] + source[pos:].replace("return {", "return { audit={OPT=OPT, FC=FC, profiles=batteryProfiles},", 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    parser.add_argument("--rf-source", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="kse-msp-admission-") as temp:
        work = Path(temp)
        upstream = work / "upstream"
        upstream.mkdir()
        for name in ("mspQueue", "mspHelper", "mspStatus", "mspFlightStats"):
            data = subprocess.check_output(["git", "-C", str(args.rf_source), "show",
                f"{PIN}:src/SCRIPTS/RF2/MSP/{name}.lua"])
            (upstream / f"{name}.lua").write_bytes(data)
        traces = {}
        for variant in ("KSE4", "KSE5"):
            dashboard = work / f"{variant}.lua"
            dashboard.write_text(instrument(ROOT.joinpath(variant, "main.lua").read_text()))
            fixture = work / f"{variant}-test.lua"
            fixture.write_text("dashboardPath=" + json.dumps(str(dashboard))
                + "\nupstreamPath=" + json.dumps(str(upstream)) + "\n"
                + HERE.joinpath("contracts.lua").read_text())
            result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                    capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise SystemExit(f"{variant}:\n{result.stdout}{result.stderr}")
            traces[variant] = [line for line in result.stdout.splitlines()
                               if line.startswith(("PASS|", "LIMIT|"))]
            if "PASS|complete" not in traces[variant]:
                raise SystemExit(f"Missing completion for {variant}: {result.stdout}")
            print(f"PASS {variant}: {sum(x.startswith('PASS|') for x in traces[variant])-1} admission assertions")
            for line in result.stdout.splitlines():
                if line.startswith("RESOURCE|"):
                    print(variant + " " + line)
        if traces["KSE4"] != traces["KSE5"]:
            raise SystemExit("KSE4/KSE5 admission trace mismatch")
        print("PASS admission functional parity; active upstream carryover explicitly retained")


if __name__ == "__main__":
    main()
