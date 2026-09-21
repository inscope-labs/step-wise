# 04. Implementation, tests, and enforcement

Phases P5 and P6. Skip P5 if the feature is documentation only. P6 always applies to any rule that protects safety.

## P5. Implementation

### P5.01 Decide whether code is needed, and which language
- **Needs:** P4.11
- **Do:** Write code only if a document cannot do the job. The core protocol stays bash-only and dependency-free. A capability that needs more (a parser, a merge) may use another language **only** as an opt-in feature, with the dependency stated in its feature file and README, and with tests that skip cleanly when the tool is absent.
- **Verify:** You can state why a document is not enough, and what the dependency is.
- **Record:** The decision, for P3.09.
- **If it fails:** If it is a dependency the operator did not expect, ask.
- **Risk:** read-only

### P5.02 Reuse the existing mechanisms
- **Needs:** P5.01
- **Do:** Do not reimplement, in a second place, what already exists: the fail-closed risk classifier (`_sw_risk_class` in `v1/utils/clipcopy.sh`), the untrusted-text quoting rule, the ledger's append-only, locked, private-permission pattern, and the session-state command pattern. If you truly must reimplement a safety gate in another language, plan the parity check in P6.03 now.
- **Verify:** Each mechanism you touch is either reused or has a parity check planned.
- **Record:** The list.
- **If it fails:** Two implementations of one gate drift. That is how a fail-open bug arose once.
- **Risk:** read-only

### P5.03 Write the implementation defensively
- **Needs:** P5.02
- **Do:** Private files (`0700` directories, `0600` files). Fail closed: an unknown value is refused, not allowed. Refusals **name the rule and never echo the offending text**. Nothing read from outside is ever executed. Control characters are stripped from anything printed. Take time and randomness from an injectable source so tests can control them.
- **Verify:** You can point to the line that enforces each of those.
- **Record:** The list.
- **If it fails:** Fix it now. A property you cannot point to has not been implemented.
- **Risk:** creates

### P5.04 Smoke-test it by hand before writing tests
- **Needs:** P5.03
- **Do:** Run it as a user would, with real commands and realistic data, including at least one refusal. Read the output as the person who will see it.
- **Verify:** The behavior is what the feature file promises. Look specifically for results that are *plausible but wrong*.
- **Record:** Anything surprising.
- **If it fails:** This step has found real design flaws (a recall that silently dropped relevant items). Fix the design, then the code.
- **Risk:** creates

### P5.05 Write hermetic tests
- **Needs:** P5.04
- **Do:** Name files `test_<name>.py` under `v1/tests/` or `<name>-test.sh` under `v1/utils/`. Use temporary directories, a controllable clock, and stub backends. Never touch the real home directory or the real clipboard. Exit non-zero on failure. Never assume the repository is in its current state: build your own fixture (tests that copy the live tree break the moment a release lands).
- **Verify:** The suite passes twice in a row, from a directory other than the repository root.
- **Record:** The test counts.
- **If it fails:** Order dependence or a hidden dependency on the environment. Remove it.
- **Risk:** creates

### P5.06 Assemble fake secrets at run time
- **Needs:** P5.05
- **Do:** A test that needs something shaped like a token must build it from parts (`"AK" + "IA" + "..."`) so no literal secret-shaped string exists in any file. Never use a real credential.
- **Verify:** `git grep` for the token shapes you test finds nothing in the tree.
- **Record:** Nothing further.
- **If it fails:** A pushed literal can trip secret scanning and block the push.
- **Risk:** creates

### P5.07 Test the merge, ordering, and consistency properties
- **Needs:** P5.05
- **Do:** If the feature has state that can diverge, test the properties, not only examples: convergence regardless of order, idempotence, and behavior under skewed clocks. Use seeded randomized histories and assert the invariant at the end.
- **Verify:** The randomized test runs many seeds and every seed satisfies the invariant.
- **Record:** The seed count.
- **If it fails:** Print the failing seed so it can be reproduced.
- **Risk:** creates

### P5.08 Test hostile and malformed input
- **Needs:** P5.05
- **Do:** For every input that comes from outside the process, include a test with malformed, truncated, oversized, duplicated, and hostile forms. A record cut before its final newline is a good case. So is one that is valid JSON but unfinished.
- **Verify:** The feature drops or refuses each, reports it, and never crashes.
- **Record:** The cases.
- **If it fails:** Handle the case. Do not "fix" the test.
- **Risk:** creates

## P6. Enforcement

