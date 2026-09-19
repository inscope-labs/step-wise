#!/usr/bin/env bash
# StepWise — tests for v1/utils/sw-lint.sh.
#
# Usage:  bash v1/utils/sw-lint-test.sh
#
# Copies the real v1/ tree into a temporary directory, injects one defect at a
# time, and checks that the linter fails and names the problem. A linter that
# cannot fail is worthless, so this proves each rule can actually fire.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_V1="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }

fresh() { rm -rf "$TMP/v1"; cp -R "$REAL_V1" "$TMP/v1"; }
lint()  { bash "$TMP/v1/utils/sw-lint.sh" --v1="$TMP/v1" 2>&1; }

# expect_fail <name> <substring the failure output must contain>
expect_fail() {
  local out rc
  out="$(lint)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"$2"* ]]; then ok "$1"
  else bad "$1" "rc=$rc; wanted output containing [$2]; got: $(printf '%s' "$out" | grep -E 'FAIL' | head -3 | tr '\n' '|')"; fi
}

echo "== Baseline =="
fresh
out="$(lint)"; rc=$?
[[ $rc -eq 0 ]] && ok "real tree passes all checks" || bad "real tree passes all checks" "$(printf '%s' "$out" | grep FAIL | head -3)"
bash "$REAL_V1/utils/sw-lint.sh" --report 2>&1 | grep -q "normal session (prompt only)" && ok "--report prints the size table" || bad "--report prints the size table"
bash "$REAL_V1/utils/sw-lint.sh" --bogus >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "unknown argument exits 2" || bad "unknown argument exits 2"

echo; echo "== Sizes and limits =="
fresh; python3 -c "open('$TMP/v1/prompt.md','a').write('x'*6000)"
expect_fail "oversize prompt is rejected" "prompt is"
fresh; python3 -c "open('$TMP/v1/feature/logging.md','a').write('x'*8000)"
expect_fail "oversize feature is rejected" "feature logging.md is"
fresh; python3 -c "open('$TMP/v1/specs/context/loading-rules.md','a').write('x'*10000)"
expect_fail "oversize spec section is rejected" "spec context/loading-rules.md is"
fresh; sed -i 's/^limit: max_optional_bytes = .*/limit: max_optional_bytes = 100/' "$TMP/v1/specs/context/size-limits.md"
expect_fail "worst-case optional context over the limit is rejected" "worst-case optional context"
fresh; sed -i '/^limit: prompt_bytes/d' "$TMP/v1/specs/context/size-limits.md"
expect_fail "missing limit line is rejected" "missing 'limit: prompt_bytes"

echo; echo "== Versions and headers =="
fresh; sed -i '2s/.*/Version: one.six/' "$TMP/v1/prompt.md"
expect_fail "malformed prompt Version line is rejected" "not a valid 'Version"
fresh; sed -i 's/^| Framework | 1.6.0 (unreleased) |/| Framework | 1.5.0 |/' "$TMP/v1/feature/logging.md"
expect_fail "feature with incompatible Framework version must not load" "incompatible with the prompt"
fresh; sed -i '/^| Status |/d' "$TMP/v1/feature/context.md"
expect_fail "feature missing a required header row is rejected" "header row 'Status' is missing"

echo; echo "== Index and reachability =="
fresh; sed -i 's/^| `feature:logging` |/| `feature:ghost` | nothing |\n| `feature:logging` |/' "$TMP/v1/prompt.md"
expect_fail "index entry with no file is rejected" "feature:ghost"
fresh; sed 's/`logging`/`newthing`/' "$TMP/v1/feature/logging.md" > "$TMP/v1/feature/newthing.md"
expect_fail "feature file missing from the prompt index is rejected" "not in the prompt's feature index"
fresh; printf '\nSee `spec:clipboard/nope` for more.\n' >> "$TMP/v1/feature/clipboard.md"
expect_fail "feature referencing a nonexistent spec is rejected" "spec:clipboard/nope"
fresh; sed 's/`clipboard\/extraction`/`clipboard\/orphan`/' "$TMP/v1/specs/clipboard/extraction.md" > "$TMP/v1/specs/clipboard/orphan.md"
expect_fail "spec no feature references (unreachable) is rejected" "not referenced by any feature"

echo; echo "== Hierarchy (Prompt -> Feature -> Spec, one way) =="
fresh; printf '\nAlso see `spec:clipboard/extraction`.\n' >> "$TMP/v1/prompt.md"
expect_fail "prompt pointing straight at a spec is rejected" "Prompt -> Spec"
fresh; printf '\nSee `feature:logging` too.\n' >> "$TMP/v1/feature/clipboard.md"
expect_fail "feature pointing sideways at another feature is rejected" "points sideways"
fresh; printf '\nThis follows the rules in prompt.md.\n' >> "$TMP/v1/specs/clipboard/extraction.md"
expect_fail "spec pointing back at the prompt is rejected" "Spec -> Prompt"
fresh; printf '\nSee `feature:execution`.\n' >> "$TMP/v1/specs/clipboard/extraction.md"
expect_fail "spec with a feature address outside its Parent row is rejected" "outside its 'Parent feature' row"

echo; echo "== Regression guard for 1.5.0 rules =="
fresh; python3 - <<PY
p='$TMP/v1/prompt.md'; s=open(p).read()
assert 'Never conceal errors.' in s
open(p,'w').write(s.replace('Never conceal errors.',''))
PY
expect_fail "deleting a required 1.5.0 rule is rejected" "Never conceal errors."
fresh; python3 - <<PY
p='$TMP/v1/prompt.md'; s=open(p).read()
old='never has its output copied to the clipboard, in manual or automatic mode, regardless of operator request'
assert old in s
open(p,'w').write(s.replace(old,'may have its output copied'))
PY
expect_fail "weakening the sensitive-output clipboard rule is rejected" "never has its output copied to the clipboard"

echo; echo "== Prompt/script risk-label drift =="
fresh; sed -i 's#^Risk: <read-only / #Risk: <read-only / brand-new-risk / #' "$TMP/v1/prompt.md"
expect_fail "a prompt risk label clipcopy.sh does not know is rejected" "brand-new-risk"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
