# 06. Branch, commits, PR, and hand-off

Phases P8 and P9. This is the only phase that changes anything outside your private clone, so it is the most tightly scoped. Re-read the authorization table in [00-principles.md](00-principles.md) before you start.

## P8. Publish

### P8.01 Confirm what you are authorized to do
- **Needs:** P7.08
- **Do:** Look at what the operator asked for, in their words, and match it to the authorization table. Write down which of push, PR, merge, and tag are covered.
- **Verify:** Each outward action you plan is covered by something the operator said.
- **Record:** The list of authorized actions.
- **If it fails:** Do the smaller thing, and ask about the rest. A proposal is not permission to push.
- **Risk:** read-only

### P8.02 Confirm the base has not moved
- **Needs:** P8.01
- **Do:** `git fetch`, then `git merge-base --is-ancestor origin/<base> HEAD`.
- **Verify:** It exits 0: your branch already contains the base tip, so there is nothing to conflict with.
- **Record:** The base commit.
- **If it fails:** The base moved. Bring it in, re-run P7.01, and only then continue. Never publish on a stale base without saying so.
- **Risk:** network

### P8.03 Plan the commits
- **Needs:** P8.02
- **Do:** Split the work into commits that each make sense alone, in dependency order: survey and design; specs, feature, and prompt edits; implementation and tests; enforcement (lint, scenarios, gate wiring); docs. Keep one topic per commit.
- **Verify:** You can say in one sentence what each commit does, and none mixes unrelated changes.
- **Record:** The plan.
- **If it fails:** Split it further.
- **Risk:** read-only

### P8.04 Stage explicitly and commit on a green check
- **Needs:** P8.03
- **Do:** Stage by path, never `git add -A` or a whole directory. Before each commit run `git status --short` (P1.08). Write a message that says what changed and **why**, and states any known limitation. Attribute the commit to yourself.
- **Verify:** `git show --stat` lists only what that commit is meant to contain.
- **Record:** The commit list.
- **If it fails:** Unstage and re-add. If the tree is red, do not commit.
- **Risk:** creates

### P8.05 Push the branch, and only the branch
- **Needs:** P8.04
- **Do:** Push with the credential in an HTTP header for this one command, never in the URL or git config, and redact the token from any output you show.
  ```bash
  B64=$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)
  git -c http.extraheader="Authorization: Basic $B64" push -u origin <branch>
  ```
  Never force. Never push the base branch.
- **Verify:** The remote head equals your local head (`git ls-remote --heads origin <branch>`).
- **Record:** The remote sha.
- **If it fails:** A 403 means the token cannot write. Report it and stop. Do not look for another route. A secret-scanning rejection means a literal secret-shaped string reached a file (P5.06), so fix the file.
- **Risk:** network

### P8.06 Verify the pushed branch from a fresh clone
- **Needs:** P8.05
- **Do:** Clone the branch into a new directory and run [templates/verify-all.sh](templates/verify-all.sh) there.
- **Verify:** The same suites pass, and their counts match your ledger. The clone proves that what you pushed is what you tested.
- **Record:** The output.
- **If it fails:** Your working tree differed from your commits. Find out how before doing anything else.
- **Risk:** network

### P8.07 Write the PR body from the template
- **Needs:** P8.06, P7.05
- **Do:** Fill in [templates/pr-body.md](templates/pr-body.md) in a **file**. Every number comes from the ledger. State plainly what is verified, what is not, and the decisions that belong to the operator.
- **Verify:** The body contains every required section, and none says more than the evidence supports.
- **Record:** The file.
- **If it fails:** Cut or soften the claim.
- **Risk:** creates

### P8.08 Open a draft pull request against the base
- **Needs:** P8.07
- **Do:** Build the JSON payload from the body file with a short script, so no inline quoting can mangle it (an apostrophe in an inline string has broken a call before), then POST it. The base is the default branch, **never** another feature branch. Set `draft` to true unless the operator asked for a ready PR.
  ```bash
  python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "head": sys.argv[2], "base": "<base>", "body": open(sys.argv[3]).read(), "draft": True}))' "<title>" "<branch>" body.md > pr.json
  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/<owner>/<repo>/pulls -d @pr.json
  ```
- **Verify:** The response has a PR number, `draft` is true, `base` is the default branch, and the commit and file counts match your plan.
- **Record:** The PR number and URL.
- **If it fails:** Read the API message. Do not retry blindly, and check that you did not create a duplicate.
- **Risk:** network

### P8.09 Correct the PR body if you find an error
- **Needs:** P8.08
- **Do:** If you notice anything overstated or wrong in the body, PATCH it immediately and tell the operator what you changed.
- **Verify:** The API returns the corrected text.
- **Record:** What was wrong.
- **If it fails:** Leave no known inaccuracy standing.
- **Risk:** network

### P8.10 Do not merge, tag, or release unless told to
- **Needs:** P8.08
- **Do:** Stop here by default. If the operator explicitly asks you to merge a named PR: re-fetch, confirm the base has not moved (P8.02) and that the PR head is the commit you verified, then merge with that sha so the merge fails if the branch changed. Merge related PRs in dependency order. After the merge, verify the base branch from a fresh clone. Create a tag only if asked.
- **Verify:** The merge response says merged, and the fresh clone of the base passes.
- **Record:** The merge commit.
- **If it fails:** If the base moved or the head differs, stop and report.
- **Risk:** network

## P9. Hand-off

### P9.01 Write the final summary
- **Needs:** P8.08
- **Do:** Follow the protocol's Final Summary: status, completed steps, skipped steps and why, important discoveries, changes, affected paths, tests and verification (numbers from the ledger), unresolved issues. Then list what is **not** verified and the decisions that belong to the operator.
- **Verify:** Every completeness criterion from P0.03 is marked established or not, with its evidence.
- **Record:** The summary.
- **If it fails:** If a criterion is not established, say so. Do not declare completion.
- **Risk:** read-only

### P9.02 Say what went wrong and how you fixed it
- **Needs:** P9.01
- **Do:** Include your own errors, anomalies, and corrections (a check that was wrong, a claim you changed, a file that changed under you).
- **Verify:** Anything you retracted or fixed appears in the summary.
- **Record:** The list.
- **If it fails:** Hiding a correction makes the rest of the summary less believable.
- **Risk:** read-only

### P9.03 Close out credentials
- **Needs:** P9.01
- **Do:** Confirm the token is not in any file, remote URL, git config, PR text, or memory. Tell the operator it is still live and should be revoked when they are done.
- **Verify:** `git grep` finds no token shape in the tree, and `git remote -v` shows no credential.
- **Record:** The check.
- **If it fails:** Remove it, tell the operator, and treat the token as compromised.
- **Risk:** read-only
