#!/usr/bin/env python3
"""Prepare model pictures for KSE4 or KSE5, preserving originals and transparency."""
import argparse
from datetime import datetime
from io import BytesIO
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image

# Measured through the actual full-screen image construction in both dashboards.
SIZES = {
    "KSE4": {"800x480": (272, 144), "480x320": (164, 97), "480x272": (164, 82)},
    "KSE5": {"800x480": (377, 156), "480x320": (225, 104), "480x272": (228, 98)},
}
SUPPORTED = {".png", ".bmp"}


def prepare_image(source, size):
    """Return PNG bytes, using the same crop/resampling as the prepared assets."""
    with Image.open(source) as image:
        image = image.convert("RGBA")
        bounds = image.getchannel("A").getbbox()
        if bounds is None:
            raise ValueError("image is entirely transparent")
        cropped = image.crop(bounds)
        scale = min((size[0] - 4) / cropped.width, (size[1] - 4) / cropped.height)
        target = (max(1, round(cropped.width * scale)),
                  max(1, round(cropped.height * scale)))
        # Premultiplied alpha prevents dark/color fringes at transparent edges.
        resized = cropped.convert("RGBa").resize(target, Image.Resampling.LANCZOS).convert("RGBA")
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        canvas.paste(resized, ((size[0] - target[0]) // 2, (size[1] - target[1]) // 2))
        stream = BytesIO()
        canvas.save(stream, format="PNG", optimize=True)
        data = stream.getvalue()
        if len(data) > 512 * 1024:
            raise ValueError("result exceeds KSE's 512 KiB file limit")
        return data


def choose_files():
    if sys.platform == "win32":
        script = '''
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Windows.Forms
$picker = New-Object System.Windows.Forms.OpenFileDialog
$picker.Title = 'Select the PNG or BMP model pictures to resize'
$picker.Filter = 'Model pictures (*.png;*.bmp)|*.png;*.bmp'
$picker.Multiselect = $true
try {
    if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        ConvertTo-Json -Compress -InputObject @($picker.FileNames)
    } else { '[]' }
} finally { $picker.Dispose() }
'''
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-STA", "-Command", script],
            capture_output=True, text=True, encoding="utf-8")
        if result.returncode:
            raise ValueError("could not open the file picker: " + result.stderr.strip())
        return [Path(name) for name in json.loads(result.stdout.lstrip("\ufeff"))]
    if sys.platform != "darwin":
        raise ValueError("provide image filenames or a folder on the command line")
    script = '''
set filesToResize to choose file with prompt "Select the PNG or BMP model pictures to resize" with multiple selections allowed
set paths to ""
repeat with chosenFile in filesToResize
    set paths to paths & POSIX path of chosenFile & linefeed
end repeat
return paths
'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if result.returncode:
        if "-128" in result.stderr:
            return []
        raise ValueError("could not open the file picker: " + result.stderr.strip())
    return [Path(line) for line in result.stdout.splitlines() if line]


def select_option(title, choices, default):
    print("\n" + title)
    for number, choice in enumerate(choices, 1):
        suffix = " (default)" if choice == default else ""
        print(f"  {number}. {choice}{suffix}")
    while True:
        answer = input("Enter a number, or press Return for the default: ").strip()
        if not answer:
            return default
        if answer.isdigit() and 1 <= int(answer) <= len(choices):
            return choices[int(answer) - 1]
        print("Please choose one of the listed numbers.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="*", type=Path, help="PNG/BMP files or folders (not recursive)")
    parser.add_argument("--dashboard", choices=["KSE4", "KSE5", "both"], default="KSE5",
                        help="target dashboard; 'both' creates separate KSE4 and KSE5 folders")
    parser.add_argument("--screen", choices=SIZES["KSE5"], default="800x480", help="full-screen radio resolution")
    parser.add_argument("--interactive", action="store_true", help="ask which dashboard and screen to target")
    parser.add_argument("--output", type=Path, help="destination folder; existing files are never overwritten")
    args = parser.parse_args(argv)
    try:
        if args.interactive:
            args.dashboard = select_option("Dashboard (both creates separate sets):", ["KSE4", "KSE5", "both"], args.dashboard)
            args.screen = select_option("Radio screen resolution:", list(SIZES["KSE5"]), args.screen)
        inputs = args.inputs or choose_files()
        if not inputs:
            print("Cancelled; no files changed.")
            return 0
        files = []
        for item in inputs:
            candidates = sorted(item.iterdir()) if item.is_dir() else [item]
            for candidate in candidates:
                if candidate.suffix.lower() in SUPPORTED and candidate.resolve() not in files:
                    files.append(candidate.resolve())
        if not files:
            raise ValueError("no PNG or BMP files selected")
        if args.output:
            output = args.output.expanduser().resolve()
            output.mkdir(parents=True, exist_ok=True)
        else:
            base = Path(__file__).resolve().parent / "Resized Images"
            stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            stamp += "_" + args.dashboard + "_" + args.screen
            output = base / stamp
            suffix = 2
            while output.exists():
                output = base / (stamp + "_" + str(suffix))
                suffix += 1
            output.mkdir(parents=True)
        failures = 0
        dashboards = list(SIZES) if args.dashboard == "both" else [args.dashboard]
        for dashboard in dashboards:
            size = SIZES[dashboard][args.screen]
            folder = output / dashboard if args.dashboard == "both" else output
            folder.mkdir(parents=True, exist_ok=True)
            for source in files:
                destination = folder / (source.stem + ".png")
                try:
                    if destination.exists():
                        raise ValueError("destination already exists; choose a different output folder")
                    data = prepare_image(source, size)
                    # Exclusive creation also prevents accidental source replacement.
                    with destination.open("xb") as file:
                        file.write(data)
                    print(f"Saved {dashboard}/{destination.name}: {size[0]} x {size[1]}, {len(data) / 1024:.1f} KiB")
                except (OSError, ValueError, Image.DecompressionBombError) as error:
                    failures += 1
                    print(f"Skipped {dashboard}/{source.name}: {error}", file=sys.stderr)
        print(f"\nOutput: {output}")
        print("Match filenames to the name displayed by KSE, then copy to /IMAGES on the SD card.")
        print("Restart the radio after replacing images to clear cached image data.")
        return 1 if failures else 0
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        return 1
    except (OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
