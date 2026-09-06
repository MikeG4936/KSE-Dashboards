#!/usr/bin/env python3
"""Validate the authored storage helper in the pinned EdgeTX Lua host."""
import argparse
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    parser.add_argument("--implementation", type=Path,
                        default=HERE.parents[1] / "src/shared/count_storage.lua")
    args = parser.parse_args()
    source = (HERE.joinpath("mock.lua").read_text() + "\n"
              + "Storage=(function()\n" + args.implementation.read_text()
              + "\nend)()\n" + HERE.joinpath("contracts.lua").read_text())
    with tempfile.TemporaryDirectory(prefix="kse-storage-") as tmp:
        fixture = Path(tmp) / "storage.lua"
        fixture.write_text(source)
        result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    lines = [line for line in result.stdout.splitlines() if line.startswith("PASS|")]
    if "PASS|complete" not in lines:
        raise SystemExit("Storage fixture completion missing: " + result.stdout)
    print(f"PASS storage: {len(lines) - 1} assertions ({args.implementation})")


if __name__ == "__main__":
    main()
