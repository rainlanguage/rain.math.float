#!/usr/bin/env bash
# Fails when the committed gas snapshot is stale against a fresh one.
#
# Non-fuzz rows must match exactly. Fuzz μ/~ are not reproducible across
# machines even with a fixed seed, so every `(runs: N, μ: X, ~: Y)` is reduced
# to `(fuzz)` on both sides: fuzz rows compare by name only. `forge snapshot
# --check` has no per-row mode, and `--tolerance` would loosen non-fuzz rows
# too. Adding, removing or renaming any test, fuzz or not, still fails.
#
# Usage: check-gas-snapshot.sh <committed> <fresh>
set -eu
committed=$1
fresh=$2
normalise() { sed -E 's/\(runs: [0-9]+, μ: [0-9]+, ~: [0-9]+\)$/(fuzz)/' "$1"; }
diff -u <(normalise "$committed") <(normalise "$fresh") || {
  echo "::error file=$committed::stale: regenerate with 'nix develop -c forge snapshot --fuzz-seed 0' and commit it"
  exit 1
}
