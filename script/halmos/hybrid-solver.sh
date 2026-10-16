#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# hybrid-solver.sh <query.smt2>
# Each stage answers only what it decides:
# 1. yices, briefly: decides most queries halmos makes before it refines
#    division, unsat or sat, in well under a second. A sat goes to bitwuzla,
#    whose model halmos parses and refines from.
# 2. cvc5 --solve-bv-as-int=sum: integer encoding proves chained
#    constant-division identities (x/10/10 == x/100) bit-blasters cannot.
# 3. yices for longer.
# Anything else falls through to bitwuzla.
# An unsat is a proof for the query as given (uninterpreted div/mul
# over-approximate the real ops) under the answering solver's correctness.
# Stages 1 and 3 and bitwuzla decide the bit-vector query itself; stage 2
# decides cvc5's integer translation of it, a mode far less exercised than
# bit-blasting, so its unsat also rests on that translation being sound, and no
# second solver checks it. With HYBRID_STAGE_LOG set, each query appends
# `<stage> <answer> <query>` there (yices-quick, cvc5-int, yices, or bitwuzla
# with `-`: it replaces this process, so its answer goes to halmos), so a
# proof's trust base can be read off the run.
# cvc5, yices-smt2 and bitwuzla are resolved from PATH.
query=$1
first() {
  printf '%s\n' "$1" | head -1
}
stage() {
  if [ -n "${HYBRID_STAGE_LOG:-}" ]; then
    echo "$1 $2 $query" >>"$HYBRID_STAGE_LOG"
  fi
}
out=$(first "$(timeout "${HYBRID_YICES_QUICK_TIMEOUT:-1}" yices-smt2 "$query" 2>/dev/null)")
if [ "$out" = unsat ]; then
  stage yices-quick unsat
  echo unsat
  exit 0
fi
if [ "$out" = sat ]; then
  stage yices-quick sat
  exec bitwuzla --produce-models "$query"
fi
out=$(first "$(timeout "${HYBRID_CVC5_TIMEOUT:-5}" cvc5 --solve-bv-as-int=sum "$query" 2>/dev/null)")
if [ "$out" = unsat ]; then
  stage cvc5-int unsat
  echo unsat
  exit 0
fi
out=$(first "$(timeout "${HYBRID_YICES_TIMEOUT:-60}" yices-smt2 "$query" 2>/dev/null)")
if [ "$out" = unsat ]; then
  stage yices unsat
  echo unsat
  exit 0
fi
stage bitwuzla -
exec bitwuzla --produce-models "$query"
