#!/usr/bin/env bash
# StepWise: tests for v1/utils/sw-release.sh.
#
# Usage:  bash v1/utils/sw-release-test.sh
#
# Works on throwaway copies of the repository, so nothing real is modified. The release
# gate decides whether a release may happen, so these tests are strict about the two
# dangerous behaviors: --apply must change NOTHING when the gate is closed, and must roll
# back completely if its own verification fails.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }
section() { printf '\n== %s ==\n' "$1"; }

R=""   # the current throwaway repo
fresh() {
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo"
  cp "$REAL_ROOT/README.md" "$REAL_ROOT/CHANGELOG.md" "$TMP/repo/"
  cp -R "$REAL_ROOT/v1" "$TMP/repo/v1"
  rm -rf "$TMP/repo/v1/tests/__pycache__" "$TMP/repo/v1/tests/results"
  R="$TMP/repo"
}
release() { bash "$R/v1/utils/sw-release.sh" "$@" 2>&1; }

# ev <file-name> [python-dict-update]: write an evidence file for the CURRENT tree in $R.
ev() {
  mkdir -p "$R/v1/tests/results"
  python3 - "$R" "$1" "${2:-{\}}" <<'PY'
import json, subprocess, sys
root, name, over = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
h = json.loads(subprocess.check_output(["python3", root + "/v1/tests/sw_acceptance.py", "--hash"]))
d = {"model": name, "samples": 3, "threshold": 0.67, "complete": True, "run_at": "2026-09-19T00:00:00Z",
     "prompt_version": "Version: 1.6.0-dev", **{k: h[k] for k in ("prompt_sha256", "tiers_sha256", "scenarios_sha256", "scenario_ids")},
     "results": [{"id": i, "status": "PASS", "failures": [], "covers": []} for i in h["scenario_ids"]]}
d.update(over)
json.dump(d, open(root + "/v1/tests/results/" + name + ".json", "w"))
PY
}

tree_sum() { (cd "$R" && find README.md CHANGELOG.md v1 -type f ! -path '*/__pycache__/*' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1); }

expect() { # expect <name> <exit-code> <substring> -- args...
  local name="$1" want="$2" needle="$3"; shift 4
  local out rc
  out="$(release "$@")"; rc=$?
  if [[ $rc -eq $want && "$out" == *"$needle"* ]]; then ok "$name"
  else bad "$name" "rc=$rc (wanted $want); wanted [$needle]; got: $(printf '%s' "$out" | grep -E 'BLOCKED|FAIL' | head -3 | tr '\n' '|')"; fi
}

section "The gate (--check)"
fresh
expect "no evidence: blocked" 1 "no acceptance evidence" -- --check --skip-suites
fresh; ev model-a
expect "good evidence: gate opens" 0 "RELEASE GATE: OPEN" -- --check --skip-suites
fresh; ev model-a; before="$(tree_sum)"; release --check --skip-suites >/dev/null; [[ "$(tree_sum)" == "$before" ]] && ok "--check changes nothing" || bad "--check changes nothing"

fresh; ev model-a '{"results": [{"id": "gate-vague-task", "status": "FAIL", "failures": [], "covers": []}]}'
expect "failing or missing scenarios: blocked" 1 "evidence:" -- --check --skip-suites
fresh; ev model-a '{"complete": false}'
expect "partial (--filter) run: blocked" 1 "partial run" -- --check --skip-suites
fresh; ev model-a '{"samples": 1}'
expect "too few samples: blocked" 1 "need at least 3" -- --check --skip-suites
fresh; ev model-a '{"threshold": 0.1}'
expect "lowered threshold: blocked" 1 "below the required" -- --check --skip-suites
fresh; ev model-a; printf '\nA rule added after the evidence was recorded.\n' >> "$R/v1/prompt.md"
expect "stale evidence (prompt edited after): blocked" 1 "stale" -- --check --skip-suites
fresh; ev model-a; printf '\nMore.\n' >> "$R/v1/feature/logging.md"
expect "stale evidence (a feature edited after): blocked" 1 "stale" -- --check --skip-suites
fresh; ev model-a; sed -i 's/fix my server/fix my laptop/' "$R/v1/tests/scenarios/gate-vague-task.json"
expect "stale evidence (a scenario edited after): blocked" 1 "stale" -- --check --skip-suites
fresh; ev model-a
expect "one model but --min-models 2: blocked" 1 "need at least 2" -- --check --skip-suites --min-models 2
fresh; ev model-a; ev model-b
expect "two models with --min-models 2: opens" 0 "RELEASE GATE: OPEN" -- --check --skip-suites --min-models 2
fresh; ev model-a; ev model-b '{"results": []}'
expect "a failing current result blocks even when another model passed" 1 "model-b" -- --check --skip-suites
fresh; mkdir -p "$R/v1/tests/results"; echo '{not json' > "$R/v1/tests/results/junk.json"
expect "a corrupt evidence file is reported, not a crash" 1 "unreadable" -- --check --skip-suites
fresh; ev model-a
expect "a custom --evidence directory is honored" 1 "no acceptance evidence" -- --check --skip-suites --evidence "$TMP/nowhere"

