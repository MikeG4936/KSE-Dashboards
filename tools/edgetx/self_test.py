#!/usr/bin/env python3
"""Exercise metadata traversal, project gates, parser failure, and ROM host."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace

import check


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edgetx", required=True, type=Path)
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    binaries, _ = check.build(args)
    with tempfile.TemporaryDirectory(prefix="kse-edgetx-self-test-") as directory:
        root = Path(directory)
        nested = root / "nested.lua"
        nested.write_text("local outer = 7\nreturn function(arg)\n"
                          "  do local a, b, c = 1, 2, 3 end\n"
                          "  do local d, e, f = 4, 5, 6 end\n"
                          "  return function() return outer + arg end\nend\n")
        result = check.check(binaries["limits"], [nested])[0]
        assert result["policy_pass"]
        assert result["prototype_count"] == 3
        assert result["prototypes"][1]["active_locals"] == 4, result
        assert result["prototypes"][2]["parent"] == 1
        assert result["prototypes"][2]["upvalues"] == 2
        assert result["stripped_bytecode_bytes"] > sum(p["instruction_bytes"] for p in result["prototypes"])

        # The violating function is nested, proving the gate is not main-only.
        locals_source = root / "locals.lua"
        locals_source.write_text("return function()\nlocal " + ",".join(f"v{i}" for i in range(181)) + "\nend\n")
        result = check.check(binaries["limits"], [locals_source])[0]
        assert result["violations"] == [{"prototype": 1, "line": 1, "metric": "active_locals", "actual": 181, "target": 180}]

        registers = root / "registers.lua"
        registers.write_text("return function()\nlocal " + ",".join(f"v{i}" for i in range(170))
                             + "\nf(" + ",".join("1" for _ in range(65)) + ")\nend\n")
        result = check.check(binaries["limits"], [registers])[0]
        assert result["maxima"]["active_locals"] == 170
        assert any(v["metric"] == "registers" for v in result["violations"])

        malformed = root / "malformed.lua"
        malformed.write_text("local = broken\n")
        completed = subprocess.run([str(binaries["limits"]), str(malformed)], capture_output=True)
        assert completed.returncode != 0 and completed.stderr

        rom = root / "rom.lua"
        rom.write_text('''assert(rawget(_G, "assert") == nil)
assert(type(assert) == "function")
assert(math.floor(3.9) == 3)
assert(("abc"):upper() == "ABC")
local values = {3, 1, 2}; table.sort(values)
assert(table.concat(values, ",") == "1,2,3")
assert(arg[1] == "fixture argument")
assert(os == nil and io == nil and package == nil)
print("TRACE|stdout", 7, false)
''')
        completed = check.command([binaries["run"], rom, "fixture argument"], capture_output=True, text=True)
        assert completed.stdout == "TRACE|stdout\t7\tfalse\n", completed.stdout
        rom.write_text('error("expected fixture failure")\n')
        completed = subprocess.run([str(binaries["run"]), str(rom)], capture_output=True)
        assert completed.returncode != 0 and b"expected fixture failure" in completed.stderr
        rom.write_text('print(string.dump(function() return 1 end))\n')
        dumped = check.command([binaries["run"], rom], capture_output=True).stdout[:-1]
        binary = root / "already-compiled.luac"
        binary.write_bytes(dumped)
        completed = subprocess.run([str(binaries["limits"]), str(binary)], capture_output=True)
        assert completed.returncode != 0 and b"binary" in completed.stderr

        # An isolated sparse checkout shares read-only objects, requiring no
        # network fetch and never modifying the caller's checkout.
        repo = root / "source"
        check.command(["git", "init", repo], capture_output=True)
        objects = check.capture(["git", "-C", args.edgetx, "rev-parse",
                                 "--path-format=absolute", "--git-path", "objects"])
        (repo / ".git/objects/info/alternates").write_text(objects + "\n")
        check.command(["git", "-C", repo, "sparse-checkout", "set", check.CORE_PATH], capture_output=True)
        check.command(["git", "-C", repo, "checkout", "--detach", check.COMMIT], capture_output=True)
        isolated = SimpleNamespace(edgetx=repo, build_dir=root / "rejected-build", cc=args.cc)
        extra = repo / check.CORE_PATH / "unexpected.h"
        extra.write_text("/* untracked input must be rejected */\n")
        try:
            check.build(isolated)
            raise AssertionError("untracked core input accepted")
        except ValueError as error:
            assert "Untracked" in str(error)
        extra.unlink()
        tracked = repo / check.CORE_PATH / "lparser.c"
        tracked.write_text(tracked.read_text() + "\n/* changed input */\n")
        try:
            check.build(isolated)
            raise AssertionError("modified core input accepted")
        except subprocess.CalledProcessError:
            pass
    print("PASS: nested metadata, scoped locals, local/register gates, syntax errors, ROM libraries, fixture failures, source provenance rejection")


if __name__ == "__main__":
    main()
