#!/usr/bin/env bash
# StepWise: release gate (plan Phase 7.2).
#
#   bash v1/utils/sw-release.sh --check
#   bash v1/utils/sw-release.sh --apply --version 1.6.0 [--date YYYY-MM-DD]
#
# Options:
#   --skip-suites       do not re-run the test suites (they take about half a minute)
#   --min-models N      models that must have passing acceptance evidence (default 1)
#   --min-samples N     samples per scenario each evidence file must have used (default 3)
#   --evidence DIR      where results files live (default v1/tests/results)
#
# --check reports every unmet condition and exits 1 if any. It changes nothing.
#
# --apply runs the same check first. If the gate is open it rewrites ONLY the mechanical
# version strings (the prompt's Version line, the Framework / Version / Status rows of each
# feature and spec, and the CHANGELOG heading), then verifies the result and rolls back on any
# failure. It does not touch the README, commit, tag, or push. Those need a human. It prints
# what is left to do.
#
# The evidence check ties results to the exact prompt, tiers and scenarios they were run
# against, so results recorded before a later edit do not count. This protects against
# accidents and stale results. It cannot stop someone who hand-edits a results file.

set -u

V1="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$V1/.." && pwd)"
PROMPT="$V1/prompt.md"
CHANGELOG="$ROOT/CHANGELOG.md"
RUNNER="$V1/tests/sw_acceptance.py"

MODE=""; VERSION=""; DATE=""; SKIP=0; MIN_MODELS=1; MIN_SAMPLES=3; EVID="$V1/tests/results"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE=check; shift ;;
    --apply) MODE=apply; shift ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --date) DATE="${2:-}"; shift 2 ;;
    --skip-suites) SKIP=1; shift ;;
    --min-models) MIN_MODELS="${2:-}"; shift 2 ;;
    --min-samples) MIN_SAMPLES="${2:-}"; shift 2 ;;
    --evidence) EVID="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "sw-release: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -z "$MODE" ]] && { echo "sw-release: choose --check or --apply (see --help)" >&2; exit 2; }
[[ "$MIN_MODELS" =~ ^[0-9]+$ && "$MIN_SAMPLES" =~ ^[0-9]+$ ]] || { echo "sw-release: --min-models and --min-samples must be integers" >&2; exit 2; }
if [[ "$MODE" == apply ]]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "sw-release: --apply needs --version X.Y.Z" >&2; exit 2; }
  DATE="${DATE:-$(date -u +%Y-%m-%d)}"
  [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "sw-release: --date must be YYYY-MM-DD" >&2; exit 2; }
fi

BLOCKERS=0
ok()      { printf 'ok       %s\n' "$*"; }
blocked() { printf 'BLOCKED  %s\n' "$*"; BLOCKERS=$((BLOCKERS + 1)); }
note()    { printf 'note     %s\n' "$*"; }

run_gate() {
  local pv re

  # 1. The prompt must be an X.Y.Z-dev prompt, and the target version must match it.
  pv="$(sed -n '2p' "$PROMPT" 2>/dev/null)"
  re='^Version: ([0-9]+\.[0-9]+\.[0-9]+)-dev$'
  TARGET=""
  if [[ "$pv" =~ $re ]]; then
    TARGET="${BASH_REMATCH[1]}"
    ok "prompt is '$pv', so the release would be $TARGET"
    if [[ -n "$VERSION" && "$VERSION" != "$TARGET" ]]; then
      blocked "--version $VERSION does not match the prompt's $TARGET-dev; refusing to guess"
    fi
  else
    blocked "prompt line 2 is '$pv', expected 'Version: X.Y.Z-dev' (nothing to release, or already released)"
  fi

  # 2. Plan 7.2: this release stays in the 1.x series.
  if [[ -d "$ROOT/v2" || -e "$ROOT/stepwise-v2-prompt.md" ]]; then
    blocked "a v2/ directory or stepwise-v2-prompt.md exists; plan 7.2 forbids both for a 1.x release"
  else
    ok "no v2/ directory and no stepwise-v2-prompt.md (plan 7.2)"
  fi

  # 3. CHANGELOG has an Unreleased section and no entry for the target yet.
  if [[ ! -f "$CHANGELOG" ]]; then
    blocked "CHANGELOG.md not found"
  elif ! grep -qE '^## Unreleased' "$CHANGELOG"; then
    blocked "CHANGELOG.md has no '## Unreleased' section to promote"
  elif [[ -n "$TARGET" ]] && grep -qE "^## ${TARGET//./\\.}( |\$)" "$CHANGELOG"; then
    blocked "CHANGELOG.md already has an entry for $TARGET"
  else
    ok "CHANGELOG.md has an Unreleased section to promote"
  fi

  # 4. Release from a committed state.
  if [[ -d "$ROOT/.git" ]]; then
    if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then
      blocked "uncommitted changes in the working tree; commit or stash them, then release from a committed state"
    else
      ok "working tree is clean"
    fi
  else
    note "not a git checkout; skipping the clean-tree check"
  fi

  # 5. The test suites.
  if (( SKIP == 1 )); then
    note "test suites skipped (--skip-suites); run without it before a real release"
  else
    suite "structure linter"        bash "$V1/utils/sw-lint.sh"
    suite "linter tests"            bash "$V1/utils/sw-lint-test.sh"
    suite "shell utility tests"     bash "$V1/utils/clipcopy-test.sh"
    suite "harness and scenario tests" python3 "$V1/tests/test_sw_acceptance.py"
  fi

  # 6. Behavioral acceptance evidence recorded against the CURRENT prompt.
  if ! command -v python3 >/dev/null 2>&1; then
    blocked "python3 not found; it is needed to verify acceptance evidence"
  else
    local out rc
    out="$(python3 "$RUNNER" --verify-evidence "$EVID" --min-models "$MIN_MODELS" --min-samples "$MIN_SAMPLES" 2>&1)"; rc=$?
    if (( rc == 0 )); then
      ok "$(printf '%s' "$out" | grep -E '^Evidence OK')"
      printf '%s\n' "$out" | grep -E '^note:' | sed 's/^/         /'
    else
      printf '%s\n' "$out" | sed -n 's/^BLOCKED: //p' | while IFS= read -r line; do printf 'BLOCKED  evidence: %s\n' "$line"; done
      printf '%s\n' "$out" | grep -E '^note:' | sed 's/^/         /'
      # The while loop above ran in a subshell, so count blockers here.
      BLOCKERS=$((BLOCKERS + $(printf '%s\n' "$out" | grep -c '^BLOCKED: ')))
    fi
  fi
}

