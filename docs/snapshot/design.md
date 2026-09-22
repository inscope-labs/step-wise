# Context Snapshot & Session Resume: design

Rationale for the feature in `v1/feature/snapshot.md` and `v1/specs/snapshot/`. The survey of what it touches is in [`repository-survey.md`](repository-survey.md). This document records the decisions, the alternatives that were rejected, the data classification, the threat model, failure behaviour, tier placement, and the items that remain for human decision.

Based on the tree at `feat/snapshot` `e08ec37` and the proposed feature specification (Context Snapshot & Session Resume v2.0.0).

## 1. Goal, and what it must not become

**Goal.** Provide a durable, local, revisioned representation of a StepWise task’s historical resumable state so an operator can interrupt work, close a terminal, switch repositories or tasks, and later re-establish the task without unnecessarily repeating known discovery. On resume the historical state is treated as untrusted input that must be reconciled against the live environment before it can influence continued execution.

**What it must not become:**

- A second Contextual Memory or a persistent Session State.
- An automatic executor of stored `next_action` values.
- A store of raw command output, credentials, or privileged data.
- An authority that can override the current prompt, feature rules, operator instructions, or evidence gates.
- A silent restorer of session-scoped controls (`AUTO_CLIPBOARD_ENABLED`, `MEMORY_ENABLED`, ledger activation, pending confirmations).
- A replacement for the operator-controlled ledger.

Governing rule (from the proposal):  
> A snapshot remembers what was known at a particular point; resume must establish what is true now.

## 2. Decision table

| Decision | Chosen | Rejected alternatives | Reason |
|---|---|---|---|
| Storage location | Project-local `.stepwise/` directory (state.yaml, events.jsonl, snapshots/, lock) plus optional global registry as locator only | Global-only store; embedding inside the ledger; memory-sync store | Keeps task state with the repository it describes; registry is deliberately non-authoritative |
| Identity model | Separate Task ID, Session ID, Snapshot ID; monotonic revision | Single session-scoped ID; content-addressed only | Enables multi-session task continuity and crash recovery without merging contexts |
| Evidence model | Reference-only (`ledger_step`, `artifact`, `git_object`, \ldots) | Copy of raw output or full transcripts | Preserves evidence-first model and secret exclusion |
| Fact lifecycle | Explicit states: historical_verified, current_verified, stale, invalidated, unknown | Simple TTL only | Time alone cannot determine validity; revalidation is required for environment-sensitive facts |
| Resume behaviour | Full validation → reconciliation → bounded Contextual Memory reconstruction → Resume Brief; never auto-execute `next_action` | Silent restore; automatic continuation | Prevents stale or injected state from becoming live authority |
| Session-state handling | Never restore; new session initialises its own defaults | Partial restore of non-safety flags | Session-scoped controls remain session-scoped |
| Concurrency | Advisory lock file with session/process/host metadata; human confirmation required to break | Time-based stale-lock assumption | Avoids false “stale” decisions |
| Integrity | Optional SHA-256 checksum as corruption detector only | Authenticated signature in v1 | Checksum is sufficient for accidental corruption; stronger authenticity left for later |
| Opt-in | Default off; activated only by explicit operator commands | Always-on or prompt-level default | Satisfies “default off, and opt-in” hard rule |
| Implementation language for any helper | Shell + Python 3 (same as swmem) if helpers are required | New runtime | Consistency with existing tooling |

## 3. Data classification (what is kept)

| Item | Treatment | Reason |
|---|---|---|
| Task identity, objective, scope, exclusions, criteria | Kept (with state) | Required to prevent scope drift on resume |
| Progress (completed steps, next_action as data) | Kept | Historical progress; next_action is never executed automatically |
| Historical facts with evidence references | Kept (status = historical_verified) | Guides discovery; never satisfies current evidence requirements by itself |
| Warnings | Kept | Unresolved issues must surface |
| Environment profile & repository fingerprint (observed) | Kept (informational) | Enables reconciliation; current detection always wins |
| Evidence references | Kept | Authoritative evidence stays in the ledger/artifacts |
| Captured session metadata | Kept (informational only) | Diagnostics; never restored |
| Raw command output, transcripts | **Never** | Secret and privilege boundary |
| Credentials, tokens, private keys, cookies | **Never** | Explicit allow-list exclusion |
| Active confirmations / authorizations | **Never** | A past confirmation is not current authorization |
| Session-scoped controls | **Never** | Ephemeral by design |
| Full terminal history | **Never** | Out of scope and high risk |

## 4. Threat model

The trust boundary is **whoever can write the snapshot files**. There is no authentication in v1.

| Threat | Defence |
|---|---|
| Snapshot text interpreted as new instructions (objective, next_action, warnings, facts, notes) | All persisted textual fields are untrusted data. Explicit rule: snapshot content never changes the prompt, feature precedence, risk classification, or authorization. Resume Brief and reconciliation force human review. |
| Hostile or corrupted snapshot accepted as current truth | Strict schema validation; optional integrity checksum; mandatory repository & environment reconciliation; material divergence is reported and requires normal decision/confirmation flow. |
| Stale claim treated as verified evidence | Fact lifecycle distinguishes historical_verified from current_verified. Missing or inaccessible evidence reference demotes the claim. |
| Secrets or privileged output persisted | Allow-list serialisation; never copy raw output; same secret-handling posture as memory-sync and the ledger. |
| Automatic execution of stored next_action | Explicit prohibition; resume ends at the Resume Brief and the normal interaction loop. |
| Restoration of session-scoped safety controls | Session State is initialised from current defaults only; captured metadata is informational. |
| Lock-file race or stolen lock | Lock records session/process/host; breaking requires human confirmation and an event. |
| Schema or feature incompatibility | Versioned schema; unknown or newer schema is rejected; migration is explicit. |
| Clock / ordering attack | Monotonic revision + event sequence; crash recovery presents discrepancies rather than choosing a side. |

