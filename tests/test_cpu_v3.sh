#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/check_x86_64_v3.sh"
GOOD="cx16 lahf_lm popcnt pni ssse3 sse4_1 sse4_2 avx avx2 bmi1 bmi2 f16c fma movbe xsave lzcnt"
"$SCRIPT" --flags "$GOOD" >/dev/null
if "$SCRIPT" --flags "${GOOD// pni/}" >/dev/null 2>&1; then
  echo "FAIL: missing pni was accepted" >&2
  exit 1
fi
if "$SCRIPT" --flags "${GOOD// lzcnt/}" >/dev/null 2>&1; then
  echo "FAIL: missing lzcnt/abm was accepted" >&2
  exit 1
fi
"$SCRIPT" --flags "${GOOD// lzcnt/ abm}" >/dev/null
echo "CPU feature-check tests passed."
