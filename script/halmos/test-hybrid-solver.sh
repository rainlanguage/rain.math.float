#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# test-hybrid-solver.sh
# Runs hybrid-solver.sh on the fixtures beside it: a sat query answers `sat`
# with a model, an unsat query exactly `unsat`, and a cascade whose yices stages
# time out and whose cvc5 answers `unknown` (with "unsat" in a later line) falls
# through to bitwuzla for both. cvc5, yices-smt2 and bitwuzla are resolved from
# PATH, as the solver resolves them.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
solver="$here/hybrid-solver.sh"
fixtures="$here/fixtures"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# `sat` then a model; bitwuzla answers after yices's sat.
out=$("$solver" "$fixtures/sat.smt2")
[ "$(head -1 <<<"$out")" = sat ] || fail "sat.smt2: $out"
grep -q 'define-fun x' <<<"$out" || fail "sat.smt2 without a model: $out"

# Exactly `unsat`, from yices.
out=$("$solver" "$fixtures/unsat.smt2")
[ "$out" = unsat ] || fail "unsat.smt2: $out"

# Fall-through: stub yices sleeps past both of its timeouts and prints after
# them, stub cvc5 prints `unknown` and then a line containing "unsat". Each
# stub records its call, so the order of stages and the real bitwuzla
# answering at the end are both checked.
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
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
out=$(PATH="$stubs:$PATH" HYBRID_YICES_QUICK_TIMEOUT=0.2 HYBRID_YICES_TIMEOUT=0.2 "$solver" "$fixtures/sat.smt2")
[ "$(head -1 <<<"$out")" = sat ] || fail "fall-through sat.smt2: $out"
grep -q 'define-fun x' <<<"$out" || fail "fall-through sat.smt2 without a model: $out"
[ "$(cat "$HYBRID_TEST_CALLS")" = "$stages" ] || fail "fall-through sat.smt2 stages: $(cat "$HYBRID_TEST_CALLS")"

: >"$HYBRID_TEST_CALLS"
out=$(PATH="$stubs:$PATH" HYBRID_YICES_QUICK_TIMEOUT=0.2 HYBRID_YICES_TIMEOUT=0.2 "$solver" "$fixtures/unsat.smt2")
[ "$out" = unsat ] || fail "fall-through unsat.smt2: $out"
[ "$(cat "$HYBRID_TEST_CALLS")" = "$stages" ] || fail "fall-through unsat.smt2 stages: $(cat "$HYBRID_TEST_CALLS")"

echo ok
