#!/usr/bin/env bash
# PL World lane compile check (the repo's local history is not safe to push; this sends only your lane's commits through a clean clone).
# usage: bash scripts/plw-compile.sh <lane-branch> <base-sha>   (base-sha = the sha your branch started from, in LANES-plworld.md)
# Prints the CI run url; read the result with: gh run view <id> -R maurricemccann/pl-dev-ios --log-failed
set -euo pipefail
lane="$1"; base="$2"; here="$(pwd)"; id_mail="$(git config user.email)"; id_name="$(git config user.name)"; [ -n "$id_mail" ] && [ -n "$id_name" ] || { echo "no git identity in this repo"; exit 1; }
tmp="$(mktemp -d)"; git clone -q https://github.com/maurricemccann/pl-dev-ios.git "$tmp/c"
git format-patch "$base..$lane" --stdout > "$tmp/p.patch"
cd "$tmp/c"; git checkout -q -B "plw-ci-$lane" origin/plworld-ci
git config user.email "$id_mail"; git config user.name "$id_name"
git am "$tmp/p.patch"
bash scripts/scan.sh | tail -2 | grep -q "SCAN CLEAN" || { echo "scan failed, not pushing"; bash scripts/scan.sh | tail -5; exit 1; }
git push -q -f origin "plw-ci-$lane"
gh workflow run build.yml --ref "plw-ci-$lane" -f publish=false
sleep 8; gh run list --workflow build.yml --branch "plw-ci-$lane" --limit 1
