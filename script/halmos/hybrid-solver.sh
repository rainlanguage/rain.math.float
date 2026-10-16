#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# hybrid-solver.sh <query.smt2>
# Each stage answers only what it decides, which is sound for the query as
# given (uninterpreted div/mul over-approximate the real ops):
# 1. yices, briefly: decides most queries halmos makes before it refines
#    division, unsat or sat, in well under a second. A sat goes to bitwuzla,
#    whose model halmos parses and refines from.
# 2. cvc5 --solve-bv-as-int=sum: integer encoding proves chained
#    constant-division identities (x/10/10 == x/100) bit-blasters cannot.
# 3. yices for longer.
# Anything else falls through to bitwuzla.
# cvc5, yices-smt2 and bitwuzla are resolved from PATH.
first() {
  printf '%s\n' "$1" | head -1
}
out=$(first "$(timeout "${HYBRID_YICES_QUICK_TIMEOUT:-1}" yices-smt2 "$1" 2>/dev/null)")
if [ "$out" = unsat ]; then
  echo unsat
  exit 0
fi
if [ "$out" = sat ]; then
  exec bitwuzla --produce-models "$1"
fi
out=$(first "$(timeout "${HYBRID_CVC5_TIMEOUT:-5}" cvc5 --solve-bv-as-int=sum "$1" 2>/dev/null)")
if [ "$out" = unsat ]; then
  echo unsat
  exit 0
fi
out=$(first "$(timeout "${HYBRID_YICES_TIMEOUT:-60}" yices-smt2 "$1" 2>/dev/null)")
if [ "$out" = unsat ]; then
  echo unsat
  exit 0
fi
exec bitwuzla --produce-models "$1"
