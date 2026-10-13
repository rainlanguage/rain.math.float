#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# hybrid-solver.sh <query.smt2>
# Each stage passes on only an unsat, which is sound for the query as given
# (uninterpreted div/mul over-approximate the real ops):
# 1. cvc5 --solve-bv-as-int=sum: integer encoding proves chained
#    constant-division identities (x/10/10 == x/100) bit-blasters cannot.
# 2. yices.
# Anything else falls through to bitwuzla, whose sat model keeps halmos's
# refinement step intact.
# cvc5, yices-smt2 and bitwuzla are resolved from PATH.
for stage in cvc5 yices; do
  if [ $stage = cvc5 ]; then
    out=$(timeout "${HYBRID_CVC5_TIMEOUT:-5}" cvc5 --solve-bv-as-int=sum "$1" 2>/dev/null)
  else
    out=$(timeout "${HYBRID_YICES_TIMEOUT:-60}" yices-smt2 "$1" 2>/dev/null)
  fi
  if [ "$(printf '%s\n' "$out" | head -1)" = unsat ]; then
    echo unsat
    exit 0
  fi
done
exec bitwuzla --produce-models "$1"
