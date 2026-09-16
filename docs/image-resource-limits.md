# Model-image limits: source evidence and recommendation

Reviewed 2026-09-15. This note records the selected policy and its source-based rationale; it does not establish transmitter memory/timing results.

## Selected common policy

KSE's selected limits are **at most 130,560 pixels (`width × height`), at most 512 pixels on either edge, and at most 512 KiB (524,288 bytes) per file**. Retain PNG/BMP header validation and fallback behavior. Prefer ordinary 8-bit, non-interlaced PNG exports and images close to their displayed size.

This preserves the old 480×272 policy's maximum decoded pixel count while admitting more useful shapes: 300×280, 272×480, 360×360 and 512×255. It intentionally does **not** admit 512×512. The 512-pixel edge rule is a project guard against extreme aspect ratios, not an EdgeTX hard limit. The 130,560-pixel budget is likewise a conservative continuation of the existing policy, not a proven maximum for every radio.

The reported `TREX 700N.png` is 300×280, 37,276 bytes and RGBA8: 84,000 pixels, about 64% of the old maximum area. Its extra eight rows do not imply greater decoded-memory demand than an allowed 480×272 RGBA image. A rectangular 480×272 rule rejects it unnecessarily. Those file properties were supplied by the task's local inspection; the cost calculations below follow from upstream source.

## Actual EdgeTX image path