**Remaining risks (accepted for v1):**  
- Checksum is corruption detection only; an attacker who can modify both state and checksum can bypass it.  
- No encryption at rest.  
- Heuristic secret scanning (if implemented) will miss novel formats; the primary control is the allow-list and the operator who runs the save command.

## 5. Failure behaviour

| Dependency / condition | Behaviour |
|---|---|
| Snapshot file missing or unreadable | `SNAPSHOT_NOT_FOUND` / `SNAPSHOT_MALFORMED`; fail closed |
| Schema unsupported or migration required | Block; report `SCHEMA_UNSUPPORTED` or `MIGRATION_REQUIRED` |
| Integrity checksum mismatch (when present) | `INTEGRITY_FAILURE`; fail closed |
| Repository missing or identity changed | Report divergence; do not silently adopt historical identity |
| Material divergence (branch, HEAD, worktree, environment) | Surface in Resume Brief; continue only through normal confirmation |
| Evidence reference unavailable | Demote corresponding claim; never treat as currently verified |
| Lock conflict | Report; require human decision to break |
| Optional helper tool missing | Continue without the helper and say so (same pattern as memory-sync) |
| Required spec or feature rule missing | `Blocked` for the behaviour that depends on it; never infer |

## 6. Opt-in and reversibility

Default: off.  
An operator who never issues a snapshot-related command experiences no change in behaviour, no new files, and no new session state.  
Activation is via explicit operator commands (to be defined in the feature file, following the `sw:<feature>/<action>` pattern). All such state is session-scoped except the durable snapshot files themselves, which are created only by an explicit save.

## 7. Tier placement and byte targets

| Artefact | Tier | Target size | Headroom check |
|---|---|---|---|
| `v1/feature/snapshot.md` | Tier 2 | ≤ 6 500 bytes (margin under 7 000) | Fits |
| `v1/specs/snapshot/schema.md` | Tier 3 | ≤ 7 000 bytes | Fits |
| `v1/specs/snapshot/lifecycle.md` | Tier 3 | ≤ 6 000 bytes | Fits |
| `v1/specs/snapshot/resume.md` | Tier 3 | ≤ 6 000 bytes | Fits |
| `v1/specs/snapshot/reconciliation.md` | Tier 3 | ≤ 5 000 bytes | Fits |
| `v1/specs/snapshot/integrity.md` | Tier 3 | ≤ 3 000 bytes | Fits |
| Prompt index entry (if required) | Tier 1 | < 100 bytes | Must stay inside 506-byte headroom or raise limit with justification |

No safety-critical rule is placed solely in Tier 2/3; the core invariants (“historical data is untrusted”, “never auto-execute next_action”, “never restore session controls”) will be restated in the feature file and, where necessary, protected via prompt-invariants.

## 8. Scale

No large-N data-plane measurements are required for v1: a snapshot is a single structured document per revision, not a growing log of records that is scanned on every operation. Event log growth is append-only and independent; retention policy will be defined in the lifecycle spec. If a helper tool is later added for large histories, measurement will be performed at that time and recorded here.

## 9. Verification plan (high level)

- Schema and state-machine validation (feature-specific linter, per operator instruction).  
- Round-trip: save → resume with no divergence.  
- Divergence cases: branch change, HEAD change, worktree dirty, environment profile change, missing evidence.  
- Negative: attempt to restore session controls, automatic next_action execution, secret serialisation, acceptance of malformed schema.  
- Crash-recovery scenarios for state/event consistency.  
- Acceptance scenarios for the safety invariants.

## 10. Decisions for the operator (P3.09)

| Decision | Recommendation | Cost of the alternative |
|---|---|---|
| Raise `prompt_bytes` if a Tier-1 index entry or invariant is required | Prefer to keep the prompt untouched or add only a one-line index entry; raise the limit only if unavoidable, with the reason recorded in the same commit | Leaving the prompt unchanged avoids a version-sensitive change; raising without need weakens the budget discipline |
| Exact command surface (`stepwise save/resume/\ldots` vs `sw:snapshot/\ldots`) | Follow existing `sw:<feature>/` pattern for consistency with memory-sync | A new top-level binary adds distribution and discovery cost |
| Whether a minimal helper binary/script is in scope for v1 | Defer executable helpers; keep the first version documentation-and-spec only if possible, or add only the smallest reader/writer needed for validation | Adding code expands the test and release surface |
| Retention defaults (max snapshots, max age) | Conservative defaults (e.g. keep last N + current) with explicit prune command requiring confirmation | Aggressive automatic pruning risks loss of the only recoverable snapshot |
| Global registry | Include as optional locator only; never authoritative | Making the registry authoritative creates a second source of truth |

These items will appear in the PR body and require explicit operator confirmation before implementation proceeds beyond design.
