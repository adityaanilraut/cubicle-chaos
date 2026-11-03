#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"

if [[ -z "$godot_bin" ]]; then
  if command -v godot >/dev/null 2>&1; then
    godot_bin="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then
    godot_bin="$(command -v godot4)"
  elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    godot_bin=/Applications/Godot.app/Contents/MacOS/Godot
  else
    echo "Godot was not found. Set GODOT_BIN to your Godot executable." >&2
    exit 1
  fi
fi

mkdir -p "$project_dir/build/web"
touch "$project_dir/build/.gdignore"
# Import first so this also works from a fresh checkout.
"$godot_bin" --headless --path "$project_dir" --import
"$godot_bin" --headless --path "$project_dir" --export-release Web "$project_dir/build/web/index.html"
echo "Web build ready: $project_dir/build/web/index.html"
echo "Preview: python3 -m http.server 8060 --bind 127.0.0.1 --directory \"$project_dir/build/web\""