### P6.01 Test the tests with injected bugs
- **Needs:** P5.05
- **Do:** For each safety property, list at least three ways to break it (remove the gate, invert the check, echo a secret, skip validation). Apply each to a **copy** of the tree with a script that (1) asserts the target text exists in the file, (2) checks the mutated file still parses, then (3) runs the suite and records which named test failed.
  ```bash
  python3 - "$file" "$old" "$new" <<'PY'
  import sys; p, old, new = sys.argv[1:4]; s = open(p).read()
  assert old in s, "mutation target not found"      # otherwise you tested nothing
  open(p, "w").write(s.replace(old, new, 1))
  PY
  ```
- **Verify:** Every mutation is caught by at least one named test.
- **Record:** The count of mutations, and which were missed at first.
- **If it fails:** First decide whether the mutation was **invalid** (target not found, does not parse: fix the mutation) or a **real gap** (add a test, then re-run that mutation). Never count an invalid mutation as caught or as missed.
- **Risk:** read-only

### P6.02 Distrust a suite that passed on its first run
- **Needs:** P6.01
- **Do:** For tests that inject a defect with `sed` or a replace, confirm the injection changed the file. A replacement that matches nothing injects nothing, and the test then passes for the wrong reason. The cheapest proof is to disable the check under test and see the test fail.
- **Verify:** Each injected-defect test fails when its check is disabled.
- **Record:** Any test that did not.
- **If it fails:** Fix the pattern until it matches.
- **Risk:** read-only

### P6.03 Add a parity check wherever a safety gate exists twice
- **Needs:** P5.02
- **Do:** Compare the two implementations **in both directions**: every value one accepts must be classified the same by the other, including the edge cases (empty, trailing comma, mixed case). Probe the *other* side's lists too, so a value one side dropped is still tested. Build the probe list without letting command substitution strip a trailing empty entry.
- **Verify:** Adding a value to one side only, and removing a value from one side only, each make the check fail.
- **Record:** The probes.
- **If it fails:** A parity check that only probes one side's list misses removals.
- **Risk:** modifies

### P6.04 Extend the linter, and test the extension
- **Needs:** P4.11
- **Do:** Add each new structural rule as a numbered section in `v1/utils/sw-lint.sh`, and tests in `v1/utils/sw-lint-test.sh` that copy the tree, inject one defect, and expect the failure message. Then break the new check itself and confirm its tests fail.
- **Verify:** The linter passes on the real tree and fails on each injected defect.
- **Record:** The new checks and test count.
- **If it fails:** A lint check with no failing test is decoration.
- **Risk:** modifies

### P6.05 Write acceptance scenarios for what only a model can show
- **Needs:** P4.11
- **Do:** For each rule that depends on a model's behavior, add a scenario under `v1/tests/scenarios/`. The schema and check types are in the docstring and validator of `v1/tests/sw_acceptance.py`. Mark rules that protect safety as **critical**. Use a scripted prelude to reach the state under test. Include no literal that looks like a secret.
- **Verify:** `python3 v1/tests/sw_acceptance.py --dry-run` accepts the scenarios.
- **Record:** The scenario ids and what each covers.
- **If it fails:** The validator names the file and the problem.
- **Risk:** creates

### P6.06 Write good and bad golden replies, and gut each check
- **Needs:** P6.05
- **Do:** The scenario tests require a golden reply that must pass every check and rule-breaking replies that must fail one. Write the bad reply to be caught by **only the check you are testing**: one that sounds compliant while doing the wrong thing. Then gut that check (make its pattern unmatchable) and confirm the golden test fails.
- **Verify:** Each critical check, when gutted, fails a test. A "bad" reply that another check also catches hides a weakness.
- **Record:** Any reply you had to rewrite.
- **If it fails:** Strengthen the bad reply.
- **Risk:** modifies

### P6.07 Wire new suites into the gate
- **Needs:** P6.04
- **Do:** Add each new suite to the `suite` list in `v1/utils/sw-release.sh`, so a release runs it. If another open PR edits the same lines, note the overlap for the hand-off instead of guessing at the merge.
- **Verify:** `bash v1/utils/sw-release.sh --check --skip-suites` still runs, and lists only the blockers you expect.
- **Record:** The suite names.
- **If it fails:** Do not waive a condition to make it pass.
- **Risk:** modifies

### P6.08 Document it accurately
- **Needs:** P6.07
- **Do:** Add a README section and `## Unreleased` entries in `CHANGELOG.md`. State plainly that it is opt-in, what is not verified, and the known gaps. Use only numbers you measured at P7.
- **Verify:** Every claim is one you can trace to a command.
- **Record:** Nothing further.
- **If it fails:** Cut the claim.
- **Risk:** modifies
