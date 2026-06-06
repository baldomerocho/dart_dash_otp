#!/usr/bin/env bash
#
# Run the test suite with coverage, generate an LCOV report, and enforce a
# minimum total line coverage threshold. This mirrors the "coverage" job in
# .github/workflows/ci.yaml so it can be run locally before pushing.
#
# Usage: ./tool/coverage.sh
#
set -euo pipefail

MIN_COVERAGE=90

# Prefer the project-pinned toolchain (fvm). Fall back to a plain `dart` on
# PATH when fvm is not installed (e.g. on CI runners).
if command -v fvm >/dev/null 2>&1; then
  DART="fvm dart"
else
  DART="dart"
fi

echo "Using toolchain: ${DART}"

$DART pub get
$DART pub global activate coverage
$DART test --coverage=coverage
$DART pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib

LCOV_FILE="coverage/lcov.info"
if [[ ! -f "$LCOV_FILE" ]]; then
  echo "error: $LCOV_FILE was not generated" >&2
  exit 1
fi

# LCOV records:
#   LF: lines found (instrumented)
#   LH: lines hit (covered)
# Total line coverage = sum(LH) / sum(LF) * 100.
COVERAGE=$(awk -F: '
  /^LF:/ { found += $2 }
  /^LH:/ { hit   += $2 }
  END {
    if (found == 0) { print "0.00" }
    else { printf "%.2f", (hit / found) * 100 }
  }
' "$LCOV_FILE")

echo "Total line coverage: ${COVERAGE}%"

# Compare as floats using awk (bash cannot compare decimals directly).
if awk -v c="$COVERAGE" -v m="$MIN_COVERAGE" 'BEGIN { exit !(c < m) }'; then
  echo "error: coverage ${COVERAGE}% is below the required minimum of ${MIN_COVERAGE}%" >&2
  exit 1
fi

echo "Coverage meets the minimum of ${MIN_COVERAGE}%."
