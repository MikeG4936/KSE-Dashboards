# Battery profile picker contracts

Build the [pinned EdgeTX fixture host](../../tools/edgetx/README.md), then run from the repository root:

```sh
python3 tests/picker/run.py --runner ../kse-edgetx-build/edgetx-run
```

Use `--baseline-ref <git-ref>` to compare the complete 480×320 dialog child geometry, text, fonts, colors, corners and alignment with an earlier checkout. Both versions must expose the current `batteryProfiles` and `G` helper boundaries; no production file is modified. The runner generates temporary test-only exports for the picker and geometry/options/cache helpers, then executes both variants with EdgeTX's own Lua core.

Each variant runs 38 cases. Coverage includes 480×272, 480×320 and 800×480 dialog fallback when `lvgl.menu` is unavailable; all six configured profiles and sparse two-profile mapping; active-profile disablement; deferred selection; repeated open, close, dismiss and capacity refresh; native selection/close; current ARM and RF host armed refusal; missing APIs; and constructor/build failures. A mock queue raises if a picker callback tries to submit an RF request directly.

Child bounds use the usable dialog **body**, not the whole dialog. In the pinned EdgeTX v2.12.1 implementation, the [dialog constructor](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_lvgl_widget.cpp#L2630-L2639) subtracts `UI_ELEMENT_HEIGHT`. The [theme scaling](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/gui/colorlcd/libui/etx_lv_theme.h#L58-L69) and [height definition](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/gui/colorlcd/libui/etx_lv_theme.h#L282) yield 32 pixels at both 480-wide sizes and 44 pixels at 800×480. [Lua's `setFlex`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_lvgl_widget.cpp#L1500-L1509) resets body padding to zero for these dialogs, which specify neither flex nor custom padding.

The original whole-dialog scaler puts the last row four pixels past the compact body and twelve pixels past the 800-wide body. The body-aware scale corrects those bounds. The 480×320 geometry stays unchanged; 800×480 geometry changes intentionally to reserve the larger firmware header.

These mocks check submitted geometry and Lua callbacks. They do not emulate LVGL rendering, glyph clipping, focus/scroll behavior, physical touch handling, MSP transport, or RF lifecycle scheduling. The armed refusal cases preserve the currently implemented checks; they do not certify the pending positive/fresh safety evidence policy or every RF write stage. Real-radio picker operation remains a separate validation checkpoint.
