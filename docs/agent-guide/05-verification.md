# 05. Verification

Phase P7. "Done" means every completeness criterion is established by evidence you produced on the **final** state. Verification of the *pushed* branch from a fresh clone is step P8.06, because it needs the push first.

## What green means

- Judge a suite by its **exit status**, and read its output as well. A summary line can look right while the suite tested nothing.
- Compare test counts to the baseline from P1.03. Counts should rise by the tests you added. A count that fell is a finding.
- If a checker says FAIL, check the **checker** before the code. If it says PASS, ask what it would have said if the code were broken (P6.02).
- Run scripts with `bash`, never `sh`. Bash-only syntax (`[[`, arrays, `${x:0:n}`, `<(...)`) fails silently or misleadingly under `sh`.

## P7

### P7.01 Run the full verification matrix
- **Needs:** P6.08
- **Do:** `bash docs/agent-guide/templates/verify-all.sh --dir <clone>`. Slow suites are excluded by default. Pass `--slow` to include them, and give each command a time limit.
- **Verify:** Every suite reports pass, and the script exits 0.
- **Record:** Each suite and its counts.
- **If it fails:** Fix the cause. Do not remove a test, and do not loosen a check.
- **Risk:** read-only

### P7.02 Run the slow suites
- **Needs:** P7.01
- **Do:** Run the release-script tests (they run every other suite inside a full-gate test, so they take minutes) as a foreground command with a time limit. Never background a job: it can die when the call returns, and a process killer that matches its own command line kills itself.
- **Verify:** Exit status 0, and the pass count matches its baseline plus what you added.
- **Record:** The counts and the duration.
- **If it fails:** If it exceeds the tool's time limit, split the work, and do not weaken the tests.
- **Risk:** read-only

### P7.03 Run the static checks
- **Needs:** P7.01
- **Do:** `shellcheck -s bash -S warning` on every shell file you touched or added, and `pyflakes` on every Python file. Gate a commit on their exit status, not on your reading of the output.
- **Verify:** Both exit 0. If a tool is not installed, that is "not verified", and you write it down as such.
- **Record:** The result, or the absence of the tool.
- **If it fails:** Fix the warning. Do not add a suppression comment without a reason.
- **Risk:** read-only

### P7.04 Check how the Markdown renders before claiming anything about it
- **Needs:** P7.01
- **Do:** Parse each changed `.md` with a CommonMark parser and check that headings and fenced blocks come out as intended. Do not judge from raw fence counts: an unclosed fence inside a list item ends with the item and renders fine.
- **Verify:** Every heading you wrote is a heading, and every code block is one.
- **Record:** Any real rendering defect.
- **If it fails:** Fix it. Do not report a defect you inferred but did not parse.
- **Risk:** read-only

### P7.05 Re-measure every number you will publish
- **Needs:** P7.01
- **Do:** Build a numbers ledger of every count, size, and headroom that will appear in the README, CHANGELOG, design document, or PR body, each with the command that produces it: prompt bytes and headroom (`wc -c` and the `limit:` line), the largest feature and spec, the worst-case optional context (`bash v1/utils/sw-lint.sh --report`), each suite's test count, the scenario count (`python3 v1/tests/sw_acceptance.py --dry-run`), and the number of injected bugs you ran (from your own tally).
- **Verify:** Each number was produced on the final tree, after your last edit.
- **Record:** The ledger. It is your source for P8.
- **If it fails:** A number you cannot reproduce does not go in. Overstating a verification count is a real failure. Count what you ran.
- **Risk:** read-only

### P7.06 Check the tree for stray artifacts
- **Needs:** P7.01
- **Do:** `git status --short`. Look for bytecode, temp files, results, and anything you did not mean to add. Confirm `git ls-files | grep -c pyc` prints 0.
- **Verify:** Every listed path is one you intend to commit, and untracked paths that should never be committed are ignored.
- **Record:** The status.
- **If it fails:** Fix `.gitignore` or remove the file. Never `git add` a directory wholesale after running tests, because that is how bytecode gets committed.
- **Risk:** read-only

### P7.07 Confirm what the release gate says
- **Needs:** P7.01
- **Do:** `bash v1/utils/sw-release.sh --check --skip-suites`.
- **Verify:** Only the blockers you expect appear (uncommitted changes before you commit, and missing acceptance evidence). A feature branch is not a release, and this check does not change any file.
- **Record:** The output.
- **If it fails:** An unexpected blocker is a finding. Do not use a waiver to clear it.
- **Risk:** read-only

### P7.08 Check the survey and design for unsupported claims
- **Needs:** P7.05
- **Do:** Re-read the survey and design document against the ledger. Every "we found" cites a file, and every measurement cites a command.
- **Verify:** Nothing in them is stronger than its evidence.
- **Record:** Any sentence you weakened or removed.
- **If it fails:** Weaken it to what you can support.
- **Risk:** read-only
