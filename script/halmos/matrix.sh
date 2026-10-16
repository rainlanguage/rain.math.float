#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# matrix.sh [lemma] [matrix.json]
# Prints the halmos workflow's job matrix as one line of JSON: the entries of
# matrix.json (beside this script) named `lemma` or `lemma-*`, every entry for
# `all` (the default), each sliced entry expanded to one job per slice. No
# entry selected is an error.
# An entry has `name`, `solver` (bitwuzla, yices or hybrid), `expect` (the
# tests its --contract/--function filter must match; a filter that silently
# matches fewer fails the job) and `args`. A sliced entry also has `range`,
# its case indices, and `starts`: slice i is [starts[i], starts[i + 1] - 1],
# the last one ending at range[1], so the slices tile the range, or this
# errors. Each slice is a job named `name-lo-hi` with `lo` and `hi`, run with
# HALMOS_SLICE_LO/HI (`LibHalmosExact.inSlice`), so its --function filter must
# match that one lemma.
# pack-low's cases 99-780 (e in [int32.min - 70, int32.min - 9]) are out: at
# about 25s each they need more slices than a matrix carries (#511).
set -euo pipefail
lemma=${1:-all}
matrix=${2:-$(cd "$(dirname "$0")" && pwd)/matrix.json}
jq -c --arg lemma "$lemma" '
  [.[]
   | select($lemma == "all" or .name == $lemma or (.name | startswith($lemma + "-")))
   | if has("starts") then
       . as $l
       | if ($l.starts[0] != $l.range[0]) or ($l.starts[-1] > $l.range[1])
            or ([$l.starts | range(1; length) as $i | $l.starts[$i] > $l.starts[$i - 1]] | all | not)
         then error("\($l.name): starts do not tile \($l.range)") else . end
       | ($l.starts + [$l.range[1] + 1]) as $b
       | range(0; $l.starts | length) as $i
       | $l + {name: "\($l.name)-\($b[$i])-\($b[$i + 1] - 1)", lo: $b[$i], hi: ($b[$i + 1] - 1)}
       | del(.starts, .range)
     else . end]
  | if length == 0 then error("no lemma named \($lemma)") else . end' "$matrix"
