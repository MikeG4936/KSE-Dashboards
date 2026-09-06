# Count-file storage regressions

The shared implementation lives in [`src/shared/count_storage.lua`](../../src/shared/count_storage.lua). [`tools/assemble.py`](../../tools/assemble.py) embeds identical marked sections into both standalone dashboards; `python3 tools/assemble.py --check` verifies generated consistency. These tests use the authored source directly and also exercise the production callback wiring. No duplicate storage implementation is kept in the test folder.

Run with the pinned EdgeTX host documented in [tools/edgetx](../../tools/edgetx/README.md):

```sh
python3 tests/storage/run.py --runner ../kse-edgetx-build/edgetx-run
python3 tests/storage/integration.py --runner ../kse-edgetx-build/edgetx-run
```

`--implementation path/to/storage.lua` accepts an equivalent module returning the `Storage` table. The driver concatenates a mock, the exact helper source and contracts into a temporary script. The mock has no host filesystem access. It models EdgeTX `io.open/read/write/close`, global `fstat`, and global `rename`/`del` returning numeric FatFS status.

Contracts cover successful replacement and retained backup, first-file creation, missing/removed media, reported and silent short writes, readback errors, silently lost close data, strict FRESULT return handling, backup deletion/rename failures, failed promotion/retry, backup-only recovery, both-artifact preference, temporary-only quarantine, empty/malformed/duplicate histories, exact byte/entry boundaries and over-limit rejection, read errors, foreign content changes, bounded retries, idempotent confirmation after a successful promotion with a failed readback, exact 32-bit maximum integer counts, overflow/fraction rejection, and quarantine of comment-shaped model names while preserving the API-version comment. These are mock filesystem contracts, not FatFS crash-consistency or SD-card tests.

The source authority is EdgeTX v2.12.1, commit `1511b3f29152f18c704f1f89b3608e0f71317de9`:

