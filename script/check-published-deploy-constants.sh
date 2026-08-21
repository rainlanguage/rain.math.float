#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
#
# Checks that the per-version deploy constants pinned in LibDecimalFloatDeploy.sol
# are complete. Each published version needs a full suite: a log-tables address +
# codehash and a DecimalFloat address + codehash, each suffixed with the version
# (dots replaced by underscores).
#
# Two halves, split by what they depend on:
#
#   1. STRUCTURAL (offline). Every version suffix that carries any pinned
#      constant must carry all four. Catches a half-written release snapshot.
#      Pure file inspection, so it is deterministic and always runs.
#   2. REGISTRY (online). Every version published to the soldeer registry must
#      carry a pinned suite, so publishing a tag without pinning its constants
#      is caught. Needs api.soldeer.xyz.
#
# Usage:
#   check-published-deploy-constants.sh [--lib <path>] [--offline]
#                                       [--registry-response <path>]
#
#   --lib <path>  file to inspect (default src/lib/deploy/LibDecimalFloatDeploy.sol)
#   --offline     run the structural half only, and never touch the network.
#                 Lets a test assert the structural half deterministically
#                 instead of depending on whether the registry answered.
#   --registry-response <path>
#                 use the contents of <path> as the registry response instead
#                 of fetching one, so a test can drive the registry half
#                 deterministically. Stands in for a fetch that SUCCEEDED;
#                 there is no stand-in for one that failed, because that path
#                 is what every offline CI run already takes.
#
# Consumed by LibDecimalFloatDeployTaggedConstants.t.sol via FFI. Output is one
# of:
#   OK                     - every half that ran, passed
#   MISSING: <names...>    - one or more expected constants are absent
#   SKIP: <reason>         - default mode only: the structural half passed but
#                            the registry could not be fetched, so that half
#                            did not run
#   UNREADABLE: <reason>   - the registry answered and no version could be read
#                            out of the answer. A failure, not a skip: see the
#                            registry half below for why.
#
# Always exits 0 so the test sees the message rather than an ffi failure.

set -uo pipefail

lib="src/lib/deploy/LibDecimalFloatDeploy.sol"
offline=0
registry_response=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lib)
      lib="${2:-}"
      if [ -z "$lib" ]; then
        printf 'MISSING: --lib requires a path'
        exit 0
      fi
      shift 2
      ;;
    --offline)
      offline=1
      shift
      ;;
    --registry-response)
      registry_response="${2:-}"
      if [ -z "$registry_response" ]; then
        printf 'MISSING: --registry-response requires a path'
        exit 0
      fi
      if [ ! -f "$registry_response" ]; then
        printf 'MISSING: no such registry response file %s' "$registry_response"
        exit 0
      fi
      shift 2
      ;;
    *)
      printf 'MISSING: unknown argument %s' "$1"
      exit 0
      ;;
  esac
done

if [ ! -f "$lib" ]; then
  printf 'MISSING: no such file %s' "$lib"
  exit 0
fi

if [ "$offline" -eq 1 ] && [ -n "$registry_response" ]; then
  printf 'MISSING: --offline and --registry-response are mutually exclusive'
  exit 0
fi

# The deploy constants that must be pinned for every version.
bases="ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS \
LOG_TABLES_DATA_CONTRACT_HASH \
ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS \
DECIMAL_FLOAT_CONTRACT_HASH"

missing=""

# Append every `<base>_<suffix>` absent from the lib to $missing.
check_suffixes() {
  for suffix in $1; do
    for b in $bases; do
      name="${b}_${suffix}"
      grep -qE "constant ${name} =" "$lib" || missing="${missing} ${name}"
    done
  done
}

# 1. Structural half. Collect every version suffix carrying at least one pinned
# constant, then demand the whole suite for each. Requiring `_[0-9]` after the
# base keeps the un-suffixed "current" constants out of the suffix set.
pinned_suffixes=$(
  for b in $bases; do
    grep -oE "constant ${b}_[0-9][0-9_]* =" "$lib" \
      | sed -E "s/^constant ${b}_//; s/ =\$//"
  done | sort -u
)
check_suffixes "$pinned_suffixes"

# 2. Registry half.
#
# Fetching and reading are kept apart on purpose. Collapsing them makes an
# answer nobody can read look exactly like no answer at all, and "no answer" is
# the branch that reports SKIP — so a change in the registry's response shape
# would silently disable this half forever while every run stayed green.
#
# A fetch that fails is a SKIP: the endpoint 404s for a project with no
# published revisions, and a network that is simply down is not a finding.
# `rain-math-float` does have published revisions, so a failed fetch here means
# the registry or the network was unreachable, not that nothing is published.
#
# A fetch that SUCCEEDS and yields no version is UNREADABLE, and that is a
# failure. This endpoint only answers 2xx for a project that exists, and a
# project exists on the registry because it has revisions; so a readable 2xx
# always carries at least one `"version"`. Zero of them means the response no
# longer looks the way this script reads it.
versions=""
registry_answered=0
if [ "$offline" -eq 0 ]; then
  if [ -n "$registry_response" ]; then
    payload=$(cat "$registry_response")
    registry_answered=1
  elif payload=$(
    curl -fsS --connect-timeout 5 --max-time 20 --retry 2 --retry-delay 1 \
      "https://api.soldeer.xyz/api/v1/revision?project_name=rain-math-float" 2>/dev/null
  ); then
    registry_answered=1
  fi

  if [ "$registry_answered" -eq 1 ]; then
    # Tolerant of whitespace around the colon so that a pretty-printed response
    # reads as a response rather than as an unreadable one.
    versions=$(
      printf '%s' "$payload" \
        | grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9][0-9.]*"' \
        | sed -E 's/.*"([0-9][0-9.]*)"$/\1/' \
        | sort -u
    )
  fi

  if [ -n "$versions" ]; then
    check_suffixes "$(printf '%s' "$versions" | tr . _)"
  fi
fi

# An absence outranks an unreachable registry: a MISSING from the structural
# half is a real failure whether or not the registry answered.
if [ -n "$missing" ]; then
  printf 'MISSING:'
  printf '%s' "$missing" | tr ' ' '\n' | grep -v '^$' | sort -u | while IFS= read -r n; do
    printf ' %s' "$n"
  done
elif [ "$offline" -eq 0 ] && [ "$registry_answered" -eq 1 ] && [ -z "$versions" ]; then
  printf 'UNREADABLE: the soldeer registry answered but no version could be read from the response; the registry half did not run'
elif [ "$offline" -eq 0 ] && [ "$registry_answered" -eq 0 ]; then
  printf 'SKIP: could not fetch published soldeer versions; pinned constant suites are structurally complete'
else
  printf 'OK'
fi