Checked EdgeTX 2.11.5 [`2273bda7b9e650c96a39a6e7f1316b6ef8415dad`](https://github.com/EdgeTX/edgetx/tree/2273bda7b9e650c96a39a6e7f1316b6ef8415dad), 2.12.1 [`1511b3f29152f18c704f1f89b3608e0f71317de9`](https://github.com/EdgeTX/edgetx/tree/1511b3f29152f18c704f1f89b3608e0f71317de9), and 2.12.4 [`def35ad324896b45d6607d4778536b1bc5360d20`](https://github.com/EdgeTX/edgetx/tree/def35ad324896b45d6607d4778536b1bc5360d20). The native decoder's conversion/open/close implementation is identical across those three inspected versions. These are identified supported-version checks, not a claim about every release or newer firmware.

- Lua `lvgl.image` constructs a `StaticImage`. It assigns the source to a native LVGL image and uses LVGL zoom to fit/fill its frame. Scaling does not resize the file before decoding. [Lua binding](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_lvgl_widget.cpp#L1982-L2026), [source assignment and zoom](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/libui/static.cpp#L216-L275).
- EdgeTX's custom STB decoder requests **four 8-bit components per source pixel**, then allocates another native LVGL buffer: **three bytes per pixel when the reported source component count is four**, otherwise two. The RGBA temporary remains alive during that conversion. Thus ordinary RGBA has a **7P-byte conversion overlap**, with **3P retained in the decoded image**, where `P = width × height`. This is not the complete peak. [2.12.4 decoder](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/libui/bitmapbuffer_fileio.cpp#L200-L289), [same 2.11.5 path](https://github.com/EdgeTX/edgetx/blob/2273bda7b9e650c96a39a6e7f1316b6ef8415dad/radio/src/gui/colorlcd/libui/bitmapbuffer_fileio.cpp#L198-L287).
- This native path is distinct from `Bitmap.open`/`BitmapBuffer` accounting. Its converted buffer comes from `lv_mem_alloc`; STB's temporary allocations use its normal allocator. A Lua Bitmap budget or Lua heap figure does not establish this path's available memory. [Separate Bitmap and native decoder implementations](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/libui/bitmapbuffer_fileio.cpp#L97-L289).

## Decode workspace and retained cache

All three inspected EdgeTX versions pin STB at [`5c205738c191bcb0abc65c4febfa9bd25ff35234`](https://github.com/nothings/stb/tree/5c205738c191bcb0abc65c4febfa9bd25ff35234). PNG decoding collects compressed IDAT data into a growing allocation and inflates it into a separate buffer; it frees the compressed buffer before reconstructing pixels. For ordinary non-interlaced RGBA8, reconstruction overlaps approximately **4P filtered bytes + 4P output bytes + row-filter workspace**, or a little over **8P**. Interlacing adds a full output allocation plus pass buffers; 16-bit PNG needs larger intermediate samples before producing 8-bit output. These are source-derived allocation models, not measured radio peaks. [IDAT/inflate lifetime](https://github.com/nothings/stb/blob/5c205738c191bcb0abc65c4febfa9bd25ff35234/stb_image.h#L5173-L5235), [pixel/filter allocation](https://github.com/nothings/stb/blob/5c205738c191bcb0abc65c4febfa9bd25ff35234/stb_image.h#L4696-L4729), [interlaced allocation](https://github.com/nothings/stb/blob/5c205738c191bcb0abc65c4febfa9bd25ff35234/stb_image.h#L4861-L4901).

The native pool is shared with other LVGL use. EdgeTX 2.11.5 configures **2 MiB on hardware**; 2.12.1/2.12.4 select **2, 4 or 8 MiB** based on SDRAM configuration. Simulator pools are larger, so a simulator success is insufficient. [2.11.5 pool](https://github.com/EdgeTX/edgetx/blob/2273bda7b9e650c96a39a6e7f1316b6ef8415dad/radio/src/gui/colorlcd/lv_conf.h#L52-L64), [2.12.4 pools](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/lv_conf.h#L52-L80).

The configured image cache has **eight entries**, not an eight-image byte budget. In the LVGL revision pinned by 2.12.1/2.12.4, cached decoder allocations remain open until eviction or invalidation. Consequently, an individual image's retained allocation is not the total image footprint. [Cache configuration](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/lv_conf.h#L167-L174), [pinned cache implementation](https://github.com/EdgeTX/lvgl/blob/5f129c540ec43a4e5aebff9f77b3688b57a78063/src/draw/lv_img_cache.c#L55-L140).

## Comparing practical tiers

These figures assume RGBA; KiB means 1,024 bytes. The last column excludes row overhead, compressed-buffer growth, allocator overhead, interlace/16-bit differences, rendering buffers, other cached images and the rest of the dashboard/radio.

| Policy/example | Pixels | Retained 3P | Conversion overlap 7P | Ordinary RGBA8 reconstruction ≈8P |
| --- | ---: | ---: | ---: | ---: |
| Actual 300×280 | 84,000 | 246.1 KiB | 574.2 KiB | 656.3 KiB |
| Recommended area budget, each edge ≤512 | 130,560 | 382.5 KiB | 892.5 KiB | 1,020 KiB |
| Optional larger tier, ≤512×512 | 262,144 | 768 KiB | 1,792 KiB | 2,048 KiB |
| 800×480 source | 384,000 | 1,125 KiB | 2,625 KiB | 3,000 KiB |

The 512×512 tier roughly doubles the original pixel budget; an RGBA image alone occupies 37.5% of a 2 MiB LVGL pool after conversion. An 800×480 image occupies about 55%. Neither is justified as a common default merely because a supported screen has that resolution. Consider such tiers only after native-memory and lifecycle testing on the actual firmware/radio combinations. Do not add STB temporary usage to the LVGL pool alone: these are distinct allocations, although both contribute to overall RAM demand.

## Why 512 KiB rather than 100 or 256 KiB?

Encoded size and decoded pixel count measure different costs. A small compressed PNG can have a huge pixel area, and a poorly compressed image with a reasonable area can be large on disk. Retain both checks.

- **100 KiB:** existing conservative file policy; no inspected decoder source establishes it as an upstream limit.
- **256 KiB:** a reasonable stricter file/IO budget, but excludes ordinary uncompressed BMP24/BMP32 near the recommended pixel maximum, and can exclude valid noisy PNGs.
- **512 KiB:** recommended companion to the unchanged pixel budget. A basic BMP32 at 130,560 pixels needs approximately 522,294 bytes including a 54-byte header, just below 524,288. It also accommodates typical uncompressed RGBA8 PNG encodings at this area, but not every possible metadata-heavy export. It increases permitted SD input and PNG compressed-workspace cost compared with 100 KiB; it is not a cost-free change.
- **1 MiB:** offers little reason for the common 130,560-pixel budget; principally admits additional metadata or less efficient encodings while raising allowed input/workspace. Reserve consideration for a measured larger-image tier.

These limits are resource screening, **not a strict peak-memory bound or full image-integrity check**. STB can allocate for an IDAT chunk's declared length before discovering truncated file data, and accepts inflated data beyond the expected pixel stream. File/header checks cannot guarantee successful native decoding of arbitrary damaged files. [Chunk allocation](https://github.com/nothings/stb/blob/5c205738c191bcb0abc65c4febfa9bd25ff35234/stb_image.h#L5182-L5194), [raw-length acceptance](https://github.com/nothings/stb/blob/5c205738c191bcb0abc65c4febfa9bd25ff35234/stb_image.h#L4722-L4725).

Before claiming a broader supported tier, measure native free memory and largest free blocks alongside Lua memory, cold loading/scaling responsiveness, and repeated model/image changes with both dashboard variants and RF Tool on the smallest-memory supported target. No such transmitter results are supplied by this research.
