#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# test-check-run.sh
# Runs check-run.sh on the fixture logs and reports beside it, in the shape of
# halmos 0.3.3's text output and --json-output: a complete proof passes, and
# each way a run can fall short fails with the message of the check that saw
# it, so a check that stops looking is caught here.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
check="$here/check-run.sh"
fixtures="$here/fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# passes <case> <check-run.sh args>
passes() {
  local case=$1
  shift
  out=$("$check" "$@" 2>&1) || fail "$case: exit $? with: $out"
}

# fails <case> <message> <check-run.sh args>
fails() {
  local case=$1 message=$2
  shift 2
  if out=$("$check" "$@" 2>&1); then fail "$case: passed with: $out"; fi
  grep -qF -- "$message" <<<"$out" || fail "$case: wrong reason: $out"
}

passes "one proof" 0 1 "$fixtures/pass.log" "$fixtures/pass.log.json"
passes "three proofs" 0 3 "$fixtures/quick.log" "$fixtures/quick.log.json"

# The time limit, by timeout's exit codes, before the report is read.
fails "timeout" "over the time limit: cut this slice smaller" 124 1 "$fixtures/timeout.log" "$tmp/none.json"
fails "killed" "over the time limit: cut this slice smaller" 137 1 "$fixtures/timeout.log" "$tmp/none.json"
HALMOS_RUN_SECONDS=300 fails "timeout names the limit" "over the time limit of 300s" 124 1 "$fixtures/timeout.log" "$tmp/none.json"

# The report.
fails "fewer tests than expected" "halmos report: expected 2 complete passing tests" 0 2 "$fixtures/pass.log" "$fixtures/pass.log.json"
fails "more tests than expected" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/quick.log" "$fixtures/quick.log.json"
fails "counterexample" "halmos report: expected 1 complete passing tests" 1 1 "$fixtures/counterexample.log" "$fixtures/counterexample.log.json"
fails "bounded loop" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/bounded.log" "$fixtures/bounded.log.json"
fails "bounded loop in the report alone" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$fixtures/bounded.log.json"
jq '.exitcode = 2' "$fixtures/pass.log.json" >"$tmp/exitcode.json"
fails "halmos exit code in the report" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$tmp/exitcode.json"
jq 'del(.test_results[][0].num_bounded_loops)' "$fixtures/pass.log.json" >"$tmp/no-loops-field.json"
fails "report without the loop field" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$tmp/no-loops-field.json"
jq '.test_results[][0].num_bounded_loops = null' "$fixtures/pass.log.json" >"$tmp/null-loops.json"
fails "report with a null loop count" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$tmp/null-loops.json"
jq 'del(.test_results)' "$fixtures/pass.log.json" >"$tmp/no-results.json"
fails "report without results" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$tmp/no-results.json"
head -c 64 "$fixtures/pass.log.json" >"$tmp/truncated.json"
fails "truncated report" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$tmp/truncated.json"
fails "missing report" "halmos report: expected 1 complete passing tests" 0 1 "$fixtures/pass.log" "$tmp/none.json"
# The report's verdict is also what a failing run prints: the per-test rows.
if out=$("$check" 0 1 "$fixtures/bounded.log" "$fixtures/bounded.log.json" 2>&1); then fail "bounded loop passed"; fi
grep -q '"num_bounded_loops": 1' <<<"$out" || fail "bounded loop rows not printed: $out"

# The text log, behind a clean report.
fails "warning in the log alone" "halmos warned: the proof is incomplete" 0 1 "$fixtures/bounded.log" "$fixtures/pass.log.json"
fails "log disagrees with the report" "exit 0; expected 1 passing tests, got 0" 0 1 "$fixtures/counterexample.log" "$fixtures/pass.log.json"
fails "nonzero exit with a clean report" "exit 1; expected 1 passing tests, got 1" 1 1 "$fixtures/pass.log" "$fixtures/pass.log.json"
sed 's/^Symbolic test result: 3 passed; 0 failed;/Symbolic test result: 2 passed; 1 failed;/' "$fixtures/quick.log" >"$tmp/two.log"
fails "log short of the report" "exit 0; expected 3 passing tests, got 0" 0 3 "$tmp/two.log" "$fixtures/quick.log.json"

echo ok
