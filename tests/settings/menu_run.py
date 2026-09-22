#!/usr/bin/env python3
"""Exercise settings-menu drafts and deferred native control callbacks."""
import argparse
from pathlib import Path
import subprocess
import tempfile

from run import themes

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True, type=Path)
    args = parser.parse_args()
    options = (ROOT / "src/shared/options.lua").read_text()
    helpers = options[options.index("local function parseVolt("):
                      options.index("-- @include variant:option_theme.lua")]
    source = (HERE.joinpath("mock.lua").read_text() + "\n" + themes()
              + "SettingsStore=(function()\n"
              + (ROOT / "src/shared/settings_store.lua").read_text()
              + "\nend)()\n"
              + HERE.joinpath("menu.lua").read_text().split("-- MODULE INSERTION POINT", 1)[0]
              + "\nMenu=(function()\n" + helpers
              + (ROOT / "src/shared/settings_menu.lua").read_text()
              + "\nend)()\n"
              + HERE.joinpath("menu.lua").read_text().split("-- MODULE INSERTION POINT", 1)[1])
    with tempfile.TemporaryDirectory(prefix="kse-settings-menu-") as tmp:
        fixture = Path(tmp) / "menu.lua"
        fixture.write_text(source)
        result = subprocess.run([str(args.runner.resolve()), str(fixture)],
                                capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    lines = [line for line in result.stdout.splitlines() if line.startswith("PASS|")]
    if "PASS|complete" not in lines:
        raise SystemExit("Menu fixture completion missing: " + result.stdout)
    print(f"PASS settings menu: {len(lines) - 1} assertions")
    for line in result.stdout.splitlines():
        if line.startswith("PROFILE|"):
            print(line)


if __name__ == "__main__":
    main()
