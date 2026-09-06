# EdgeTX compiler and fixture host

Requirements: Python 3.9+, Git and a C11 compiler (`cc`, or `--cc /path/to/compiler`). No Python packages are needed. Run the commands from the repository root. Keep the build directory outside dashboard deployment folders.

The only supported compiler input is EdgeTX v2.12.1 commit `1511b3f29152f18c704f1f89b3608e0f71317de9`. An existing clean checkout can be supplied with `--edgetx`. To fetch a minimal checkout explicitly:

```sh
git clone --filter=blob:none --no-checkout https://github.com/EdgeTX/edgetx.git ../kse-edgetx
git -C ../kse-edgetx sparse-checkout set radio/src/thirdparty/Lua/src
git -C ../kse-edgetx checkout --detach 1511b3f29152f18c704f1f89b3608e0f71317de9
```

Build and check both production scripts:

```sh
python3 tools/edgetx/check.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build check KSE4/main.lua KSE5/main.lua --json ../kse-edgetx-build/resources.json
python3 tools/edgetx/self_test.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build
```

`build` can replace `check ...` to build without checking a source. Each invocation verifies the checkout commit and rejects changed or untracked core files. The build manifest records compiler identity, options, EdgeTX commit and SHA-256 hashes of core/header/harness inputs; unchanged builds are reused. Source bytes, lines and SHA-256 accompany every measured file. JSON contains every prototype, its parent and source line, maximum simultaneous active locals, register slots, upvalues, VM instruction count and instruction bytes. It also records complete stripped serialized bytecode size. Per-prototype instruction bytes exclude constants and other serialized metadata.

Project gates apply to **every prototype**, including nested functions: at most **180 active locals and 230 registers**. Exit 1 means the source compiled but exceeded a project gate; exit 2 means input/build/compile failure. `--report-only` permits baseline collection with exceeded project targets while retaining `policy_pass: false` and violations in JSON. It does not bypass parse failures. Upstream hard limits are 200 locals, fewer than 255 registers and 255 upvalues; the parser enforces these. See the [review's resource contract](../../docs/KSE4-KSE5-optimization-review.md#7-share-functional-source-and-create-compiler-headroom) for scope and source evidence.

The checker inspects prototypes before stripping. For locals, it adds one observation call at the pinned parser's local-limit check in a generated build-directory copy of `lparser.c`; it does not change the upstream checkout or emitted bytecode. This records the same simultaneous count that EdgeTX checks, including parameters and zero-instruction scopes whose debug `startpc` and `endpc` coincide. The exact generated parser hash is in the build manifest. Registers and upvalues come directly from prototype metadata. The self-test checks nested traversal, disjoint empty scopes, project-local and register rejection, parser failure, ROM-library lookup, arguments and fixture error propagation.

Run a Lua fixture with the same core:

```sh
python3 tools/edgetx/check.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build run path/to/fixture.lua argument1
```

The host provides EdgeTX's ROM-backed base, math, table and string libraries, `_G` lookup and `arg` (`arg[0]` is the fixture). Its `print` writes fixture traces to host stdout instead of the firmware debug sink. Fixtures supply radio APIs and storage mocks. There is no `io`, `os`, package loader, radio scheduler, LVGL, RF transport, firmware allocator or widget instruction hook. The core retains EdgeTX's 32-bit Lua numbers/integers; `NATIVE_TARGET` enables host file loading. A no-op `debug.h` supplies the firmware trace macro. The runner uses the original parser, without the checker's observation hook. The host is intentionally separate from the production dashboard installation.

These results establish parser compatibility and the behavior exercised by fixtures. They do not establish whole-radio RAM, callback timing, instruction-budget compliance, physical rendering or over-the-air RF performance. Do not install these host binaries or their bytecode outputs on a transmitter.

The test-only `measure(function, ...)` helper returns the executed Lua VM instruction count followed by the function's return values. It counts with a one-instruction hook, restores the prior hook on success/error, and rejects nested measurement. This helps identify expensive mocked paths; counts include Lua mocks and exclude native API time. A measured helper is not the complete widget callback, and its result does not establish a transmitter instruction/time margin.