section "Other conditions"
fresh; ev model-a; sed -i '2s/.*/Version: 1.6.0/' "$R/v1/prompt.md"
expect "prompt already released (no -dev): blocked" 1 "expected 'Version: X.Y.Z-dev'" -- --check --skip-suites
fresh; ev model-a; mkdir "$R/v2"
expect "a v2/ directory: blocked (plan 7.2)" 1 "plan 7.2 forbids" -- --check --skip-suites
fresh; ev model-a; : > "$R/stepwise-v2-prompt.md"
expect "stepwise-v2-prompt.md: blocked (plan 7.2)" 1 "plan 7.2 forbids" -- --check --skip-suites
fresh; ev model-a; sed -i 's/^## Unreleased.*/## Something else/' "$R/CHANGELOG.md"
expect "no Unreleased section: blocked" 1 "no '## Unreleased' section" -- --check --skip-suites
fresh; ev model-a; sed -i 's/^## Unreleased.*/## 1.6.0 — 2026-01-01/' "$R/CHANGELOG.md"; printf '\n## Unreleased\n' >> "$R/CHANGELOG.md"
expect "CHANGELOG already has the target entry: blocked" 1 "already has an entry for 1.6.0" -- --check --skip-suites
fresh; ev model-a
expect "--version that does not match the prompt: blocked" 1 "does not match" -- --check --skip-suites --version 1.7.0

fresh; ev model-a
( cd "$R" && git init -q && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -q -m init )
expect "clean git tree: opens" 0 "working tree is clean" -- --check --skip-suites
echo "stray" >> "$R/README.md"
expect "dirty git tree: blocked" 1 "uncommitted changes" -- --check --skip-suites
( cd "$R" && git checkout -q README.md && : > untracked.txt )
expect "untracked file: blocked" 1 "uncommitted changes" -- --check --skip-suites

section "Usage errors"
fresh
expect "no mode: usage error" 2 "choose --check or --apply" -- --skip-suites
expect "unknown option: usage error" 2 "unknown argument" -- --bogus
expect "--apply without --version: usage error" 2 "needs --version" -- --apply
expect "--apply with a bad date: usage error" 2 "YYYY-MM-DD" -- --apply --version 1.6.0 --date tomorrow
expect "non-integer --min-models: usage error" 2 "must be integers" -- --check --min-models x

section "--apply refuses when the gate is closed"
fresh; before="$(tree_sum)"
out="$(release --apply --version 1.6.0 --skip-suites)"; rc=$?
[[ $rc -eq 1 && "$out" == *"nothing was changed"* ]] && ok "no evidence: refuses and says so" || bad "no evidence: refuses and says so" "rc=$rc"
[[ "$(tree_sum)" == "$before" ]] && ok "no evidence: every file is byte-identical afterward" || bad "no evidence: every file is byte-identical afterward"
fresh; ev model-a '{"samples": 1}'; before="$(tree_sum)"
release --apply --version 1.6.0 --skip-suites >/dev/null
[[ "$(tree_sum)" == "$before" ]] && ok "weak evidence: nothing changed" || bad "weak evidence: nothing changed"
fresh; ev model-a; before="$(tree_sum)"
release --apply --version 1.7.0 --skip-suites >/dev/null
[[ "$(tree_sum)" == "$before" ]] && ok "wrong --version: nothing changed" || bad "wrong --version: nothing changed"

section "--apply when the gate is open"
fresh; ev model-a; readme_before="$(sha256sum "$R/README.md" | cut -d' ' -f1)"
out="$(release --apply --version 1.6.0 --date 2026-09-30 --skip-suites)"; rc=$?
[[ $rc -eq 0 ]] && ok "succeeds (exit 0)" || bad "succeeds (exit 0)" "$(printf '%s' "$out" | tail -4)"
[[ "$(sed -n 2p "$R/v1/prompt.md")" == "Version: 1.6.0" ]] && ok "prompt Version line is 1.6.0" || bad "prompt Version line is 1.6.0"
grep -qE '^## 1\.6\.0 — 2026-09-30$' "$R/CHANGELOG.md" && ok "CHANGELOG heading is '## 1.6.0 — 2026-09-30'" || bad "CHANGELOG heading"
grep -q 'Not a release' "$R/CHANGELOG.md" && bad "the 'Not a release' paragraph is gone" || ok "the 'Not a release' paragraph is gone"
grep -q 'Released after the Phase 6' "$R/CHANGELOG.md" && ok "CHANGELOG points at the recorded results" || bad "CHANGELOG points at the recorded results"
left="$(grep -rnE '^(Version: .*-(dev|draft)|\| (Framework|Version) \|.*(-dev|-draft|unreleased))' "$R/v1/prompt.md" "$R/v1/feature" "$R/v1/specs")"
[[ -z "$left" ]] && ok "no -dev, -draft or (unreleased) marker left in the prompt or tier headers" || bad "markers left" "$left"
n="$(grep -rlE '^\| Version \| 1\.6\.0 \|$' "$R/v1/feature" "$R/v1/specs" | wc -l | tr -d ' ')"
[[ "$n" -eq "$(ls "$R"/v1/feature/*.md "$R"/v1/specs/*/*.md | wc -l | tr -d ' ')" ]] && ok "every feature and spec header now says Version 1.6.0" || bad "every header updated" "$n updated"
grep -rq '^| Status | Released\.' "$R/v1/feature/clipboard.md" && ok "Status rows say Released" || bad "Status rows say Released"
bash "$R/v1/utils/sw-lint.sh" >/dev/null 2>&1 && ok "the structure linter still passes" || bad "the structure linter still passes"
python3 "$R/v1/tests/sw_acceptance.py" --verify-evidence "$R/v1/tests/results" >/dev/null 2>&1 && ok "the evidence still verifies (a version bump does not invalidate it)" || bad "the evidence still verifies"
[[ "$(sha256sum "$R/README.md" | cut -d' ' -f1)" == "$readme_before" ]] && ok "README.md is untouched" || bad "README.md is untouched"
[[ "$out" == *"README.md: update the Status line"* ]] && ok "prints what is left for a human" || bad "prints what is left for a human"
find "$R" -name '*.bak' | grep -q . && bad "no .bak files left behind" || ok "no .bak files left behind"
out2="$(release --apply --version 1.6.0 --skip-suites)"; rc=$?
[[ $rc -eq 1 && "$out2" == *"expected 'Version: X.Y.Z-dev'"* ]] && ok "applying twice is refused" || bad "applying twice is refused" "rc=$rc"

