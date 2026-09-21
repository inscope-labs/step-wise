# Task plan: <feature or change name>

Copy this file into your working notes and fill it in. Do not commit a filled-in copy. Get the objective and criteria confirmed (P0.02, P0.03) before starting P1.

## Header

| Field | Value |
|---|---|
| Change type | <row of 07-change-types.md> |
| Objective (one line, confirmed) | <what changes or is established, and the observable success condition> |
| Confirmed by / when | <who, in what words> |
| Execution mode | <human-executed, or delegated> |
| Private clone | <path> |
| Base branch and commit | <branch>, <sha> |
| Working branch | <name> |
| Authorized outward actions | <push / draft PR / merge / tag: only what was said> |

## Completeness criteria

Six standard criteria. Fold feature-specific requirements into them; the protocol bounds the list at 2 to 6 items.

| # | Condition | Evidence type | Status |
|---|---|---|---|
| C1 | The repository survey classifies every relevant area and states what already exists, what collides, what must be reused, and which budgets bind | artifact inspection: the survey and its conclusions (P2.05, P2.06) | |
| C2 | The feature, specs, and prompt edits pass the structure linter within every budget | linter output (P4.11) | |
| C3 | Every rule that protects safety has a test that fails when the rule is broken, and a scenario if it depends on a model's behavior | mutation results and gutted-check results (P6.01, P6.06) | |
| C4 | The full verification matrix passes from a fresh clone of the pushed branch, and every published number was re-measured on the final state | numbers ledger and command output (P7.05, P8.06) | |
| C5 | A draft PR against the base exists with the required sections and the correct state | API response (P8.08) | |
| C6 | Nothing was merged, tagged, or released without an explicit instruction, and the unverified items and the human decisions are listed | PR body, and explicit human confirmation of the decisions | |

## Steps

Mark each: `todo`, `done` (with the evidence you recorded), `skipped` (with the reason from the change-type row), or `blocked`. A step is done when its **Verify** condition was observed.

| Phase | Steps |
|---|---|
| P0 Intake | P0.01, P0.02, P0.03, P0.04 |
| P1 Preflight | P1.01, P1.02, P1.03, P1.04, P1.05, P1.06, P1.07, P1.08 |
| P2 Survey | P2.01, P2.02, P2.03, P2.04, P2.05, P2.06 |
| P3 Design | P3.01, P3.02, P3.03, P3.04, P3.05, P3.06, P3.07, P3.08, P3.09 |
| P4 Tier artifacts | P4.01, P4.02, P4.03, P4.04, P4.05, P4.06, P4.07, P4.08, P4.09, P4.10, P4.11, P4.12 |
| P5 Implementation | P5.01, P5.02, P5.03, P5.04, P5.05, P5.06, P5.07, P5.08 |
| P6 Enforcement | P6.01, P6.02, P6.03, P6.04, P6.05, P6.06, P6.07, P6.08 |
| P7 Verification | P7.01, P7.02, P7.03, P7.04, P7.05, P7.06, P7.07, P7.08 |
| P8 Publish | P8.01, P8.02, P8.03, P8.04, P8.05, P8.06, P8.07, P8.08, P8.09, P8.10 |
| P9 Hand-off | P9.01, P9.02, P9.03 |

| Step | Status | Evidence recorded |
|---|---|---|
| <step id> | <todo/done/skipped/blocked> | <output, path, or reason> |

## Numbers ledger (P7.05)

Every number you will publish, with the command that produced it on the final tree.

| Number | Value | Command |
|---|---|---|
| <what> | <value> | <command> |

## Decisions for the operator (P3.09)

| Decision | My recommendation | Cost of the alternative |
|---|---|---|
| <decision> | <choice> | <cost> |

## Baseline (P1.03)

| Suite | Result | Count |
|---|---|---|
| <suite> | <pass/fail> | <count> |

## Anomalies and corrections (P1.08, P9.02)

| What | When | What I did |
|---|---|---|
| <anomaly, or a mistake I corrected> | <when> | <action> |

## Not verified (P9.01)

- <thing you did not verify, and why>
