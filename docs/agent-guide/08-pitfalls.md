# 08. Pitfalls

Every entry here happened. Read it before publishing, and when something behaves oddly. Add a row only for a real failure, with the step that prevents it.

## Process and repository

| What happened | Cause | Prevent |
|---|---|---|
| A PR's tests never reached the base branch | The PR was based on another feature branch. That branch merged first, and the second PR merged into a dead branch | P8.08. Base on the default branch, always (H3) |
| Compiled `.pyc` files were committed | `git add` of a directory right after running the tests | P8.04, P7.06. Stage by path, and keep bytecode in `.gitignore` |
| Files in the working tree changed that the agent never touched | Another session shared the default working directory, and the reflog showed its commits | P1.01, P1.08. Use a private clone, and check `git status` before every commit |
| 22 release tests and 1 lint test failed the moment a release landed | The tests copied the live tree and assumed it was still pre-release | P5.05. Build a fixture, never depend on the current state |
| A release left a pre-release version in a `Depends on` row, and the obvious fix (rewriting it) would have invalidated recorded evidence | The script rewrote and checked only the `Framework`, `Version` and `Status` rows, and the evidence hash counted version numbers inside `Depends on` rows | If a new file puts a version number in any header row other than `Framework`, `Version` and `Status`, check that the release script and the evidence hash both handle that row |
| A claimed rendering bug was not real | It was judged from raw fence counts, but an unclosed fence inside a list item ends with the item | P7.04. Parse before claiming |
| "Remove the block" could mean deleting the gate or waiving one condition | An ambiguous instruction | 00 section 3. State your reading and do the smaller thing. The waiver is scoped, recorded, and never creates evidence |
| Push returned 403 although reading worked | The token was read-only. A public repository clones without a token, which hides that | P8.05. Report it and stop |
| A `mergeable` field read `null` right after opening a PR | GitHub computes it asynchronously | Poll briefly before deciding anything |

## Tests

| What happened | Cause | Prevent |
|---|---|---|
| A defect-injection test passed although nothing was injected | The `sed` pattern matched nothing | P6.02. Disable the check and confirm the test fails |
| A mutation showed "not caught" when it had never been applied | The target text was not found, or shell escaping mangled it | P6.01. Assert the target exists and the file parses |
| A suite passed on its first run and hid a real gap | It only tested the cases the author thought of | P6.01. Break the code on purpose |
| A parity check missed a removed label | It probed only one side's list | P6.03. Probe both sides, plus edge cases |
| A probe list silently lost its empty entry | Command substitution strips trailing newlines | P6.03. Never put the empty entry last |
| A regex could never match the reply it was written for | A tokenization slip (`i (have|'ve)` needs a space that "I've" lacks) | P6.06. A golden good reply must pass every check |
| A "bad" reply was caught by a different check than the one under test | The check under test could have been broken unnoticed | P6.06. Gut the check and confirm a test fails |
| Test fixtures shaped like secrets risked blocking the push | Secret scanning flags literals | P5.06. Assemble them at run time |
| A script's option-parsing loop hung forever | `shift 2` fails when only one argument is left, so the loop never advanced | Check `$# -ge 2` for every option that takes a value, and test it under `timeout` |
| A store's root directory was world-readable | `makedirs(mode=...)` applies the mode to the leaf only | P5.03. Create private directories explicitly |
| A write path stored unknown fields | Writers accepted what readers tolerate | P5.03. Be strict on write, permissive on read |
| Recall silently dropped relevant items | A search rule that was correct for search and wrong for recall | P5.04. Smoke-test by hand |

## Tooling and reporting

| What happened | Cause | Prevent |
|---|---|---|
| A checker printed FAIL for suites that passed | Bash-only `[[ ]]` run under `sh` | Run scripts with `bash` (05, "What green means") |
| A call failed with a syntax error, or a payload was mangled | An apostrophe inside an inline `bash -c '...'` string, or a nested heredoc | P8.08. Put text in files and build JSON with a script |
| A background job produced nothing, and a `pkill -f` killed its own shell | Background jobs can die when the call returns, and the pattern matched the killer's command line | P7.02. Foreground with `timeout` |
| A command ran past the tool's time limit | A long suite in a single call | P7.02. Split, and give every command a limit |
| A verification count in a PR body was overstated | It was written from impression, not from a tally | P7.05, P8.09. Count what you ran, and correct at once |
| Evidence recorded before an edit went stale | Evidence is tied by hash to the exact text | Record acceptance evidence after your last edit to the prompt, tiers, or scenarios |
| Prompt headroom was nearly gone when the feature arrived | It was measured late | P1.04. Measure first, and let it shape the design |
