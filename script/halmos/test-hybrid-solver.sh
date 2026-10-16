#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# test-hybrid-solver.sh
# Runs hybrid-solver.sh on the fixtures beside it: a sat query answers `sat`
# with a model, an unsat query exactly `unsat`, and a cascade whose yices stages
# time out and whose cvc5 answers `unknown` (with "unsat" in a later line) falls
# through to bitwuzla for both; a cvc5 or a later yices that answers unsat ends
# the cascade there. The stage log names the deciding stage of every query and
# is not written when HYBRID_STAGE_LOG is unset. cvc5, yices-smt2 and bitwuzla
# are resolved from PATH, as the solver resolves them.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
solver="$here/hybrid-solver.sh"
fixtures="$here/fixtures"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
unset HYBRID_STAGE_LOG

# `sat` then a model; bitwuzla answers after yices's sat.
out=$("$solver" "$fixtures/sat.smt2")
[ "$(head -1 <<<"$out")" = sat ] || fail "sat.smt2: $out"
grep -q 'define-fun x' <<<"$out" || fail "sat.smt2 without a model: $out"

# Exactly `unsat`, from yices.
out=$("$solver" "$fixtures/unsat.smt2")
[ "$out" = unsat ] || fail "unsat.smt2: $out"

# The same two with the stage log on: one line each, the deciding stage first.
export HYBRID_STAGE_LOG="$stubs/stages"
out=$("$solver" "$fixtures/unsat.smt2")
[ "$out" = unsat ] || fail "unsat.smt2 with a stage log: $out"
[ "$(cat "$HYBRID_STAGE_LOG")" = "yices-quick unsat $fixtures/unsat.smt2" ] || fail "unsat.smt2 stage log: $(cat "$HYBRID_STAGE_LOG")"
: >"$HYBRID_STAGE_LOG"
out=$("$solver" "$fixtures/sat.smt2")
[ "$(head -1 <<<"$out")" = sat ] || fail "sat.smt2 with a stage log: $out"
[ "$(cat "$HYBRID_STAGE_LOG")" = "yices-quick sat $fixtures/sat.smt2" ] || fail "sat.smt2 stage log: $(cat "$HYBRID_STAGE_LOG")"

# Fall-through: stub yices sleeps past both of its timeouts and prints after
# them, stub cvc5 prints `unknown` and then a line containing "unsat". Each
# stub records its call, so the order of stages and the real bitwuzla
# answering at the end are both checked.
export HYBRID_TEST_CALLS="$stubs/calls"
cat >"$stubs/yices-smt2" <<'EOF'
#!/usr/bin/env bash
echo yices >>"$HYBRID_TEST_CALLS"
sleep 1
echo unsat
EOF
cat >"$stubs/cvc5" <<'EOF'
#!/usr/bin/env bash
echo cvc5 >>"$HYBRID_TEST_CALLS"
echo unknown
echo '(:reason-unknown "unsat core unavailable")'
EOF
chmod +x "$stubs/yices-smt2" "$stubs/cvc5"
stages=$'yices\ncvc5\nyices'

: >"$HYBRID_TEST_CALLS"
: >"$HYBRID_STAGE_LOG"
out=$(PATH="$stubs:$PATH" HYBRID_YICES_QUICK_TIMEOUT=0.2 HYBRID_YICES_TIMEOUT=0.2 "$solver" "$fixtures/sat.smt2")
[ "$(head -1 <<<"$out")" = sat ] || fail "fall-through sat.smt2: $out"
grep -q 'define-fun x' <<<"$out" || fail "fall-through sat.smt2 without a model: $out"
[ "$(cat "$HYBRID_TEST_CALLS")" = "$stages" ] || fail "fall-through sat.smt2 stages: $(cat "$HYBRID_TEST_CALLS")"
[ "$(cat "$HYBRID_STAGE_LOG")" = "bitwuzla - $fixtures/sat.smt2" ] || fail "fall-through sat.smt2 stage log: $(cat "$HYBRID_STAGE_LOG")"

: >"$HYBRID_TEST_CALLS"
: >"$HYBRID_STAGE_LOG"
out=$(PATH="$stubs:$PATH" HYBRID_YICES_QUICK_TIMEOUT=0.2 HYBRID_YICES_TIMEOUT=0.2 "$solver" "$fixtures/unsat.smt2")
[ "$out" = unsat ] || fail "fall-through unsat.smt2: $out"
[ "$(cat "$HYBRID_TEST_CALLS")" = "$stages" ] || fail "fall-through unsat.smt2 stages: $(cat "$HYBRID_TEST_CALLS")"
[ "$(cat "$HYBRID_STAGE_LOG")" = "bitwuzla - $fixtures/unsat.smt2" ] || fail "fall-through unsat.smt2 stage log: $(cat "$HYBRID_STAGE_LOG")"

# Stage 2 decides: stub cvc5 answers unsat after the quick yices times out, so
# the answer is `unsat` and neither the longer yices nor bitwuzla runs.
cat >"$stubs/cvc5" <<'EOF'
#!/usr/bin/env bash
echo cvc5 >>"$HYBRID_TEST_CALLS"
echo unsat
EOF
: >"$HYBRID_TEST_CALLS"
: >"$HYBRID_STAGE_LOG"
out=$(PATH="$stubs:$PATH" HYBRID_YICES_QUICK_TIMEOUT=0.2 HYBRID_YICES_TIMEOUT=0.2 "$solver" "$fixtures/sat.smt2")
[ "$out" = unsat ] || fail "cvc5 unsat: $out"
[ "$(cat "$HYBRID_TEST_CALLS")" = $'yices\ncvc5' ] || fail "cvc5 unsat stages: $(cat "$HYBRID_TEST_CALLS")"
[ "$(cat "$HYBRID_STAGE_LOG")" = "cvc5-int unsat $fixtures/sat.smt2" ] || fail "cvc5 unsat stage log: $(cat "$HYBRID_STAGE_LOG")"

# Stage 3 decides: stub yices answers unsat after 0.5s, past the quick timeout
# and inside the longer one, with stub cvc5 back to unknown.
cat >"$stubs/yices-smt2" <<'EOF'
#!/usr/bin/env bash
echo yices >>"$HYBRID_TEST_CALLS"
sleep 0.5
echo unsat
EOF
cat >"$stubs/cvc5" <<'EOF'
#!/usr/bin/env bash
echo cvc5 >>"$HYBRID_TEST_CALLS"
echo unknown
EOF
: >"$HYBRID_TEST_CALLS"
: >"$HYBRID_STAGE_LOG"
out=$(PATH="$stubs:$PATH" HYBRID_YICES_QUICK_TIMEOUT=0.2 HYBRID_YICES_TIMEOUT=5 "$solver" "$fixtures/sat.smt2")
[ "$out" = unsat ] || fail "long yices unsat: $out"
[ "$(cat "$HYBRID_TEST_CALLS")" = "$stages" ] || fail "long yices unsat stages: $(cat "$HYBRID_TEST_CALLS")"
[ "$(cat "$HYBRID_STAGE_LOG")" = "yices unsat $fixtures/sat.smt2" ] || fail "long yices unsat stage log: $(cat "$HYBRID_STAGE_LOG")"

# Unset, the stage log is not written.
unset HYBRID_STAGE_LOG
rm -f "$stubs/stages"
out=$("$solver" "$fixtures/unsat.smt2")
[ "$out" = unsat ] || fail "unsat.smt2 without a stage log: $out"
[ ! -e "$stubs/stages" ] || fail "stage log written while unset"

echo ok
