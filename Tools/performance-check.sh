#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Optional source tree allows a before/after comparison with the same harness.
SOURCE_ROOT="${1:-.}"
OUTPUT="${2:-.build/performance-check}"
mkdir -p "$OUTPUT"
python3 - "$SOURCE_ROOT" "$OUTPUT" <<'PY'
import pathlib, subprocess, sys
root, output = map(pathlib.Path, sys.argv[1:])
sources = sorted(str(p) for p in (root / 'Sources').rglob('*.swift') if p.name != 'DaktRecorderApp.swift')
subprocess.run(['swiftc', '-O', '-parse-as-library', '-framework', 'ScreenCaptureKit', '-framework', 'Carbon',
                *sources, 'Tools/PerformanceBenchmark.swift', '-o', str(output / 'benchmark')], check=True)
PY
"$OUTPUT/benchmark" | tee "$OUTPUT/results.jsonl"
