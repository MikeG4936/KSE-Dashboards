#!/usr/bin/env python3
"""Exercise picker capability fallbacks with the pinned EdgeTX Lua host."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def instrument(source: str) -> str:
    anchor = "  service=serviceBatteryProfileFeature,"
    if source.count(anchor) != 1:
        raise ValueError("Expected battery profile export anchor not found")
    # A style-only historical comparison normalizes the admission result;
    # current behavioral cases still run the real ARM checks without this stub.
    boundary = source.rfind("\nreturn {", 0, source.index(anchor))
    if boundary < 0:
        raise ValueError("Expected profile-controller return boundary not found")
    source = (source[:boundary]
        + '\nif arg[1]=="style" then profileSwitchUnsafe=function() return false end end\n'
        + source[boundary:])
    source = source.replace(anchor, "  picker=showBatteryProfileMenu,\n" + anchor)
    if "function Admission.disarmed(" in source:
        source = source.replace(anchor, "  disarmed=MspAdmission.disarmed,\n" + anchor)
    end = source.rfind("\nreturn {")
    if end < 0 or "useLvgl" not in source[end:]:
        raise ValueError("Expected final widget descriptor not found")
    return (HERE.joinpath("mock.lua").read_text() + "\n" + source[:end]
            + "\n__picker={owner=WidgetOwner,show=batteryProfiles.picker,disarmed=batteryProfiles.disarmed,G=G,apply=applyOptions,clear=clearFrameCache}\n"
            + HERE.joinpath("contracts.lua").read_text())


def execute(runner: Path, source: str, variant: str, mode: str) -> list[str]:
    with tempfile.TemporaryDirectory(prefix="kse-picker-") as temporary:
        generated = Path(temporary) / f"{variant}-picker.lua"
        generated.write_text(instrument(source))
        completed = subprocess.run([str(runner), str(generated), mode, variant],
                                   capture_output=True, text=True, timeout=30)
    if completed.returncode:
        raise RuntimeError(f"{variant} {mode}: {completed.stdout}{completed.stderr}")
    lines = completed.stdout.splitlines()
    if "PICKER|complete" not in lines:
        raise RuntimeError(f"Missing completion marker: {completed.stdout}")
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, required=True)
    parser.add_argument("--baseline-ref", help="Optional Git ref for unchanged 480x320 style comparison")
    args = parser.parse_args()
    for variant in ("KSE4", "KSE5"):
        source = (ROOT / variant / "main.lua").read_text()
        lines = execute(args.runner.resolve(), source, variant, "all")
        print(f"PASS {variant}: {sum(line.startswith('PICKER|case|') for line in lines)} picker cases")
        if args.baseline_ref:
            baseline = subprocess.run(["git", "show", f"{args.baseline_ref}:{variant}/main.lua"],
                                      cwd=ROOT, check=True, text=True, capture_output=True).stdout
            before = execute(args.runner.resolve(), baseline, variant, "style")
            after = execute(args.runner.resolve(), source, variant, "style")
            if before != after:
                raise AssertionError(f"{variant} 480x320 style changed\nBEFORE {before}\nAFTER {after}")
            print(f"PASS {variant}: 480x320 style matches {args.baseline_ref}")


if __name__ == "__main__":
    main()
