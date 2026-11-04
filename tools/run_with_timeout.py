#!/usr/bin/env python3
"""Run a test with a portable timeout, preserving its output."""
import subprocess
import sys

try:
    result = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    print(f"Timed out after {sys.argv[1]} seconds", file=sys.stderr)
    sys.exit(124)
sys.exit(result.returncode)
