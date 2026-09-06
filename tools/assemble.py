#!/usr/bin/env python3
"""Assemble marked shared functional sections into standalone dashboards."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MODULES = {"count_storage": "Storage", "msp_admission": "MspAdmission"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail instead of updating stale sections")
    args = parser.parse_args()
    stale = []
    for variant in ("KSE4", "KSE5"):
        path = ROOT / variant / "main.lua"
        original = updated = path.read_text()
        for module, binding in MODULES.items():
            body = (ROOT / "src/shared" / (module + ".lua")).read_text()
            begin, end = "-- BEGIN SHARED " + module, "-- END SHARED " + module
            pattern = re.compile(re.escape(begin) + r"\n.*?\n" + re.escape(end), re.S)
            if len(pattern.findall(updated)) != 1:
                raise SystemExit(f"Expected exactly one {module} section in {path}")
            generated = begin + "\nlocal " + binding + " = (function()\n" + body + "end)()\n" + end
            updated = pattern.sub(lambda _: generated, updated)
        if original != updated:
            stale.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.write_text(updated)
    if stale and args.check:
        raise SystemExit("Regenerate shared sections: " + ", ".join(stale))
    print("Shared sections " + ("updated: " + ", ".join(stale) if stale else "are current"))


if __name__ == "__main__":
    main()
