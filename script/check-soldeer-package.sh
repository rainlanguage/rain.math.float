#!/usr/bin/env bash
# Fails when the soldeer package would ship anything other than the tracked
# files under src/, README.md, SPEC.md, LICENSE and LICENSES/, or would miss
# any of them. The dry run is the same zip the publish gate hashes, so a
# package that passes here publishes only on a change to those files.
set -eu
cd "$(dirname "$0")/.."
expected=$(git ls-files -- src README.md SPEC.md LICENSE LICENSES | LC_ALL=C sort)
out=$(forge soldeer push rain-math-float~0.0.0 --dry-run 2>&1) || {
  echo "$out"
  exit 1
}
zip=$(sed -nE 's/.*Zip file created at (.*\.zip).*/\1/p' <<<"$out" | tail -n 1)
[ -n "$zip" ] && [ -f "$zip" ] || {
  echo "$out"
  echo "dry run produced no zip"
  exit 1
}
trap 'rm -f "$zip"' EXIT
actual=$(python3 -c '
import sys, zipfile
for name in zipfile.ZipFile(sys.argv[1]).namelist():
    if not name.endswith("/"):
        print(name)
' "$zip" | LC_ALL=C sort)
diff -u <(echo "$expected") <(echo "$actual") || {
  echo "::error file=.soldeerignore::the package would ship the files on the right, not the tracked files on the left"
  exit 1
}
echo "package ships exactly the $(echo "$expected" | wc -l) tracked files under src/, README.md, SPEC.md, LICENSE and LICENSES/"
