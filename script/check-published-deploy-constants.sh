#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
#
# Prints "OK" iff every version published to the soldeer registry for
# `rain-math-float` has a full suite of pinned deploy constants in
# LibDecimalFloatDeploy.sol: a log-tables address + codehash and a DecimalFloat
# address + codehash, each suffixed with the version.
#
# Consumed by LibDecimalFloatDeployTaggedConstants.t.sol via FFI. Output is one
# of:
#   OK                   - every published version has its full constant suite
#   MISSING: <names...>  - one or more expected constants are absent
#   SKIP: <reason>       - the registry could not be reached (nothing verified)
#
# Always exits 0 so the test sees the message rather than an ffi failure.

lib="src/lib/deploy/LibDecimalFloatDeploy.sol"

versions=$(
  curl -fsS --connect-timeout 5 --max-time 20 --retry 2 --retry-delay 1 \
    "https://api.soldeer.xyz/api/v1/revision?project_name=rain-math-float" 2>/dev/null \
    | grep -oE '"version":"[0-9][0-9.]*"' | cut -d'"' -f4 | sort -u
)

if [ -z "$versions" ]; then
  printf 'SKIP: could not fetch published soldeer versions'
  exit 0
fi

# The deploy constants that must be pinned for every published version, suffixed
# with the version (dots replaced by underscores).
bases="ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS \
LOG_TABLES_DATA_CONTRACT_HASH \
ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS \
DECIMAL_FLOAT_CONTRACT_HASH"

missing=""
for v in $versions; do
  suffix=$(printf '%s' "$v" | tr . _)
  for b in $bases; do
    name="${b}_${suffix}"
    grep -qE "constant ${name} =" "$lib" || missing="${missing} ${name}"
  done
done

if [ -n "$missing" ]; then
  printf 'MISSING:%s' "$missing"
else
  printf 'OK'
fi