- [`read_chars`/`io.read`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/liolib.c#L422-L431) turns a FatFS read error into an empty string, just like EOF. The helper compares every read to the size reported by `fstat`, checks for extra bytes, and checks size again after reading. It never treats a short chunk as proof of successful EOF.
- [`io.close`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/liolib.c#L227-L233) discards the underlying close result. Successful `pcall` cannot establish a durable flush. Temporary and promoted files are read back, but cached reads still cannot prove power-loss durability.
- [`g_write`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/liolib.c#L531-L551) checks both FatFS status and byte count. Failure returns a nil/error result; success returns the file handle.
- [`fstat`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_filesystem.cpp#L126-L153) supplies file size but returns nil for any filesystem failure, not only a missing file. [`del`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_filesystem.cpp#L173-L183) and [`rename`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_filesystem.cpp#L242-L251) are normal global lookups returning numeric FRESULT. The helper accepts only numeric zero as successful mutation.

## Production integration coverage

EdgeTX enables `LUA_FLOORN2I`: `math.tointeger` alone can accept a fractional value, and mixed integer/float equality can hide that fraction. Count validation combines the conversion/range check with an explicit `value > math.floor(value)` rejection. The fixtures exercise this behavior in the pinned core rather than assuming desktop Lua numeric semantics.

`integration.py` runs fresh copies of both complete dashboard scripts for each scenario. Test exports expose the real `create`, `update`, `background` and counter/state functions. The renderer and RF controller entry points are replaced with no-ops to isolate count-file behavior; the test does not model RF Tool filesystem use. Radio API mocks are reused from `tests/behavior`, then the storage failure-injection mock supplies the filesystem calls.

The integration fixtures check that a qualified timer threshold increments once and marks the full cache dirty, then a subsequent callback persists it. They also check exhausted retries and manual retry without recounting, unreadable histories returning an unavailable count and visible error without writes, no count-file I/O in fresh FC mode, completion of earlier dirty local counts after switching to FC, simulation deferral, and retention of both models' pending counts across model changes. Cross-variant traces must agree.

The production implementation preserves the existing CSV header, model-key normalization and threshold trigger. It loads the history only for KSE Counter. A missing usable cache yields an unavailable count rather than an invented zero. A valid backup may supply a displayed count while an invalid main keeps the history read-only.

`service()` performs at most three attempts with a 500-tick (five-second) interval. Failure leaves the incremented in-memory count dirty and `FILE ERROR` visible. After correcting the media issue, switch **Flight Counter** away from and back to **KSE Counter**, or recreate the widget, to restart that bounded retry schedule. These actions preserve a dirty count within the loaded dashboard runtime and do not recount the qualifying flight. Restarting the transmitter or unloading the script discards unsaved RAM; this is not a durable retry journal.

A fresh FC-counter session does not load or write the count file. Switching to FC after a local event became dirty still completes that earlier save; a failed pending local save remains visible as `KSE FILE ERROR` alongside the FC count/status. An exhausted retry budget still requires the manual retry action. The integration fixture verifies the retained error state; renderer output is outside its mocked scope.

Simulation, currently not exposed as a widget option, defers filesystem work while retaining any earlier real dirty count. The integration fixture sets `OPT.simTelemetry` directly, confirms no retry attempts or count-file I/O occur during simulated callbacks, and verifies that real callbacks resume persistence without recounting. Model changes retain the shared file cache. A recovered backup is restored to main by the next successful save; loading it alone does not immediately write.

## Conservative recovery boundaries

- A complete valid main wins. If main is missing, a complete valid backup wins over any temporary candidate. The next save reconstructs main while retaining backup.
- Serialized model names beginning with `#` are rejected because they collide with CSV comments. Existing comment-shaped numeric model rows produce `AMBIGUOUS MODEL NAME` and make the history read-only; the `# api_ver=1` header and ordinary comments remain supported.
- An existing malformed, unreadable, oversized or over-entry-limit main stays non-writable. A valid backup may be displayed but cannot silently replace that main. No partial parser result is published.
- A temporary-only valid CSV supplies read-only salvage with `TEMP UNCONFIRMED`. A power-interrupted write can end at a valid record boundary; plain CSV carries no evidence that this is the complete history. Automatic promotion would require an additional completion journal/marker or explicit user recovery. The implementation leaves that recovery decision explicit.
- When all three names appear missing and the parent directory can be statted, a new cache may be created. Because `fstat` merges absence and I/O errors, absence is not provable through this API alone. Final rename never overwrites an existing main/backup: an undiscovered file causes promotion failure. The implementation does not promise to preserve an unreadable orphan temporary file in that ambiguous first-creation case.
- Readback and optimistic base-content checking reduce accidental overwrites but are not atomic compare-and-swap, SD durability, or concurrent-instance ownership. A same-size external modification during a read is not detectable in general. Production still needs the planned single-owner/lifecycle contract.

Temporary-only quarantine recovery remains manual. Real-media power-cut tests and radio memory/timing validation remain outstanding. Synchronous full-file validation creates allocation/work bursts; these desktop fixtures do not establish radio callback budgets, heap headroom or durable SD flush behavior.

## Instruction characterization

```sh
python3 tests/storage/profile.py --runner ../kse-edgetx-build/edgetx-run
```

The fixture measures 200-model histories at typical and maximum (32 KiB) file sizes, covering isolated load/save and complete local-counter create/background-save callbacks with RF and renderer entry points stubbed. Each measured path must remain below 15,000 Lua instructions. Counts include Lua filesystem-mock overhead; they exclude native I/O time and the invoked RF/render work needed to establish a whole-radio callback budget.

Saving compares current file contents with the previously validated base text instead of parsing unchanged history again. Reads use bounded 8 KiB chunks to reduce call overhead. Retained heap, native I/O latency and complete callbacks with RF Tool still require radio measurements.
