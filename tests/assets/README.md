# Image resource bounds

Run `python3 tests/assets/run.py --runner ../kse-edgetx-build/edgetx-run` from the repository root using the [pinned EdgeTX host](../../tools/edgetx/README.md).

The driver executes the production image-candidate validator in both dashboards, including all four supplied assets, PNG/BMP dimension limits, byte-size limits, top-down BMPs, truncated reads, unavailable APIs/media and oversized DIB declarations that would overflow 32-bit addition. All reads are asserted to stay within 54 bytes; files over 100 KiB are rejected without reading their contents.

These checks validate header dimensions and resource bounds before LVGL loading. They do not replace a full image decoder, verify PNG checksums/pixel payloads, or measure native LVGL allocations. Actual image rendering remains a transmitter check. The size API is EdgeTX's global [`fstat`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_filesystem.cpp#L126-L153), with normal ROM-backed lookup.
