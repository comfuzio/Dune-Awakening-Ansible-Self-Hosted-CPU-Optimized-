#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--flags" ]]; then
  [[ $# -eq 2 ]] || { echo "Usage: $0 [--flags 'space separated CPU flags']" >&2; exit 2; }
  flags="$2"
else
  flags="$(awk -F: '/^flags[[:space:]]*:/ {print $2; exit}' /proc/cpuinfo)"
fi

if [[ -z "$flags" ]]; then
  echo "Could not read x86 CPU flags." >&2
  exit 2
fi

# Linux exposes SSE3 as pni and may expose LZCNT as abm.
required="cx16 lahf_lm popcnt pni ssse3 sse4_1 sse4_2 avx avx2 bmi1 bmi2 f16c fma movbe xsave"
for flag in $required; do
  case " $flags " in
    *" $flag "*) ;;
    *) echo "Missing x86-64-v3 CPU flag: $flag" >&2; exit 1 ;;
  esac
done

case " $flags " in
  *" lzcnt "*) ;;
  *" abm "*) ;;
  *) echo "Missing x86-64-v3 CPU flag: lzcnt/abm" >&2; exit 1 ;;
esac

echo "CPU flags satisfy the x86-64-v3 feature check."
