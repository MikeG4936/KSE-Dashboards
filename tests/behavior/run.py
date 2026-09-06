#!/usr/bin/env python3
"""Run deterministic dashboard contracts using the supported EdgeTX Lua runner."""
import argparse
import difflib
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SENSORS = """activeSensorName getSensorNumber resolveNamed getCellCount getPackVolt
getCellVoltage getBatPct getCapa getCurr getTemp getBec getRxBatt getBattProfile
getHeadspeed getTailRpm getGovernorMode getGovState getTxVolt txPctFromVolts
signalPercent getRqly percentFromCellVoltage selectFlightBatteryPercent
calculateAdjustedPercent""".split()
FUNCTIONS = """clearFrameCache applyOptions tick resetSessionEvidence
resetSessionStats updateBatteryAlertState resetBatteryAlertState
updateBatteryHapticTick updateEscBecAlerts updateRxPackAlert tickFlightCount
timerElapsedSeconds getFlightCount create update refresh get updateMotorAlertGate""".split()


def instrument(source: str, variant: str) -> str:
    # Replace only the final widget descriptor. No production source is edited.
    marker = source.rfind("\nreturn {")
    if marker < 0 or 'useLvgl' not in source[marker:]:
        raise ValueError("Expected final widget descriptor not found")
    namespace = "sensors." if "local sensors = {}" in source else ""
    exports = [f"{name}={namespace}{name}" for name in SENSORS]
    exports += [f"{name}={name}" for name in FUNCTIONS]
    exports += ["D=D", "A=A", "OPT=OPT", "S=S", "FC=FC", "voice=BATTERY_VOICE",
                "options=options", "config=function() return minFlightDur, SRC.motorSwitch end",
                "theme=function() return C_BG, C_ACCENT, OPT.bgTransparent end"]
    return (HERE.joinpath("mock.lua").read_text() + "\n" + source[:marker]
            + "\n__test={" + ",".join(exports) + "}\n"
            + 'buildUi=function(w) if w then w.uiBuilt=true; w.ui=w.ui or {} end end\n'
            + 'updateUiState=function() end\n__variant="' + variant + '"\n'
            + HERE.joinpath("contracts.lua").read_text())


def run(runner: Path, path: Path, variant: str) -> list[str]:
    with tempfile.TemporaryDirectory(prefix="kse-behavior-") as tmp:
        generated = Path(tmp) / f"{variant}-contracts.lua"
        generated.write_text(instrument(path.read_text(), variant))
        result = subprocess.run([str(runner), str(generated)], text=True,
                                capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f"{path}:\n{result.stdout}{result.stderr}")
    traces = [line for line in result.stdout.splitlines()
              if line.startswith(("TRACE|", "THEME|"))]
    if not traces or "TRACE|complete|true" not in traces:
        raise RuntimeError(f"Missing completion marker for {path}: {result.stdout}")
    return traces


def compare(left: list[str], right: list[str], label: str) -> None:
    if left != right:
        diff = "\n".join(difflib.unified_diff(left, right, fromfile="expected",
                                             tofile="actual", lineterm=""))
        raise RuntimeError(f"{label} changed:\n{diff}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path,
                        help="EdgeTX runner executable accepting a Lua filename")
    parser.add_argument("--baseline-dir", type=Path,
                        help="Optional directory containing KSE4/main.lua and KSE5/main.lua")
    parser.add_argument("--trace-dir", type=Path, help="Optional saved trace output directory")
    args = parser.parse_args()
    traces = {}
    for variant in ("KSE4", "KSE5"):
        traces[variant] = run(args.runner.resolve(), ROOT / variant / "main.lua", variant)
        if args.baseline_dir:
            before = run(args.runner.resolve(), args.baseline_dir / variant / "main.lua", variant)
            compare(before, traces[variant], f"{variant} baseline")
        if args.trace_dir:
            args.trace_dir.mkdir(parents=True, exist_ok=True)
            (args.trace_dir / f"{variant}.txt").write_text("\n".join(traces[variant]) + "\n")
        print(f"PASS {variant}: {len(traces[variant])} contract observations"
              + (", baseline unchanged" if args.baseline_dir else ""))
    compare([x for x in traces["KSE4"] if x.startswith("TRACE|")],
            [x for x in traces["KSE5"] if x.startswith("TRACE|")], "KSE4/KSE5 parity")
    print("PASS cross-variant functional parity (intentional palettes excluded)")


if __name__ == "__main__":
    main()
