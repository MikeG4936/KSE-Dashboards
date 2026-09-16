#!/bin/bash
# Double-click on macOS; the resizer will open a file picker.
set -e
trap 'printf "\nPress Return to close this window..."; read -r reply' EXIT
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  printf 'Python 3 is required. Install it from https://www.python.org/downloads/macos/ and try again.\n'
  exit 1
fi
if [ ! -x "$script_dir/.venv/bin/python3" ]; then
  printf 'Preparing the image resizer (first run only)...\n'
  python3 -m venv "$script_dir/.venv"
fi
if ! "$script_dir/.venv/bin/python3" -c 'from PIL import Image; Image.Resampling.LANCZOS' >/dev/null 2>&1; then
  printf 'Installing Pillow; this requires internet access on the first run...\n'
  "$script_dir/.venv/bin/python3" -m pip install --disable-pip-version-check --upgrade Pillow
fi
"$script_dir/.venv/bin/python3" "$script_dir/resize_kse_images.py" --interactive "$@"
