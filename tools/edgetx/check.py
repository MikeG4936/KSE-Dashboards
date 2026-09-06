#!/usr/bin/env python3
"""Build and run pinned EdgeTX Lua resource checks without vendoring Lua."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

COMMIT = "1511b3f29152f18c704f1f89b3608e0f71317de9"
CORE_PATH = "radio/src/thirdparty/Lua/src"
HERE = Path(__file__).resolve().parent
CORE = "lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio lauxlib".split()
LIBS = "lbaselib lmathlib ltablib lstrlib".split()
FLAGS = ["-std=c11", "-O2", "-DNATIVE_TARGET", "-DLUA_COMPAT_5_2"]
GATES = {"active_locals": 180, "registers": 230}


def command(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def capture(args):
    return command(args, capture_output=True, text=True).stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(args):
    checkout = args.edgetx.resolve()
    core = checkout / CORE_PATH
    head = capture(["git", "-C", checkout, "rev-parse", "HEAD"])
    if head != COMMIT:
        raise ValueError(f"EdgeTX HEAD must be {COMMIT}; found {head}")
    command(["git", "-C", checkout, "diff", "--exit-code", COMMIT, "--", CORE_PATH],
            stdout=subprocess.DEVNULL)
    extra = capture(["git", "-C", checkout, "ls-files", "--others", "--", CORE_PATH])
    if extra:
        raise ValueError(f"Untracked files in EdgeTX core are not allowed: {extra}")
    inputs = [core / (name + ".c") for name in CORE + LIBS]
    inputs += sorted(core.glob("*.h"))
    inputs += [HERE / name for name in ("limits.c", "run.c", "debug.h", "check.py")]
    if any(path.is_symlink() for path in inputs):
        raise ValueError("Compiler input symlinks are not supported")
    provenance = {
        "edgetx_commit": COMMIT,
        "core_path": CORE_PATH,
        "compiler": capture([args.cc, "--version"]).splitlines()[0],
        "flags": FLAGS,
        "inputs_sha256": {
            ("harness/" if path.parent == HERE else "core/") + path.name: digest(path)
            for path in inputs
        },
    }
    output = args.build_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Observe the exact parser count without changing emitted bytecode or the
    # upstream checkout. Debug local intervals omit zero-instruction scopes.
    parser_text = (core / "lparser.c").read_text()
    anchor = "  checklimit(fs, dyd->actvar.n + 1 - fs->firstlocal,\n"
    if parser_text.count(anchor) != 1:
        raise ValueError("Pinned parser local-check anchor changed")
    instrumented = ("extern void kse_observe_local_count(const void *, int);\n" +
        parser_text.replace(anchor,
            "  kse_observe_local_count(fs->f, dyd->actvar.n + 1 - fs->firstlocal);\n" + anchor))
    parser_copy = output / "lparser-observed.c"
    parser_copy.write_text(instrumented)
    provenance["observed_parser_sha256"] = digest(parser_copy)
    manifest = output / "build.json"
    binaries = {kind: output / ("edgetx-" + kind) for kind in ("limits", "run")}
    if manifest.exists() and json.loads(manifest.read_text()) == provenance and all(p.exists() for p in binaries.values()):
        return binaries, provenance
    for kind, binary in binaries.items():
        names = CORE + (LIBS if kind == "run" else [])
        sources = [parser_copy if kind == "limits" and name == "lparser"
                   else core / (name + ".c") for name in names]
        command([args.cc, *FLAGS, "-I", core, "-I", HERE, HERE / (kind + ".c"),
                 *sources, "-lm", "-o", binary])
    manifest.write_text(json.dumps(provenance, indent=2) + "\n")
    return binaries, provenance


def check(binary, sources):
    results = []
    for source in sources:
        source = Path(source)
        result = json.loads(capture([binary, source]))
        result.update(source=str(source), source_sha256=digest(source),
                      source_bytes=source.stat().st_size,
                      source_lines=len(source.read_bytes().splitlines()))
        rows = result["prototypes"]
        result["prototype_count"] = len(rows)
        result["maxima"] = {key: max(row[key] for row in rows)
                            for key in ("active_locals", "registers", "upvalues")}
        result["violations"] = [
            {"prototype": row["id"], "line": row["line"], "metric": key,
             "actual": row[key], "target": target}
            for row in rows for key, target in GATES.items() if row[key] > target
        ]
        result["policy_pass"] = not result["violations"]
        results.append(result)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edgetx", required=True, type=Path, help="clean checkout of the pinned EdgeTX commit")
    parser.add_argument("--build-dir", required=True, type=Path, help="directory for host executables and build provenance")
    parser.add_argument("--cc", default="cc", help="C compiler executable (default: cc)")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("build")
    checker = sub.add_parser("check")
    checker.add_argument("sources", nargs="+", help="Lua source files")
    checker.add_argument("--json", type=Path, help="write all prototype metrics and provenance")
    checker.add_argument("--report-only", action="store_true", help="record a baseline even when project margins fail")
    runner = sub.add_parser("run")
    runner.add_argument("fixture", type=Path)
    runner.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        binaries, provenance = build(args)
        if args.action == "build":
            print(binaries["limits"])
            print(binaries["run"])
        elif args.action == "run":
            return subprocess.run([str(binaries["run"]), str(args.fixture), *args.arguments]).returncode
        else:
            results = check(binaries["limits"], args.sources)
            if args.json:
                args.json.write_text(json.dumps({"schema_version": 1, "build": provenance,
                    "project_targets": GATES, "files": results}, indent=2) + "\n")
            for item in results:
                m = item["maxima"]
                print(f"{item['source']}: {'PASS' if item['policy_pass'] else 'FAIL'} "
                      f"locals={m['active_locals']} registers={m['registers']} upvalues={m['upvalues']} "
                      f"prototypes={item['prototype_count']} bytecode={item['stripped_bytecode_bytes']}")
                for violation in item["violations"]:
                    print(f"  prototype {violation['prototype']} line {violation['line']}: "
                          f"{violation['metric']} {violation['actual']} > {violation['target']}")
            return 0 if args.report_only or all(item["policy_pass"] for item in results) else 1
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