suite() { # label command...
  local label="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if (( rc == 0 )); then ok "$label passed"
  else blocked "$label FAILED: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi
}

restore() { # backup dir
  cp "$1/prompt.md" "$PROMPT"
  rm -rf "$V1/feature" "$V1/specs"
  cp -R "$1/feature" "$V1/feature"
  cp -R "$1/specs" "$V1/specs"
  cp "$1/CHANGELOG.md" "$CHANGELOG"
}

apply_edits() {
  local t="${TARGET//./\\.}" f
  sed -i.bak "2s/^Version: ${t}-dev\$/Version: ${TARGET}/" "$PROMPT"
  for f in "$V1"/feature/*.md "$V1"/specs/*/*.md; do
    [[ -f "$f" ]] || continue
    sed -E -i.bak \
      -e "s/^\\| Framework \\| ${t} \\(unreleased\\) \\|\$/| Framework | ${TARGET} |/" \
      -e "s/^\\| Version \\| ${t}-(dev|draft) \\|\$/| Version | ${TARGET} |/" \
      -e "s/^\\| Status \\| Draft\\./| Status | Released./" "$f"
  done
  sed -E -i.bak "s/^## Unreleased [^0-9]*${t} \\(in progress\\)\$/## ${TARGET} — ${DATE}/" "$CHANGELOG"
  awk -v msg="Released after the Phase 6 acceptance scenarios passed. The recorded results are in \`v1/tests/results/\`." \
      '/^\*\*Not a release\.\*\*/ { print msg; next } { print }' "$CHANGELOG" > "$CHANGELOG.new" && mv "$CHANGELOG.new" "$CHANGELOG"
  find "$V1" "$ROOT" -maxdepth 3 -name '*.bak' -delete 2>/dev/null
}

echo "== Release gate =="
run_gate
echo
if (( BLOCKERS > 0 )); then
  echo "RELEASE GATE: BLOCKED ($BLOCKERS)"
  [[ "$MODE" == apply ]] && echo "sw-release: nothing was changed."
  exit 1
fi
echo "RELEASE GATE: OPEN"
[[ "$MODE" == check ]] && exit 0

# --- apply -------------------------------------------------------------------
echo
echo "== Applying $TARGET ($DATE) =="
BK="$(mktemp -d)"
cp "$PROMPT" "$BK/prompt.md"; cp "$CHANGELOG" "$BK/CHANGELOG.md"
cp -R "$V1/feature" "$BK/feature"; cp -R "$V1/specs" "$BK/specs"

fail_and_restore() {
  echo "FAIL     $*"
  restore "$BK"
  echo "sw-release: rolled back; the files are as they were."
  rm -rf "$BK"
  exit 1
}

apply_edits

leftover="$(grep -nE '^(Version: .*-(dev|draft)|\| (Framework|Version) \|.*(-dev|-draft|unreleased))' "$PROMPT" "$V1"/feature/*.md "$V1"/specs/*/*.md 2>/dev/null)"
[[ -n "$leftover" ]] && fail_and_restore "pre-release markers remain: $(printf '%s' "$leftover" | head -3 | tr '\n' ' ')"
grep -qE "^## ${TARGET//./\\.} — ${DATE}\$" "$CHANGELOG" || fail_and_restore "the CHANGELOG heading '## Unreleased … ${TARGET} (in progress)' was not in the expected form; edit it by hand"
[[ "$(sed -n '2p' "$PROMPT")" == "Version: $TARGET" ]] || fail_and_restore "the prompt's Version line was not updated"
bash "$V1/utils/sw-lint.sh" >/dev/null 2>&1 || fail_and_restore "the structure linter fails after the edit"
python3 "$RUNNER" --verify-evidence "$EVID" --min-models "$MIN_MODELS" --min-samples "$MIN_SAMPLES" >/dev/null 2>&1 \
  || fail_and_restore "acceptance evidence no longer verifies after the edit"
rm -rf "$BK"

ok "prompt is now 'Version: $TARGET'; feature and spec headers updated; CHANGELOG heading is '## $TARGET — $DATE'"
ok "structure linter passes and the acceptance evidence still verifies"
cat <<EOF

Not done by this script. These need a person:
  1. README.md: update the Status line and the "In progress" paragraph, and rename the
     "(1.6.0-dev)" and "(1.6.0 preview)" headings (and the anchors that link to them).
  2. Review the diff (git diff), then commit.
  3. Tag it (git tag v$TARGET) and push. This script never commits, tags, or pushes.
EOF
