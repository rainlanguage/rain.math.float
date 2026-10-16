#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# check-run.sh <exit> <expect> <log> <report.json>
# The verdict on one run of the halmos workflow, from the exit code of
# `timeout -k 10 $HALMOS_RUN_SECONDS halmos --json-output <report.json>`, its
# text output in <log> and that report. Exit 0 is a complete proof of exactly
# <expect> tests; anything else exits 1 and says why.
# - Exit 124 or 137: the run hit the time limit, cut the slice smaller.
# - The report decides: halmos's own exit code 0, exactly <expect> tests each
#   with exit code 0 (not a counterexample, timeout, stuck path, all-revert or
#   error) and no loop cut short by the bound, which leaves a proof
#   incomplete. A missing file or field fails.
# - Backstops on the text log: a WARNING the report has no field for (the
#   --width limit), and the pass count as printed, which must be <expect>.
set -euo pipefail
code=$1
expect=$2
log=$3
report=$4
if [ "$code" = 124 ] || [ "$code" = 137 ]; then
  echo "over the time limit${HALMOS_RUN_SECONDS:+ of ${HALMOS_RUN_SECONDS}s}: cut this slice smaller"
  exit 1
fi
if ! jq -e --argjson expect "$expect" '
      .exitcode == 0
      and ([.test_results[][]] | length == $expect
           and all(.exitcode == 0 and .num_bounded_loops == 0))' "$report" >/dev/null; then
  echo "halmos report: expected $expect complete passing tests"
  jq '.test_results[][] | {name, exitcode, num_bounded_loops}' "$report" || true
  exit 1
fi
if grep -q WARNING "$log"; then
  echo "halmos warned: the proof is incomplete"
  exit 1
fi
passed=$(awk '/^Symbolic test result: [0-9]+ passed; 0 failed;/ { n += $4 } END { print n + 0 }' "$log")
if [ "$code" != 0 ] || [ "$passed" != "$expect" ]; then
  echo "exit $code; expected $expect passing tests, got $passed"
  exit 1
fi
echo "$passed passed"
