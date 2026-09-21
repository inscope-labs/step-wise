#!/usr/bin/env bash
# StepWise: the verification matrix (guide step P7.01, P1.03, P8.06).
#
#   bash verify-all.sh [--dir REPO] [--slow]
#
#   --dir REPO   the repository to verify (default: the git top level of the current directory)
#   --slow       also run the release-script tests, which run every other suite inside a full-gate
#                test and take minutes
#
# It discovers suites, so a new test file is picked up without editing this script:
#   v1/utils/sw-lint.sh                  the structure linter
#   v1/utils/*-test.sh                   shell test suites (the slow release tests only with --slow)
#   v1/tests/test_*.py                   Python test suites
#   v1/tests/sw_acceptance.py --dry-run  validates the acceptance scenarios (no network, no key)
#   v1/utils/sw-docs-lint.sh             the guide linter, if present
#   static checks                        shellcheck and pyflakes, if installed
#
# A suite passes if and only if its EXIT STATUS is 0. The last line of its output is printed so you can
# record counts, but it is never what decides the result. A tool that is not installed is reported as
# UNVERIFIED, not skipped silently. Exit status: 0 if nothing failed, 1 otherwise.
#
# Run it with bash, never sh.

set -u

DIR=""; SLOW=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) [[ $# -ge 2 ]] || { echo "verify-all: --dir needs a value" >&2; exit 2; }; DIR="$2"; shift 2 ;;
    --slow) SLOW=1; shift ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "verify-all: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -z "$DIR" ]] && DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$DIR" && -d "$DIR/v1" ]] || { echo "verify-all: no StepWise repository at '${DIR:-.}' (use --dir)" >&2; exit 2; }
cd "$DIR" || exit 2

FAILED=0; PASSED=0; UNVERIFIED=()
LIMIT=250; (( SLOW == 1 )) && LIMIT=290

run() { # label command...
  local label="$1"; shift
  local out rc last
  out="$(timeout "$LIMIT" "$@" 2>&1)"; rc=$?
  last="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)"
  if (( rc == 0 )); then
    PASSED=$((PASSED + 1)); printf 'PASS  %-34s %s\n' "$label" "${last:0:80}"
  elif (( rc == 124 )); then
    FAILED=$((FAILED + 1)); printf 'FAIL  %-34s timed out after %ss\n' "$label" "$LIMIT"
  else
    FAILED=$((FAILED + 1)); printf 'FAIL  %-34s exit %s: %s\n' "$label" "$rc" "${last:0:80}"
  fi
}

echo "== Verifying $DIR =="
echo "base: $(git log --oneline -n 1 2>/dev/null || echo 'not a git checkout')"
echo "prompt: $(sed -n 2p v1/prompt.md 2>/dev/null)"
echo

[[ -f v1/utils/sw-lint.sh ]] && run "structure linter" bash v1/utils/sw-lint.sh
[[ -f v1/utils/clipcopy.sh ]] && run "clipcopy self-test" bash v1/utils/clipcopy.sh

for f in v1/utils/*-test.sh; do
  [[ -f "$f" ]] || continue
  if [[ "$(basename "$f")" == "sw-release-test.sh" && $SLOW -eq 0 ]]; then
    UNVERIFIED+=("$f was not run (slow; pass --slow)")
    continue
  fi
  run "$(basename "$f")" bash "$f"
done

if command -v python3 >/dev/null 2>&1; then
  for f in v1/tests/test_*.py; do
    [[ -f "$f" ]] || continue
    run "$(basename "$f")" python3 -W error::ResourceWarning "$f"
  done
  [[ -f v1/tests/sw_acceptance.py ]] && run "acceptance scenarios (dry run)" python3 v1/tests/sw_acceptance.py --dry-run
else
  UNVERIFIED+=("python3 not installed: no Python suite could run")
fi

[[ -f v1/utils/sw-docs-lint.sh ]] && run "guide linter" bash v1/utils/sw-docs-lint.sh

if command -v shellcheck >/dev/null 2>&1; then
  run "shellcheck" shellcheck -s bash -S warning v1/utils/*.sh docs/agent-guide/templates/*.sh
else
  UNVERIFIED+=("shellcheck not installed")
fi
if command -v python3 >/dev/null 2>&1 && python3 -m pyflakes --version >/dev/null 2>&1; then
  run "pyflakes" python3 -m pyflakes v1/tests/*.py
else
  UNVERIFIED+=("pyflakes not installed")
fi

if git ls-files 2>/dev/null | grep -q -E '\.pyc$|__pycache__'; then
  FAILED=$((FAILED + 1)); echo "FAIL  tracked bytecode                   compiled files are committed"
else
  PASSED=$((PASSED + 1)); echo "PASS  no tracked bytecode"
fi

echo
echo "passed: $PASSED   failed: $FAILED"
if (( ${#UNVERIFIED[@]} > 0 )); then
  echo "UNVERIFIED (say so in the hand-off):"
  for u in "${UNVERIFIED[@]}"; do echo "  - $u"; done
fi
if (( FAILED == 0 )); then echo "VERIFIED: nothing failed"; exit 0; else echo "NOT VERIFIED: $FAILED failed"; exit 1; fi
