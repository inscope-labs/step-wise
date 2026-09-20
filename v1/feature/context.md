# Feature: Context

| | |
|---|---|
| Framework | 1.6.0 |
| Component | feature `context` (Tier 2) |
| Version | 1.6.0 |
| Depends on | specs `context/loading-rules`, `context/size-limits` |
| Supersedes | nothing; extends **Contextual Memory** in `v1/prompt.md` |
| Status | Released. Loaded on demand. |

Precedence: Prompt > Feature > Specs. Nothing here relaxes a rule in the mandatory prompt.

Load this when Contextual Memory is growing, outputs are long, you are about to carry state across many steps, or you need the tier-tracking and compaction rules.

## 1. What Contextual Memory gains in 1.6.0

The 1.5.0 fields are unchanged (Objective, CompletenessCriteria, completed and skipped steps, verified state, human confirmations, constraints, failures, corrections, affected paths, warnings, remaining objectives). 1.6.0 adds only the minimum new state:

| Field | Meaning | Source | Default |
|---|---|---|---|
| `session_id` | the active ledger session | the `[StepWise] Session started: <id>` notice the operator pastes | unset |
| `auto_clipboard_enabled` | automatic clipboard mode | `sw:auto-copy/enable` and `sw:auto-copy/disable` only | `false` |
| `ledger_path` | the active session's ledger file | the `[StepWise] Ledger: <path>` notice the operator pastes | unset |
| `next_ledger_index` | the index the next recorded step is expected to get | last `[StepWise] Ledger: recorded STEP <n> …` notice, plus one | unset |
| `context_loaded` | Tier 2 and Tier 3 items currently in context, each with its `Framework` version | your own loads | `[]` |

Rules:

- **You never write the ledger; the operator's shell does.** So `session_id`, `ledger_path`, and `next_ledger_index` are only what the operator's pasted output reported. Do not assume a session exists, and do not invent an index. The notice is authoritative; the counter is a convenience and is corrected whenever a notice disagrees.
- **Never put ledger contents in Contextual Memory.** Store the fact that evidence exists and where (`STEP 17`), not the evidence itself.
- These fields are session-scoped and reset with the session, like all session state.

## 2. Compaction

Context holds *state*; the ledger holds *historical evidence*.

```
raw shell output → validation → relevant state extracted → compact memory
                                                        ↘ raw output stays in the ledger (if a session is active)
```

Example. After a step whose output was a 30 KB `git diff`, record `working tree clean` or `commit abc123 verified`, plus `evidence: ledger STEP 17` when a ledger session is active. Do not restate or re-summarize the diff in later turns.

Compaction changes only what you **carry forward**. You cannot delete what is already in the conversation, but you stop repeating it.

**Never compact away:**

- the confirmed Objective and CompletenessCriteria, with their evidence types
- unresolved warnings and failures, including ones that a later step appeared to fix
- the distinction between shell evidence and human confirmation
- the `[n]` expected-output markers of the step currently awaiting a result
- pending destructive, privileged, or irreversible confirmations

Compaction never replaces validation. Validate from the pasted terminal output first (with `[n]` marker citations), then compact.

Without a ledger session, compact the same way but note that the raw evidence remains only in the conversation, so keep the specific lines that a later step may need to cite.

## 3. Loading discipline

- Operate on the prompt alone by default. Escalate only when the prompt is not enough, to the smallest sufficient item (spec `context/loading-rules`).
- Record each loaded item in `context_loaded`, so you do not reload something already in context and can say what is loaded.
- Do not load a second feature or a spec section "just in case".
- Budgets and the difference between source size, serialized size, and token cost are in spec `context/size-limits`.

## Detailed references

- `spec:context/loading-rules`: address resolution, fetching or asking for pasted text, version compatibility, precedence and hierarchy edge cases
- `spec:context/size-limits`: the measured limits per tier and how they are checked
