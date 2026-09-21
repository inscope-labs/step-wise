# Agent guide: changing StepWise

For an AI agent asked to change StepWise: propose a new feature, correct a rule, or improve tooling. **Read this before you touch anything under `v1/`.** It is written to be followed, one atomic step at a time, and it is itself changed only through the process it describes.

## Three rules that outrank everything else in this guide

1. **No number without a source.** Never write a limit, count, or size from memory. Read it from its source (table below) or measure it, and say which.
2. **Nothing is merged, tagged, or released without an explicit instruction** from the operator naming that action. A request to "open a PR" or "push a branch" authorizes exactly that.
3. **Say what you did not verify.** Every hand-off states what was measured, what was not, and what needs a human decision.

## How to use it

1. Read [00-principles.md](00-principles.md) once. It is short.
2. Decide the change type in [07-change-types.md](07-change-types.md). It tells you which phases apply.
3. Copy [templates/task-plan.md](templates/task-plan.md), fill it in, and get the operator to confirm the Objective and criteria (StepWise's own gates, applied to this task).
4. Load each phase file only when you reach it. They are independent on purpose, so you carry only what the current phase needs.

| Phase | File | Load when |
|---|---|---|
| Principles, execution modes, hard rules | [00-principles.md](00-principles.md) | always, first |
| P0 intake, P1 preflight | [01-preflight.md](01-preflight.md) | starting |
| P2 survey, P3 design | [02-survey-and-design.md](02-survey-and-design.md) | before writing any file |
| P4 tier artifacts | [03-tier-artifacts.md](03-tier-artifacts.md) | writing the feature, specs, or prompt edits |
| P5 implementation, P6 enforcement | [04-implementation-and-tests.md](04-implementation-and-tests.md) | writing code, tests, lint, scenarios |
| P7 verification | [05-verification.md](05-verification.md) | before any claim of "done" |
| P8 branch, commits, PR; P9 hand-off | [06-branch-commit-pr.md](06-branch-commit-pr.md) | publishing |
| Which phases apply to which change | [07-change-types.md](07-change-types.md) | deciding scope |
| Failures already made once | [08-pitfalls.md](08-pitfalls.md) | when something behaves oddly, and before publishing |

Templates: [task plan](templates/task-plan.md), [PR body](templates/pr-body.md), [survey](templates/survey.md), [feature](templates/feature.md), [spec](templates/spec.md), and a [verification script](templates/verify-all.sh).

## The atomic step format

Every step has an ID (`P<phase>.<nn>`) and the same fields. A step is done only when its **Verify** condition is observed, not when its **Do** was attempted.

```
### P1.03 Title
- **Needs:** P1.02        (step IDs that must be done first, or "nothing")
- **Do:** the exact action or command
- **Verify:** the observable result that proves it
- **Record:** the evidence to keep for the hand-off
- **If it fails:** stop, fix and re-run, or escalate
- **Risk:** read-only, creates, modifies, network, ...
```

`Risk` uses the protocol's own labels. `Needs` may only name steps that exist. `v1/utils/sw-docs-lint.sh` enforces both, and also that every link and repo path in this guide resolves.

## Sources of truth

Do not restate these. Read them.

| Question | Source |
|---|---|
| Size limits per tier | the `limit:` lines in `v1/specs/context/size-limits.md` |
| What loads from where, precedence, version compatibility, allowed edges | `v1/specs/context/loading-rules.md` |
| What a tier file's header must contain, index and reachability rules | `v1/utils/sw-lint.sh` (run it, and read its failures) |
| The protocol itself: gates, step format, states, safety | `v1/prompt.md` |
| Which rules must never be lost from the prompt | `v1/utils/prompt-invariants.txt` |
| Risk labels and how they are classified | `v1/utils/clipcopy.sh` (`_sw_risk_class`) and `v1/feature/clipboard.md` |
| Acceptance scenario schema and check types | the docstring and validator in `v1/tests/sw_acceptance.py` |
| How a release is made and gated | `docs/1.6.0-plan/compatibility.md`, section 6, and `v1/utils/sw-release.sh --help` |
| What has been changed and why | `CHANGELOG.md` |

## Placeholders

In these files, anything that does not exist yet is written with angle brackets, such as `<feature>`. A real path that does not exist is a bug in the guide, and the docs linter fails on it.
