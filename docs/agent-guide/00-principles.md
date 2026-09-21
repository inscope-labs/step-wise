# 00. Principles

## 1. StepWise applies to changing StepWise

You follow the protocol in `v1/prompt.md` while you change it. Nothing in this guide replaces it. The mapping:

| Protocol element | What it means for this task |
|---|---|
| Objective Clarification Gate | State the change in one line with an observable success condition, and get it confirmed before any survey or design |
| Completeness Criteria Wizard | Propose 2 to 6 checkable criteria (the template has a standard set), and get them accepted. You cannot skip this |
| Discovery, Baseline | The repository survey, and a green baseline on the base branch. Do not modify state until both exist |
| One functional step per turn | Each guide step (`P<phase>.<nn>`) is one bounded step with expected output, in human-executed mode |
| Risk classification | Classify every step before you take it. Anything that is not read-only says so |
| Evidence over assumption | Recorded command output is evidence. Your memory of a number is a claim |
| State progression, `Blocked` | If a required source cannot be read, you are Blocked. You do not infer it |
| Final Summary | The hand-off (P9): status, steps, discoveries, changes, affected paths, verification, unresolved issues |
| Minimal drift | Change only what the objective needs. Mention other improvements, do not make them |

## 2. Two execution modes

**A. Human-executed (strict).** You cannot run commands. Give one step at a time, with the command and a numbered expected-output block, and wait for pasted output. Validate it, citing markers for any mismatch, before the next step.

**B. Delegated.** You have tools and were asked to do the work. You may run steps yourself, and you may batch **read-only** steps. These stay mandatory:

- the Objective and criteria gates, before you start
- risk classification before every step, and evidence cited from real output
- explicit operator confirmation for anything outside the authorization scope (section 3)
- no fabricated or hand-edited evidence, ever
- the final summary, including what is unverified

Batching never applies to a step that modifies shared state (push, merge, tag, delete). Those are single, confirmed, and verified after.

## 3. Authorization scope

Authorization is what the operator said, not what is convenient.

| The operator said | You may | You may not |
|---|---|---|
| "propose / draft / generate a feature" | create files and commits on a private branch | push, or open a PR |
| "push the branch" | push that branch | open a PR, merge |
| "open a PR" / "set up the PR" | push that branch, open a **draft** PR | merge, tag |
| "merge it" (naming the PR) | merge that PR, pinned to a verified commit | tag, release, merge others |
| "tag / release" | use the release gate as documented | bypass its conditions without a recorded waiver |
| nothing about it | nothing outward-facing | push, merge, tag, delete, force, rewrite history |

If a request is ambiguous ("remove the block", "complete the release"), say what you understand it to mean, and do the smaller thing.

## 4. Hard rules

- **H1. Work in a private clone.** Another session may share the default working directory. Create your own with a unique path.
- **H2. Never push to the base branch.** Push a feature branch, then use a PR.
- **H3. Never base a PR on another feature branch.** It is stranded when that branch merges first. Base on the default branch.
- **H4. Never fabricate evidence.** Do not write a results file, a test count, or a "passes" you did not observe. A recorded waiver is not fabrication. A hand-written pass is.
- **H5. Never weaken a safety rule to make a check pass.** Fix the check, or ask.
- **H6. No secrets anywhere.** Not in the repository, tests, PR bodies, logs, or memory. Test fixtures that look like secrets are assembled at run time (see [04](04-implementation-and-tests.md)).
- **H7. Measure before you claim.** Every count, size, and headroom in a hand-off comes from a command you ran on the final state.
- **H8. Report anomalies at once.** Files that changed under you, a test that passed on its first run, a number that does not match: say so, do not smooth it over.
- **H9. One source of truth.** If a fact has a source, cite the source. Do not copy the value.
- **H10. Default off, and opt-in.** A new capability changes nothing for someone who does not turn it on.

## 5. Credentials you are handed

- Use a token through an HTTP header for the one command that needs it. Never put it in a URL, a git config, a file, or an environment file you leave behind.
- Redact it from any output you show.
- Do not store it in memory or in any repository.
- Say at the end that it is still live and should be revoked.
- If it turns out read-only, say so and stop. Do not look for another route.

## 6. What good reporting looks like

State the verified facts first, with the command or output they came from. Then what you did not verify. Then the decisions that belong to a human. If you found and fixed your own mistake, say so plainly. A hand-off that hides its corrections cannot be trusted about anything else.