section "--apply rolls back if its own verification fails"
fresh; ev model-a; sed -i 's/^## Unreleased.*/## Unreleased/' "$R/CHANGELOG.md"; before="$(tree_sum)"
out="$(release --apply --version 1.6.0 --skip-suites)"; rc=$?
[[ $rc -eq 1 && "$out" == *"rolled back"* ]] && ok "an unrecognized CHANGELOG heading fails and reports the rollback" || bad "reports the rollback" "rc=$rc; $(printf '%s' "$out" | tail -3 | tr '\n' '|')"
[[ "$(tree_sum)" == "$before" ]] && ok "rollback restores every file byte-for-byte" || bad "rollback restores every file byte-for-byte"

fresh; ev model-a; sed -i 's/^| Version | 1.6.0-dev |$/| Version | 1.6.0-dev  |/' "$R/v1/feature/logging.md"; before="$(tree_sum)"
out="$(release --apply --version 1.6.0 --skip-suites)"; rc=$?
[[ $rc -eq 1 && "$out" == *"pre-release markers remain"* && "$out" == *"rolled back"* ]] && ok "a header the script cannot rewrite is detected and rolled back" || bad "unrewritable header is detected" "rc=$rc; $(printf '%s' "$out" | tail -3 | tr '\n' '|')"
[[ "$(tree_sum)" == "$before" ]] && ok "that rollback is also byte-for-byte" || bad "that rollback is also byte-for-byte"

# The post-apply evidence check is a safety net: a version bump never changes hashed text, so it cannot
# fire in normal use. Simulate a future bug in apply_edits that touches hashed text, and confirm the net holds.
fresh; ev model-a; before="$(tree_sum)"
sed -i '/^apply_edits$/s/$/; printf "\\nTAMPER\\n" >> "$PROMPT"/' "$R/v1/utils/sw-release.sh"
before="$(tree_sum)"
out="$(release --apply --version 1.6.0 --skip-suites)"; rc=$?
[[ $rc -eq 1 && "$out" == *"acceptance evidence no longer verifies"* && "$out" == *"rolled back"* ]] && ok "an apply that alters hashed text is caught by the post-apply evidence check" || bad "post-apply evidence check" "rc=$rc; $(printf '%s' "$out" | tail -3 | tr '\n' '|')"
[[ "$(tree_sum)" == "$before" ]] && ok "and that rollback is byte-for-byte too" || bad "that rollback is byte-for-byte"

section "Full gate with the real suites (slow)"
fresh; ev model-a
out="$(release --check)"; rc=$?
[[ $rc -eq 0 && "$out" == *"structure linter passed"* && "$out" == *"harness and scenario tests passed"* ]] && ok "runs the linter, linter tests, utility tests and harness tests, and opens" \
  || bad "full check on a good tree" "rc=$rc; $(printf '%s' "$out" | grep -E 'BLOCKED' | head -3 | tr '\n' '|')"
fresh; ev model-a; printf '\nBroken.\n' >> "$R/v1/prompt.md"; ev model-a   # re-record so evidence is fresh, but the prompt now breaks a rule the linter checks
python3 - "$R" <<'PY'
import sys,re
p=sys.argv[1]+'/v1/prompt.md'; s=open(p).read()
open(p,'w').write(s.replace('Never conceal errors.',''))
PY
ev model-a
out="$(release --check)"; rc=$?
[[ $rc -eq 1 && "$out" == *"structure linter FAILED"* ]] && ok "a linter failure blocks the release even with fresh evidence" || bad "a linter failure blocks the release" "rc=$rc"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
