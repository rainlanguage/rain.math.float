#!/usr/bin/env bash
# Runs check-gas-snapshot.sh on snapshot pairs: fuzz rows may change their
# statistics, everything else must match exactly, and a stale snapshot names
# the regenerate command.
set -eu
check="$(dirname "$0")/check-gas-snapshot.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/committed" <<'EOF'
LibDecimalFloatAbsTest:testAbsInt224Min() (gas: 7557)
LibDecimalFloatAbsTest:testAbsNegative(int256,int32) (runs: 5096, μ: 2577, ~: 2838)
LibDecimalFloatAbsTest:testAbsZero(uint32) (runs: 5096, μ: 516, ~: 516)
LibDecimalFloatAddRuleTest:testAddRuleCancelExact() (gas: 296247)
EOF

passed=0
failed=0
# expect <case> <pass|fail> <fresh> [<text the output must contain>]
# A passing check must not print an error annotation.
expect() {
  local case=$1 want=$2 fresh=$3 needle=${4-} out got ok=1
  if out=$(bash "$check" "$work/committed" "$fresh" 2>&1); then got=pass; else got=fail; fi
  [ "$got" = "$want" ] || ok=0
  [ -z "$needle" ] || [[ $out == *"$needle"* ]] || ok=0
  [ "$want" = fail ] || [[ $out != *"::error"* ]] || ok=0
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL $case: wanted $want${needle:+ naming $needle}, got $got:"
    echo "$out"
  fi
}
# fresh <case> <sed script applied to the committed file>
fresh() {
  sed -E "$2" "$work/committed" >"$work/$1"
  echo "$work/$1"
}

expect "identical" pass "$(fresh identical '')"
expect "fuzz statistics changed" pass \
  "$(fresh fuzz 's/runs: 5096, μ: 2577, ~: 2838/runs: 4000, μ: 9999, ~: 1/')"
expect "non-fuzz gas changed" fail \
  "$(fresh gas 's/gas: 7557/gas: 7558/')" \
  "regenerate with 'nix develop -c forge snapshot --fuzz-seed 0'"
expect "non-fuzz row removed" fail "$(fresh removed '/testAddRuleCancelExact/d')"
expect "fuzz row removed" fail "$(fresh fuzzremoved '/testAbsZero/d')"
expect "row added" fail "$(fresh added '/testAddRuleCancelExact/a LibDecimalFloatAbsTest:testAbsNew() (gas: 1)')"
expect "fuzz row renamed" fail "$(fresh renamed 's/testAbsZero\(/testAbsZeroed(/')"
expect "fuzz row signature changed" fail "$(fresh signature 's/testAbsZero\(uint32\)/testAbsZero(uint64)/')"
expect "fresh snapshot missing" fail "$work/missing"

echo "$passed passed; $failed failed"
[ "$failed" -eq 0 ]
