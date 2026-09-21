# 01. Intake and preflight

Phases P0 and P1. Nothing here changes the repository.

## P0. Intake

### P0.01 State the objective in one line
- **Needs:** nothing
- **Do:** Write one line: what changes or is established, plus at least one observable success condition. Example shape: "Add an opt-in feature X so that Y can be recalled across sessions; done when its specs pass the linter and a draft PR exists."
- **Verify:** The line names a target and a condition someone could check without asking you.
- **Record:** The line, verbatim.
- **If it fails:** Ask up to three clarifying questions, then restate. Do not start work on an unconfirmed objective.
- **Risk:** read-only

### P0.02 Get the objective confirmed
- **Needs:** P0.01
- **Do:** Show the line to the operator and wait for an explicit yes or an edit.
- **Verify:** An explicit confirmation is in the conversation. Silence is not confirmation.
- **Record:** The confirmed wording.
- **If it fails:** Stay Blocked. Do not survey or design.
- **Risk:** read-only

### P0.03 Propose and confirm completeness criteria
- **Needs:** P0.02
- **Do:** Copy [templates/task-plan.md](templates/task-plan.md). Use its six standard criteria and fold feature-specific requirements into them, because the protocol bounds the list at 2 to 6 items. Mark each with its evidence type. Get them accepted, edited, or rejected.
- **Verify:** An accepted list exists. You may not skip this step, and "skip" is not a valid answer to it.
- **Record:** The accepted list, with edits.
- **If it fails:** Revise and ask again.
- **Risk:** read-only

### P0.04 Classify the change type
- **Needs:** P0.02
- **Do:** Match the objective to a row in [07-change-types.md](07-change-types.md). Follow that row's phase list.
- **Verify:** You can name the row and the phases it skips.
- **Record:** The change type.
- **If it fails:** If it fits no row, say so and ask, rather than picking the closest.
- **Risk:** read-only

## P1. Preflight

### P1.01 Create a private clone
- **Needs:** P0.03
- **Do:**
  ```bash
  WS="$(mktemp -d /tmp/stepwise-ws.XXXXXX)" && git clone -q <repo-url> "$WS/repo" && cd "$WS/repo" && pwd
  ```
- **Verify:** The path is one you just created, under a unique name, and `git status` is clean. Another session cannot be writing to it.
- **Record:** The path.
- **If it fails:** Do not fall back to a shared working directory.
- **Risk:** creates

### P1.02 Record the base and look for collisions
- **Needs:** P1.01
- **Do:** Note the base branch tip (`git log --oneline -n 1`). List open pull requests and their changed files. If a PR touches the files you expect to change, note the overlap.
- **Verify:** You can state the base commit and every open PR that overlaps your scope.
- **Record:** The base commit, and the overlapping PRs (or "none").
- **If it fails:** If a PR already implements your objective, stop and tell the operator instead of duplicating it.
- **Risk:** network

### P1.03 Establish a green baseline
- **Needs:** P1.01
- **Do:** Run the verification script from [templates/verify-all.sh](templates/verify-all.sh) against the clone, with bash.
- **Verify:** Every suite passes on the untouched base. Any failure here is a finding.
- **Record:** The suite list and pass counts, so a later run can be compared.
- **If it fails:** Stop and report. Never build on a red baseline, and never hide it.
- **Risk:** read-only

### P1.04 Measure the budgets
- **Needs:** P1.03
- **Do:** Run `bash v1/utils/sw-lint.sh --report`. Read the limits from the `limit:` lines in `v1/specs/context/size-limits.md`. Compute the headroom for the prompt, the largest feature, the largest spec, and the worst case.
- **Verify:** You have a number for each headroom, and you know which limit binds first.
- **Record:** The headroom figures. They decide how much you may add to Tier 1.
- **If it fails:** If headroom is below what the feature needs, that is a design constraint. Surface it at P3.
- **Risk:** read-only

### P1.05 Read the sources of truth
- **Needs:** P1.01
- **Do:** Read the files in the README's "Sources of truth" table that your change type touches. At minimum: `v1/prompt.md`, `v1/specs/context/loading-rules.md`, and one existing feature and spec as a pattern (`v1/feature/inspection.md` and `v1/specs/clipboard/ledger-format.md` are good ones).
- **Verify:** You can cite, without guessing, what a tier file's header contains and what edges are allowed between tiers.
- **Record:** The files you read.
- **If it fails:** If you cannot read one, you are Blocked on it. Do not infer its rules.
- **Risk:** read-only

### P1.06 Choose and reserve the branch name
- **Needs:** P0.04
- **Do:** Name it by change type: `feat/<feature>`, `fix/<topic>`, `docs/<topic>`, `test/<topic>`. Confirm no such branch exists on the remote.
- **Verify:** `git ls-remote --heads origin <branch>` prints nothing.
- **Record:** The branch name.
- **If it fails:** Choose another. Never reuse or overwrite an existing branch.
- **Risk:** read-only

### P1.07 Create the branch
- **Needs:** P1.03, P1.06
- **Do:** `git checkout -b <branch>` from the base tip.
- **Verify:** `git branch --show-current` prints the name, and the tree is clean.
- **Record:** Nothing further.
- **If it fails:** Stop and inspect. Do not force.
- **Risk:** creates

### P1.08 Arm the anomaly check
- **Needs:** P1.07
- **Do:** Before every commit, run `git status --short` and confirm every listed file is one you changed. Note the time of your last write.
- **Verify:** No file appears that you did not touch, and no file you edited has reverted.
- **Record:** Any anomaly, immediately.
- **If it fails:** Something else is writing in your tree. Stop, report, and move to a fresh clone.
- **Risk:** read-only
