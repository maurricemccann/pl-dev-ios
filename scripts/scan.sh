#!/usr/bin/env bash
# Hygiene scan for a public repo: fails if anything private could be in the working tree or the history.
# Usage: bash scripts/scan.sh
# Allowed on purpose: the bundled fonts and the generated placeholder icons.
# Font licence files are skipped by the email check only: a licence may print its author's public contact.
# A real config file (pldev-config*.json, *.pldev) is ignored by git, so it is never read here and must never be tracked.
set -u
fail=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SCAN FAILED: this is not a git repository, so nothing could be checked."; exit 1; }
check() { # label, pattern, then any extra paths to leave out
  local label="$1" pattern="$2"
  shift 2
  local hits hist
  hits=$(git grep -n -I --untracked -E "$pattern" -- . ':!scripts/scan.sh' "$@" 2>/dev/null | { [ -n "${ALLOW:-}" ] && grep -v -E "$ALLOW" || cat; })
  hist=$(git log --all -p --no-color -- . ':!scripts/scan.sh' "$@" 2>/dev/null | grep -n -E "^\+.*($pattern)" | { [ -n "${ALLOW:-}" ] && grep -v -E "$ALLOW" || cat; } | head -3)
  if [ -n "$hits" ] || [ -n "$hist" ]; then
    echo "FAIL: $label"; [ -n "$hits" ] && echo "$hits" | cut -c1-200 | head -5; [ -n "$hist" ] && echo "(history) $hist" | cut -c1-200; fail=1
  fi
}
# placeholders are not addresses: example.com (reserved for examples) and the your@email.com hint in a field (11-13)
ALLOW='@example\.(com|org|net)|your@email\.com' check "email address"            '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' ':!*OFL.txt' ':!*LICENSE*'
check "tailnet hostname"         '\.ts\.net'
check "tailscale address"        '(^|[^0-9])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+'
check "long hex (key or token)"  '[0-9a-fA-F]{32,}'
check "token-looking string"     '(ghp_|github_pat_|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}|xox[abp]-|AKIA[0-9A-Z]{12})'
check "Apple ID wording"         '[Aa]pple ?ID'
check "claude session link"      'claude\.ai/code/session_[A-Za-z0-9]{8,}'   # a real link has its id; naming the pattern is not a leak
# his hand font's own file and face names and the repo owner's GitHub handle are public by design (the font is his published asset)
ALLOW='MaurriceMccannPsychedHandw|maurricemccann' check "personal detail"          '([Gg]irlfriend|[Bb]oyfriend|[Ww]ife|[Hh]usband|[Mm]aurrice|psychedleo|[Hh]esperia)'
# a real config file holds keys and addresses: it must never be tracked, now or in the past
tracked=$( { git ls-files -- 'pldev-config*.json' '*.pldev' ':(glob)**/pldev-config*.json'; git log --all --format= --name-only -- 'pldev-config*.json' '*.pldev' ':(glob)**/pldev-config*.json'; } 2>/dev/null | sort -u | grep -v '^$')
if [ -n "$tracked" ]; then echo "FAIL: a config file is tracked or was committed:"; echo "$tracked"; fail=1; fi
# commit identity must be the noreply address only
bad=$(git log --all --format='%ae %ce' 2>/dev/null | tr ' ' '\n' | sort -u | grep -v -E '@users\.noreply\.github\.com$' | grep -v '^$')
if [ -n "$bad" ]; then echo "FAIL: non-noreply commit email in history:"; echo "$bad"; fail=1; fi
if [ "$fail" = 0 ]; then echo "SCAN CLEAN: nothing private found in the tree or the history."; else echo "SCAN FAILED"; fi
exit $fail
