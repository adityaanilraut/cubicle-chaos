#!/usr/bin/env bash
# Runs every headless regression suite. Used locally and by CI.
# Usage: bash tools/run_tests.sh [godot-binary]
set -uo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${1:-${GODOT_BIN:-}}"

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

# Regression suites exercise save/load and settings. Keep those files away from
# the player's real profile on both macOS (HOME) and Linux (XDG directories).
test_profile="$(mktemp -d "${TMPDIR:-/tmp}/cubicle-chaos-tests.XXXXXX")" || exit 1
trap 'rm -rf "$test_profile"' EXIT
export HOME="$test_profile"
export XDG_DATA_HOME="$test_profile/data"
export XDG_CONFIG_HOME="$test_profile/config"

cd "$project_dir"
"$godot_bin" --headless --path . --import >/dev/null 2>&1 || true

failures=0
ran=0
for suite in tests/*_regression.gd; do
  ran=$((ran + 1))
  name="$(basename "$suite")"
  if output="$("$godot_bin" --headless --path . --script "res://$suite" 2>&1)"; then
    echo "PASS $name"
  else
    failures=$((failures + 1))
    echo "FAIL $name"
    echo "$output" | tail -n 30
  fi
  # A leaked-instance warning means a scene freed something late; fail on it
  # so shutdown leaks cannot creep back in.
  if echo "$output" | grep -q "ObjectDB instances were leaked"; then
    failures=$((failures + 1))
    echo "LEAK $name reported leaked ObjectDB instances"
  fi
done

echo "Ran $ran suites, $failures failure(s)."
[[ $failures -eq 0 ]]
