# Prompt migration map: 1.5.0 to 1.6.0-dev

Traceability for the restructure of `v1/prompt.md` (plan Phase 1). Every named block of the 1.5.0 prompt is listed with where it lives now and what kind of change it got. This was derived by comparing the two files line by line, not from memory. Of 87 non-empty lines in the 1.6.0-dev prompt, 68 are byte-identical to 1.5.0.

**Kinds of change**

- **Verbatim**: byte-identical, same tier.
- **Moved verbatim**: byte-identical text, now in a feature.
- **Modified**: same block, reworded. The change is spelled out.

## Unchanged in the prompt (verbatim)

Role, Execution Model, Human Boundary, Intake, Objective Clarification Gate, Completeness Criteria Wizard (including its proposal template and the paragraph after it), Discovery, Baseline, Functional Steps, Stepwise Interaction (including the full step format and the `Run this and paste the output` and `next`/`skip` paragraphs), Output Validation, State Progression, Adaptive Planning, Error Handling, Assumption Verification, Privileged, Destructive, Existing Work, Network, Alternatives, Transparency, Protocol Consistency, Minimal Drift, Human Control, Completion, Final Summary, Communication, Core Principles, `Never skip the human execution boundary or invent evidence.`, Start.

The `Risk:` line of the step format is also unchanged.

## Moved out of the prompt

| 1.5.0 block | Now in | Change |
|---|---|---|
| Grouping | `feature:execution` | Moved verbatim |
| Scripts | `feature:execution` | Moved verbatim |
| Command Construction | prompt and `feature:execution` | **Split.** The first two sentences stay in the prompt verbatim, followed by the block's last sentence ("Sound shell engineering takes precedence over artificial command-count rules") and a pointer to the feature. Everything from `Avoid unnecessary shell complexity` onward, including that last sentence, is also in the feature verbatim |
| Logging | prompt and `feature:logging` | **Modified in the prompt** to a short form that keeps the two behaviors that matter without the feature loaded ("establish it before substantive execution", "do not wrap every command in logging machinery unnecessarily"). The original paragraph moved verbatim to the feature |
| One-Shot | prompt and `feature:execution` | **Modified in the prompt** to keep "not default", "explicit change of execution mode, never an inference", and "same safety, validation, and auditability requirements". The original moved verbatim to the feature |
| Clipboard Copy (Opt-In) | prompt (`Clipboard`) and `feature:clipboard` | **Rewritten**; see the rule-by-rule table below |

### Clipboard Copy, rule by rule

| 1.5.0 rule | 1.6.0-dev location |
|---|---|
| Copy is additive, never replaces terminal display | prompt `Clipboard`; feature "Always" |
| Copy is per invocation and requested by the operator with `runcopy -- <command>`; never enabled automatically or assumed | prompt `Clipboard` (now: unless the operator opts in per invocation or enables the session-scoped automatic mode); feature "Manual mode" |
| `runcopy --no-copy -- <command>` skips one invocation | feature "Manual mode" |
| Mention the wrapper is available when a step's output may be worth keeping; do not assume it | feature "Manual mode" |
| credential/privileged-data steps bypass copy regardless of operator request | prompt `Safety` and `Clipboard`; strengthened to "in manual or automatic mode" |
| Bypass prints `[StepWise] Clipboard copy bypassed: …` and terminal display is preserved | feature "Always". The notice is printed by `clipcopy.sh` (unchanged in behavior) |
| Reference implementation, backend order `termux-clipboard-set` → `xclip` → `pbcopy` → `clip.exe`, no-op with a notice | feature "Manual mode" |
| The function is one-time setup; using it stays opt-in per invocation | feature "Manual mode" |

## Modified in the prompt

| Block | Change |
|---|---|
| Version line | `1.5.0` to `1.6.0-dev` |
| Safety | Last sentence only. It said a credential/privileged-data step "automatically bypasses opt-in clipboard copy (see **Clipboard Copy**)". It now says such a step "never has its output copied to the clipboard, in manual or automatic mode, regardless of operator request (see **Clipboard**)" |
| Contextual Memory | One sentence appended: also track session state and which optional context is loaded, and keep memory to validated state, not raw output |
| Default Pattern | Items 6 and 7 changed (classify risk before presenting the step; clipboard and ledger follow **Clipboard** and **Session State**, and credential/privileged-data output is never copied), and one closing sentence added giving the order within every step. Items 1–5 and 8–12 are verbatim |

## New in the prompt

| Block | Plan section |
|---|---|
| Session State | 2.1 |
| Context Tiers (loading rules, addresses, precedence, version compatibility, `Blocked` on missing reference) | 1.2, 1.4, 1.5, 1.7, 1.8 |
| Feature index table | 1.6 |

## What this does not prove

The linter (`v1/utils/sw-lint.sh`) confirms the required rule strings in `v1/utils/prompt-invariants.txt` are still present. It cannot confirm that a model still behaves the same way. That needs the Phase 6 acceptance tests run against a model, which are not done yet.
