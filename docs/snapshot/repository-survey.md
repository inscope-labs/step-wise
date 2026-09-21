# Context Snapshot & Session Resume: repository survey

Deliverable of P2. It lists every area of the repository that relates to Context Snapshot & Session Resume, whether directly or indirectly, and says what each constrains or must change. Based on the tree at `feat/snapshot` `e08ec37`. Line numbers are for that commit.

**Method.** Fourteen concepts were scored across all tracked Markdown, shell and Python sources (excluding generated scenario JSON): snapshot, resume, persist, session, state, task, evidence, ledger, secret, reconcile, history, memory, lock, schema. High-scoring files were then read for the actual definitions and constraints they impose. Existing memory-sync design and survey documents were used as structural patterns.

**Relation key.** **Direct**: defines or implements it. **Produces**: generates the content or evidence. **Governs**: constrains how it may be loaded, sized, versioned, or trusted. **Enforces**: tooling that must be extended so it cannot drift. **Adjacent**: related, and deliberately kept separate. **Outside**: the environment.

## 1. Direct

| Area | What it says now | What the change must do |
|---|---|---|
| (none) | No existing feature, spec or utility implements durable task-resumable snapshots or a resume-with-reconciliation flow. | Create new Tier-2 feature file and supporting Tier-3 specs under `v1/feature/snapshot.md` and `v1/specs/snapshot/`. |

## 2. Produces

| Area | Relevance | Consequence |
|---|---|---|
| `v1/feature/clipboard.md` + `v1/specs/clipboard/ledger-format.md` | Ledger steps and evidence references are the only authorised form of durable observation. | Snapshots may store only evidence references (type + session_id + step), never raw command output or privileged data. |
| `v1/utils/swmem.py` + memory-sync specs | Demonstrates a working pattern for schema-versioned, append-only, secret-excluding persistence. | Reuse the same safety posture (allow-list, never serialize credentials, historical data is untrusted). |

## 3. Governs

| Area | Relevance | Consequence |
|---|---|---|
| `v1/prompt.md` (Session State, evidence rules, Objective Clarification Gate, risk labels) | Session State is ephemeral; historical data is never authority or evidence by itself; confirmation and risk gates remain mandatory. | Snapshot must never restore session-scoped controls (`AUTO_CLIPBOARD_ENABLED`, `MEMORY_ENABLED`, ledger activation, pending confirmations). Resume must re-establish current truth and re-run gates. |
| `v1/feature/context.md` | Contextual Memory is the compact, current, AI-carried working state; it is bounded and never persistent. | Snapshot is historical only. After reconciliation it may contribute to a fresh, bounded Contextual Memory; it does not replace it. |
| `v1/specs/context/loading-rules.md` + `size-limits.md` | Tier addresses, precedence (Prompt > Feature > Spec), size limits, allowed edges. | New feature must be addressed as `feature:snapshot`, specs as `spec:snapshot/<section>`, stay inside `feature_bytes = 7000` and `spec_section_bytes = 9000`, and appear in the prompt’s feature index only if required. |
| `v1/utils/prompt-invariants.txt` | Protected rule strings that must remain in the prompt. | Any prompt edit required by the feature must preserve every listed invariant; the invariant file itself is updated only deliberately. |

## 4. Enforces

| Area | Consequence |
|---|---|
| `v1/utils/sw-lint.sh` and related tests | Structure, size, header, hierarchy and required-rule checks. Because the existing linter suite is currently red on main, a feature-specific linter will be supplied at the end of this task (per operator instruction). |
| `v1/utils/clipcopy.sh` risk classifier | Risk labels used by any new commands or examples must remain in the protocol set. |
| Acceptance scenarios (`v1/tests/scenarios/`, `sw_acceptance.py`) | New safety properties (no automatic `next_action` execution, no restoration of session controls, evidence-reference-only, secret exclusion) will require scenarios. |

## 5. Adjacent

| Area | Why separate |
|---|---|
| `feature:memory-sync` + its three specs | Persistent memory of facts, constraints and failures across sessions. Snapshot is task-scoped, revisioned, resumable state with explicit reconciliation; the two must not be merged. |
| `feature:inspection` + ledger | Operator-controlled historical evidence store. Snapshots hold references into it; they do not become a second ledger. |
| `feature:clipboard` auto-copy controls | Session-scoped and never restored from a snapshot. |
| `docs/memory-sync/*` | Prior design and survey artefacts. Used only as structural examples; content is not copied. |
| Agent-guide (`docs/agent-guide/`) | Process constraints for this change itself; not part of the runtime feature. |

## 6. Outside the repository

| Area | Relevance |
|---|---|
| Operator’s shell and filesystem | All save/resume I/O occurs through operator-visible commands; the assistant never writes state itself. |
| Git repository identity (root, remote, branch, HEAD, worktree) | Resume must reconcile against live git state; divergence is reported, never silently accepted. |
| Environment profile (detected or declared) | Historical profile is informational only; current detection wins. |
| Terminal / session interruption | Primary user value of the feature. |

## 7. Conclusions

1. **What already exists** and should be extended, not duplicated: the opt-in session-flag pattern, untrusted-historical-data rule, secret-exclusion allow-list, evidence-reference model, and schema-versioning approach demonstrated by memory-sync.
2. **What collides** with the proposal: nothing. No current component provides durable, task-scoped, revisioned, reconcilable resume state.
3. **What must be reused, not reimplemented:** evidence references (never raw output), session-scoped controls that stay ephemeral, Objective Clarification Gate, risk and confirmation gates, and the “historical data is never authority” invariant.
4. **Boundary constraints** that shape the design: the assistant has no direct execution; all persistence is operator-mediated; a snapshot is untrusted historical data; resume never executes a stored `next_action`; material divergence must be surfaced.
5. **Budgets that bind:** new feature file ≤ 7 000 bytes; each new spec section ≤ 9 000 bytes; prompt headroom is only 506 bytes, so Tier-1 changes must be minimal or the limit must be raised with justification in the same commit.
