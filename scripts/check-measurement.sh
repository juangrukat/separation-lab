#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/separation-checks.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -O \
  SeparationLab/Measurement.swift \
  SeparationLab/Registration.swift \
  Tests/MeasurementChecks.swift \
  -o "$test_dir/measurement-checks"
"$test_dir/measurement-checks"
