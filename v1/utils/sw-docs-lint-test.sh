#!/usr/bin/env bash
# StepWise: tests for v1/utils/sw-docs-lint.sh.
#
# Usage:  bash v1/utils/sw-docs-lint-test.sh
#
# Copies the real guide and the parts of the repository it points at into a temporary root, injects one
# defect at a time, and checks that the linter fails and names the problem. Every injection goes through
# `mutate`, which ASSERTS that the text it replaces exists, so an injection that changes nothing cannot
# make a test pass for the wrong reason.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }
section() { printf '\n== %s ==\n' "$1"; }

R="$TMP/root"
G="$R/docs/agent-guide"
fresh() {
  rm -rf "$R"; mkdir -p "$R"
  cp -R "$REAL_ROOT/v1" "$R/v1"
  cp -R "$REAL_ROOT/docs" "$R/docs"          # the guide points at other docs too, so copy them all
  rm -rf "$R/v1/tests/__pycache__"
}
lint() { bash "$R/v1/utils/sw-docs-lint.sh" --root="$R" 2>&1; }

# mutate <file> <old> <new>: replace the first occurrence, and FAIL LOUDLY if it is not there.
mutate() {
  python3 - "$1" "$2" "$3" <<'PY' || { echo "TEST BUG: mutation target not found in $1: $2" >&2; exit 99; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert old in s, "not found"
open(p, "w").write(s.replace(old, new, 1))
PY
}
append() { printf '\n%s\n' "$2" >> "$1"; }

expect_fail() { # name substring
  local out rc; out="$(lint)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"$2"* ]]; then ok "$1"
  else bad "$1" "rc=$rc; wanted [$2]; got: $(printf '%s' "$out" | grep FAIL | head -2 | tr '\n' '|')"; fi
}
expect_pass() { # name
  local out rc; out="$(lint)"; rc=$?
  if [[ $rc -eq 0 ]]; then ok "$1"; else bad "$1" "$(printf '%s' "$out" | grep FAIL | head -2 | tr '\n' '|')"; fi
}

section "Baseline"
fresh; expect_pass "the real guide passes every check"
fresh; rm -rf "$G"; out="$(lint)"; rc=$?
[[ $rc -eq 0 && "$out" == *"nothing to check"* ]] && ok "a tree with no guide passes with a note" || bad "no guide passes with a note" "rc=$rc"
bash "$REAL_ROOT/v1/utils/sw-docs-lint.sh" --bogus >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "an unknown argument exits 2" || bad "an unknown argument exits 2"

section "Links"
fresh; append "$G/00-principles.md" "See [nothing](does-not-exist.md)."
expect_fail "a broken relative link is rejected" "link target does not exist"
fresh; append "$G/00-principles.md" "See [readme](README.md#section)."
expect_pass "a link with an anchor to an existing file is accepted"
fresh; append "$G/00-principles.md" "See [web](https://example.com/does/not/exist)."
expect_pass "an external link is not checked"

section "Repository paths"
fresh; append "$G/00-principles.md" 'The file `v1/utils/does-not-exist.sh` matters.'
expect_fail "a path that does not exist is rejected" "names a path that does not exist"
fresh; append "$G/00-principles.md" 'See `docs/agent-guide/nope.md` for more.'
expect_fail "a docs path that does not exist is rejected" "names a path that does not exist"
fresh; append "$G/00-principles.md" 'Placeholders: `v1/feature/<name>.md`, `v1/specs/<feature>/<section>.md`, `v1/tests/test_*.py`, `docs/<feature>/design.md`.'
expect_pass "placeholders and wildcards are checked only to their last real directory"
fresh; append "$G/00-principles.md" 'The prompt is at v1/prompt.md. Also see v1/prompt.md, and (v1/prompt.md).'
expect_pass "a real path followed by punctuation is accepted"
fresh; append "$G/00-principles.md" 'A placeholder under a missing directory: `v1/no-such-dir/<name>.md`.'
expect_fail "a placeholder path under a directory that does not exist is rejected" "names a path that does not exist"

section "Everything is linked from the README"
fresh; printf '# Extra\n' > "$G/09-extra.md"
expect_fail "a guide file not linked from the README is rejected" "09-extra.md is not linked"
fresh; printf '# Extra template\n' > "$G/templates/extra.md"
expect_fail "a template not linked from the README is rejected" "templates/extra.md is not linked"
fresh; printf '#!/usr/bin/env bash\n' > "$G/templates/extra.sh"
expect_fail "a shell template not linked from the README is rejected" "templates/extra.sh is not linked"
fresh; rm "$G/README.md"
expect_fail "a missing README is rejected" "README.md is missing"

section "Step headings and fields"
fresh; mutate "$G/01-preflight.md" "### P0.01 State the objective in one line" "### P0.1 State the objective in one line"
expect_fail "a malformed step heading is rejected" "malformed step heading"
fresh; mutate "$G/01-preflight.md" "- **Verify:** The line names a target" "- **Checked:** The line names a target"
expect_fail "a step missing its Verify field is rejected" "P0.01 is missing its 'Verify' field"
fresh; mutate "$G/01-preflight.md" "- **Needs:** nothing
- **Do:** Write one line" "- **Do:** Write one line"
expect_fail "a step missing its Needs field is rejected" "missing its 'Needs' field"
fresh; mutate "$G/01-preflight.md" "- **Record:** The line, verbatim." "- **Noted:** The line, verbatim."
expect_fail "a step missing its Record field is rejected" "missing its 'Record' field"
fresh; mutate "$G/01-preflight.md" "- **If it fails:** Ask up to three" "- **Otherwise:** Ask up to three"
expect_fail "a step missing its If-it-fails field is rejected" "missing its 'If it fails' field"
fresh; mutate "$G/01-preflight.md" "- **Do:** Write one line" "- **Action:** Write one line"
expect_fail "a step missing its Do field is rejected" "missing its 'Do' field"

section "Risk labels"
fresh; mutate "$G/01-preflight.md" "- **Risk:** read-only" "- **Risk:** harmless"
expect_fail "a Risk that is not a protocol label is rejected" "not a protocol label"
fresh; mutate "$G/01-preflight.md" "- **Risk:** read-only" "- **Risk:** read-only, network"
expect_fail "a combined Risk value is rejected (one label per step)" "not a protocol label"
fresh; mutate "$G/01-preflight.md" "- **Risk:** read-only" "- **Risk:** READ-ONLY"
expect_fail "a Risk in the wrong case is rejected" "not a protocol label"
fresh; python3 - "$G/01-preflight.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
i = s.index("- **Risk:** read-only"); j = s.index("\n", i)
open(p, "w").write(s[:i] + s[j+1:])
PY
expect_fail "a step with no Risk line is rejected" "missing its 'Risk' field"

section "Step IDs and the dependency graph"
fresh; printf '# 09\n\n## P0. Dup\n\n### P0.01 Duplicate of an existing step\n- **Needs:** nothing\n- **Do:** x\n- **Verify:** x\n- **Record:** x\n- **If it fails:** x\n- **Risk:** read-only\n' > "$G/09-dup.md"
mutate "$G/README.md" "| Failures already made once |" "| [dup](09-dup.md) | x | x |
| Failures already made once |"
expect_fail "a step ID defined twice is rejected" "defined more than once"
fresh; mutate "$G/01-preflight.md" "- **Needs:** P0.01
- **Do:** Show the line" "- **Needs:** P9.99
- **Do:** Show the line"
expect_fail "a Needs naming an undefined step is rejected, by the check that names the dependent step" "step P0.02 needs P9.99, which is not defined"
fresh; mutate "$G/01-preflight.md" "- **Needs:** P0.02
- **Do:** Copy" "- **Needs:** P0.04
- **Do:** Copy"
expect_fail "a Needs pointing at a later step is rejected (no cycles)" "strictly earlier"
fresh; mutate "$G/01-preflight.md" "- **Needs:** P0.01
- **Do:** Show the line" "- **Needs:** P0.02
- **Do:** Show the line"
expect_fail "a step that needs itself is rejected" "strictly earlier"
fresh; mutate "$G/01-preflight.md" "- **Needs:** P1.01
- **Do:** Note the base" "- **Needs:** P1.01, P8.08
- **Do:** Note the base"
expect_fail "one bad entry in a multi-step Needs is caught" "strictly earlier"
fresh; append "$G/00-principles.md" "As described in step P7.99."
expect_fail "a step mentioned in prose but not defined is rejected" "mentions step P7.99"
fresh; mutate "$G/07-change-types.md" "P6.05, P6.06, P7" "P6.05, P6.66, P7"
expect_fail "a step mentioned in the change-type matrix but not defined is rejected" "mentions step P6.66"

section "The task-plan template"
fresh; mutate "$G/templates/task-plan.md" "P4.05, " ""
expect_fail "a step missing from the task-plan template is rejected" "does not list step P4.05"
fresh; mutate "$G/templates/task-plan.md" ", P9.03" ""
expect_fail "the last step missing from the template is rejected" "does not list step P9.03"
fresh; rm "$G/templates/task-plan.md"
expect_fail "a missing task-plan template is rejected" "task-plan.md is missing"
fresh; mutate "$G/templates/task-plan.md" "P1.01, " "P1.010, "
expect_fail "a similar-looking ID does not count as listing the step" "does not list step P1.01"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
