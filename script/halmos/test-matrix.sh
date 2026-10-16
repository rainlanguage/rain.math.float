#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# test-matrix.sh
# Runs matrix.sh on matrix.json beside it and on matrices derived from it: the
# whole matrix is 71 jobs of the right shape whose slices tile each sliced
# entry's range (re-derived here from the jobs' lo/hi, not from starts), the
# dispatch choices select what they name and together cover every job, and
# starts that do not tile, or a lemma no entry is named for, are errors.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
matrix="$here/matrix.sh"
real="$here/matrix.json"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Every job, one line of compact JSON.
all=$("$matrix")
[ "$(wc -l <<<"$all")" = 1 ] || fail "not one line: $all"
[ "$("$matrix" all)" = "$all" ] || fail "all differs from the default"
jq -e 'length == 71' <<<"$all" >/dev/null || fail "expected 71 jobs, got $(jq length <<<"$all")"
jq -e '[.[].name] | length == (unique | length)' <<<"$all" >/dev/null || fail "duplicate job names"
jq -e 'all(has("name") and has("solver") and has("expect") and has("args")
           and ((has("range") or has("starts")) | not)
           and ((has("lo") and has("hi") and .lo <= .hi) or ((has("lo") or has("hi")) | not)))' <<<"$all" >/dev/null \
  || fail "job shape: $all"
jq -e 'all(.solver == "bitwuzla" or .solver == "yices" or .solver == "hybrid")' <<<"$all" >/dev/null || fail "solver names"

# Unsliced entries are jobs as they are.
for name in quick divhint pack-below pack-above far; do
  jq -e --arg n "$name" 'map(select(.name == $n)) | length == 1 and (.[0] | (has("lo") | not))' <<<"$all" >/dev/null \
    || fail "$name is not one unsliced job"
done

# Each sliced entry: its jobs sorted by lo start at range[0], end at range[1],
# meet with no gap or overlap, number as many as its starts, and are named
# name-lo-hi.
jq -e --slurpfile m "$real" '
  . as $jobs
  | [$m[0][] | select(has("starts")) | . as $l
     | ([$jobs[] | select(.name | test("^\($l.name)-[0-9]+-[0-9]+$"))] | sort_by(.lo))
     | length == ($l.starts | length)
       and .[0].lo == $l.range[0] and .[-1].hi == $l.range[1]
       and ([range(1; length) as $i | .[$i].lo == .[$i - 1].hi + 1] | all)
       and all(.name == "\($l.name)-\(.lo)-\(.hi)")]
  | all' <<<"$all" >/dev/null || fail "slices do not tile their ranges: $all"
for name in hints-0-9 hints-70-76 hints-pack-0-71 hints-pack-72-76 pack-low-0-10 pack-low-88-98 \
  pack-low-end-781-791 pack-low-end-847-857 pack-middle-0-10 pack-high-0-21 pack-high-836-857; do
  jq -e --arg n "$name" 'any(.name == $n)' <<<"$all" >/dev/null || fail "no job $name"
done
jq -e 'map(select(.name == "hints-pack-72-76")) | .[0] | .lo == 72 and .hi == 76 and .solver == "hybrid" and .expect == 1' \
  <<<"$all" >/dev/null || fail "hints-pack-72-76 slice bounds"
jq -e 'map(select(.name == "quick")) | .[0].expect == 3' <<<"$all" >/dev/null || fail "quick expects 3"

# The dispatch choices: a name selects the entry of that name and the entries
# named name-*, so `hints` runs both hint proofs and `pack` every PACK band.
[ "$(jq -c '[.[].name]' <<<"$("$matrix" quick)")" = '["quick"]' ] || fail "quick selection"
[ "$(jq -c '[.[].name]' <<<"$("$matrix" divhint)")" = '["divhint"]' ] || fail "divhint selection"
[ "$(jq -c '[.[].name]' <<<"$("$matrix" far)")" = '["far"]' ] || fail "far selection"
hints=$("$matrix" hints)
jq -e 'length == 10 and (map(select(.name | startswith("hints-pack-"))) | length == 2)
       and all(.name | startswith("hints-"))' <<<"$hints" >/dev/null || fail "hints selection: $hints"
pack=$("$matrix" pack)
jq -e 'length == 58 and all(.name | startswith("pack-"))' <<<"$pack" >/dev/null || fail "pack selection: $pack"
# Together the choices are the whole matrix.
chosen=$(for lemma in quick divhint hints pack far; do "$matrix" "$lemma"; done | jq -s 'add | map(.name) | sort')
[ "$chosen" = "$(jq 'map(.name) | sort' <<<"$all")" ] || fail "the dispatch choices do not cover the matrix"

# Errors: a name no entry has, and starts that do not tile the range.
if out=$("$matrix" near 2>&1); then fail "near selected: $out"; fi
grep -q 'no lemma named near' <<<"$out" || fail "near: $out"
if out=$("$matrix" all <(echo '[]') 2>&1); then fail "empty matrix selected: $out"; fi
grep -q 'no lemma named all' <<<"$out" || fail "empty matrix: $out"
bad() {
  local case=$1 filter=$2
  jq "$filter" "$real" >"$tmp/bad.json"
  if out=$("$matrix" all "$tmp/bad.json" 2>&1); then fail "$case accepted: $out"; fi
  grep -q 'hints: starts do not tile \[0,76\]' <<<"$out" || fail "$case: $out"
}
bad "first start past range[0]" 'map(if .name == "hints" then .starts[0] = 1 else . end)'
bad "last start past range[1]" 'map(if .name == "hints" then .starts += [77] else . end)'
bad "starts out of order" 'map(if .name == "hints" then .starts = [0, 20, 10] else . end)'
bad "repeated start" 'map(if .name == "hints" then .starts = [0, 10, 10] else . end)'
# The same checks leave a tiling untouched: starts ending exactly at range[1]
# is a one-case last slice.
jq 'map(if .name == "hints" then .starts += [76] else . end)' "$real" >"$tmp/edge.json"
jq -e 'map(select(.name == "hints-76-76")) | length == 1' <<<"$("$matrix" hints "$tmp/edge.json")" >/dev/null \
  || fail "one-case last slice"

echo ok
