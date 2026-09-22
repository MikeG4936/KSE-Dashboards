#!/usr/bin/env python3
"""Exercise settings persistence in the pinned EdgeTX Lua fixture host."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def themes():
    """Exercise each authored variant's canonical theme labels."""
    result = []
    for variant in ("KSE4", "KSE5"):
        source = (ROOT / "src/variants" / variant / "main.lua").read_text()
        labels = re.search(r"G\.settingsThemes\s*=\s*({.*?})", source, re.S)
        if labels is None:
            raise ValueError(f"Missing canonical theme labels for {variant}")
        result.append(f"themes{variant[-1]}=" + labels.group(1) + "\n")
    return "".join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    parser.add_argument("--implementation", type=Path,
                        default=ROOT / "src/shared/settings_store.lua")
    args = parser.parse_args()
    source = (HERE.joinpath("mock.lua").read_text() + "\n"
              + "Store=(function()\n" + args.implementation.read_text()
              + "\nend)()\n" + HERE.joinpath("storage.lua").read_text())
    with tempfile.TemporaryDirectory(prefix="kse-settings-") as tmp:
        fixture = Path(tmp) / "settings.lua"
        fixture.write_text(source)
        result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    lines = [line for line in result.stdout.splitlines() if line.startswith("PASS|")]
    if "PASS|complete" not in lines:
        raise SystemExit("Settings fixture completion missing: " + result.stdout)
    print(f"PASS settings: {len(lines) - 1} assertions ({args.implementation})")
    for line in result.stdout.splitlines():
        if line.startswith("PROFILE|"):
            print(line)


if __name__ == "__main__":
    main()
