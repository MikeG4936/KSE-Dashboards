# KSE image resizer for Windows and Mac

Prepare pictures for either KSE4 or KSE5: trim transparent margins, preserve proportions and transparency, and resize to the dashboard's image box with a two-pixel margin. Original files are never overwritten.

## Using the resizer

1. Save **[KSE Image Resizer.html](KSE%20Image%20Resizer.html)** to your computer. On GitHub, open the file and use **Download raw file**; do not save the GitHub page itself.
2. Double-click the downloaded HTML file to open it in a current version of Edge, Chrome, Firefox or Safari. **No installation or internet connection is needed.** Your pictures stay on your computer.
3. Choose **KSE4**, **KSE5**, or **both**, then choose your model under **Transmitter / screen size**. RadioMaster and Jumper models are grouped by brand; if yours is unlisted, use a plain screen-resolution choice at the bottom.
4. Drop PNG or BMP pictures onto the tool, or click **Choose pictures**. Check the previews.
5. Click **Download all (ZIP)** and extract it, or download individual PNGs. Choosing **both** creates separate **KSE4** and **KSE5** folders in the ZIP.
6. Copy the desired PNGs to `/IMAGES` on your SD card. Their names must match the name displayed by KSE. **Restart the radio after replacing images** to clear cached image data.

The browser tool accepts up to 30 pictures at a time, up to 20 MB and 16 million pixels each. Duplicate filenames get a numbered suffix; rename those to match the dashboard before copying them to your radio.

## Dashboard sizes

The default is **KSE5 / RadioMaster TX16S MK3 / MAX (800 × 480)**. The original TX16S and MKII share one entry, including their MAX editions. Choosing a transmitter selects its screen resolution; these presets match the current full-screen dashboard layouts:

| Radio resolution | KSE4 image size | KSE5 image size |
| --- | --- | --- |
| 800 × 480 | 272 × 144 | 377 × 156 |
| 480 × 320 | 164 × 97 | 225 × 104 |
| 480 × 272 | 164 × 82 | 228 × 98 |

Smaller widget zones or future layout changes may require display scaling. If the same model picture is shared by KSE4 and KSE5 on one SD card, use the KSE5 copy; KSE4 can scale it down. Do not copy both versions over the same filename.

Transparent pixels stay transparent. Solid backgrounds are retained; the tool does not redraw the aircraft or remove painted backgrounds. Enlarging a small source cannot restore missing detail. BMP inputs become PNGs; existing PNG names are retained unless a duplicate or invalid filename needs adjusting. For OMP Auto, use `OMP M1.png` and `OMP M2.png`.
