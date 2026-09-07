#!/usr/bin/env bash
# Runs every tests/*_test.sh file. Pass a filter to run a subset of tests:
#
#   tests/run.sh              # everything
#   tests/run.sh source_profile
set -uo pipefail

cd "$(dirname "$0")" || exit 1

failures=0
for file in *_test.sh; do
  echo "== $file"

  output="$(bash "$file" "$@" 2>&1)"
  status=$?
  printf '%s\n' "$output"

  # A test file that exits before printing its summary has not reported
  # anything: install.sh and update.sh both end in a call that would replace or
  # abort the process if their "only run when executed" guard regressed.
  if ! printf '%s\n' "$output" | grep -q "^$file: [0-9]* run,"; then
    echo "$file exited without reporting a summary" >&2
    status=1
  fi

  [[ $status -eq 0 ]] || failures=$((failures + 1))
done

if [[ $failures -ne 0 ]]; then
  echo "$failures test file(s) failed" >&2
  exit 1
fi

echo "All test files passed"
