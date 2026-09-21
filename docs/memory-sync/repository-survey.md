# Contextual Memory Sync: repository survey

Deliverable 1 of the proposal. It lists every area of the repository that relates to a persistent, searchable, synchronizable implementation of the StepWise memory schema, whether directly or indirectly, and says what each area constrains or must change. It is based on the tree at `main` `334f62f` (`1.6.0`), scored file by file against the concepts a persistent memory touches (memory, persistence, sessions, ledger, state, constraints/paths/failures, evidence, secrets, hashing, compaction, `sw:` commands, untrusted-text quoting), then read directly. Line numbers are for that commit.

**Relation key.** **Direct**: defines or implements the memory schema. **Indirect, produces**: generates the content or evidence a memory would record. **Indirect, governs**: constrains how memory may be loaded, sized, versioned or trusted. **Indirect, enforces**: tooling that must be extended so the feature cannot drift or regress. **Adjacent**: related but should stay separate.

## 1. Direct: where the memory schema lives today

| Area | What it says now | What Contextual Memory Sync must do |
|---|---|---|
| `v1/prompt.md` L85, **Contextual Memory** | The field list: Objective, CompletenessCriteria, completed/skipped steps, verified state, human confirmations, constraints, failures, corrections, affected paths, warnings, remaining objectives. Also "Do not treat an old expected state as current if later operations may have changed it." | This is the schema to persist. Add one sentence that recalled memory is a hypothesis, never evidence. Decide per field whether it persists (see the schema spec: human confirmations must **not**) |
| `v1/prompt.md` L87, **Session State** | "Explicit, session-scoped, never persistent ... never written to ... files." | **A real conflict.** Keep the flags non-persistent, and state that the memory store is data written only by the operator's shell, not session state. Add `MEMORY_ENABLED` (default `false`) |
| `v1/prompt.md` L61 / L67 / L75, **State Progression, Assumption Verification, Existing Work** | "Claims guide discovery; evidence establishes state." "Do not ... repeat verified work unless state may have changed." | These are the rules recalled memory must obey. Recalled facts are *claims*. They may skip a discovery step only after a fresh re-check |
| `v1/prompt.md` Context Tiers + feature index (L93-97) | Five features indexed, one row each | Add a `feature:memory-sync` row. Prompt has 1,003 bytes of headroom (18,997 of 20,000) |
| `v1/feature/context.md` §1-3 | The 1.6.0 fields (`session_id`, `auto_clipboard_enabled`, `ledger_path`, `next_ledger_index`, `context_loaded`), compaction rules, "never compact away" list | The session-scoped half of memory. The persistent half must not duplicate it. Session fields are **never** persisted; only their *references* (a session id and a `STEP n`) may appear as evidence pointers |
| `docs/1.6.0-plan/...-02-IMPLEMENTATION.md` Phase 4 (4.1, 4.2) | "Do not put entire ledger contents into contextual memory"; "Context = state, Ledger = historical evidence" | Establishes the layering the new store completes: memory holds validated state and *pointers* to evidence, never raw output |
| `docs/1.6.0-plan/...-01-ARCHITECTURE.md` §1.9, §2.1; `...-03-VERIFICATION.md` §5.2 (layer 4, "Context Memory") | Memory is layer 4 of the five-layer architecture, "compact current operational state" | The persistent store is a new backing for layer 4. The diagram and the "Context = state" separation stay true |

## 2. Indirect, produces: where memory content and evidence come from

| Area | Relevance | Consequence |
|---|---|---|
| `v1/feature/inspection.md`, `v1/specs/clipboard/ledger-format.md` | The ledger records step output and assigns `STEP n`. It has a session directory, an append-only format, a lock, and **withholds sensitive output** | The ledger is the natural *evidence source* for a memory record (`source.ledger = "STEP 17"`). Reuse its patterns (append-only, mkdir-style locking, 0700/0600, malformed-record tolerance). Never copy ledger text into memory |
| `v1/utils/clipcopy.sh` L169 `_sw_state_root`, L192-198 `_sw_active_ledger`, L211 lock, L225 `umask 077` | State root is `STEPWISE_HOME` or `~/.cache/stepwise`. Session id grammar guards path traversal | **`~/.cache` is the wrong home for durable memory** (caches are deletable). Use the XDG data dir for the store and the XDG state dir for local-only state, with the same id-grammar discipline |
| `_sw_risk_class` in `clipcopy.sh`; the prompt's `Risk:` line; `feature/clipboard.md` §4 | The fail-closed classifier: sensitive or unrecognized labels never copy and are never written to the ledger | A memory write derived from a step must pass **the same gate**. A second implementation would drift (the earlier fail-open bug came from exactly this), so a lint check must keep them in agreement |
| `feature/clipboard.md` §3 and the prompt's Session State | The pattern for an opt-in, session-scoped mode with `sw:` commands (`sw:auto-copy/enable`) | Memory follows the same pattern: `MEMORY_ENABLED=false` by default, changed only by `sw:memory/on` and `sw:memory/off`, never persistent |
| `feature/inspection.md` §3, `feature/clipboard.md` L69; scenario `ledger-metadata-quoting` | Free text inside an operator-run command must be single-quoted, because double quotes let `` `...` `` and `$(...)` execute | Every memory write is a command with free text (`--text`, `--subject`). **The same injection class applies**, so the same rule and a lint check are required |
| `v1/utils/clipcopy.sh` `runledger` / `sw_session_start` output notices | The agent learns session ids and step numbers only from pasted notices | Same discipline for memory: the agent learns the store's state only from pasted output. It never assumes a store exists |

## 3. Indirect, governs: how memory may be loaded, sized and versioned

| Area | Relevance | Consequence |
|---|---|---|
| `v1/specs/context/size-limits.md` (`limit:` lines, L33-36, L49) | Contextual Memory target of ~2,000 tokens; worst-case optional context capped at 14,000 bytes with 1,164 bytes of headroom | Recall output must be compact and bounded (`--limit`). The new feature (≤ ~6.6 KB) and each new spec (≤ ~6.4 KB) must fit the existing limits, or a limit must be raised with a stated reason |
| `v1/specs/context/loading-rules.md` §3, §4, §6 | `Framework` major.minor compatibility; precedence Prompt > Feature > Specs; strict one-way loading | A new feature needs a header and a spec map. **Add a fourth precedence level: recalled memory is below Specs**, and can only *add* restrictions, never relax a rule |
| `v1/feature/context.md` §3 (loading discipline) | Record loaded items in `context_loaded` | Recalled memory is another thing to record, so it is not re-recalled needlessly |
| Prompt **Context Tiers** paragraph | Smallest-sufficient loading; `Blocked` on a missing reference | A missing `feature:memory-sync` blocks only memory behavior. The core protocol continues |

## 4. Indirect, enforces: tooling that must be extended

| Area | Consequence |
|---|---|
| `v1/utils/sw-lint.sh` §5 (index), §6 (spec reachability), §7 (hierarchy), §3 (sizes), §8 (invariants), §10 (untrusted text), §11 (label vocabulary) | The new feature and specs are checked automatically once indexed. **Extend** §10 to the new free-text options, and add a check that the memory tool's risk classifier agrees with the shell's |
| `v1/utils/sw-lint-test.sh`, `v1/utils/prompt-invariants.txt` | Add invariants for the new prompt rules (recalled memory is a hypothesis). Add lint tests for the new checks |
| `v1/tests/sw_acceptance.py`, `scenarios/`, `preludes.json`, `test_sw_acceptance.py` (golden replies) | Add scenarios for the new behavior (recall as hypothesis, never storing a secret, loading on demand). The golden test requires good and bad replies for each. `compute_hashes` already covers new tier files |
| `v1/utils/sw-release.sh`, `sw-release-test.sh` | New tier files carry `Framework`, `Version`, `Status` and `Depends on` rows that a release rewrites, so they must follow the header conventions |
| `CHANGELOG.md`, `README.md`, `docs/1.6.0-plan/compatibility.md`, `prompt-migration-map.md` | Document the feature, its opt-in default, and the deliberate carve-out from "never persistent". Start a new `-dev` cycle |
| `.gitignore` | A project may keep a store in `.stepwise/`. **This** repository must never commit one |
| `v1/utils/clipcopy-test.sh` | Model for hermetic tests: temporary home, stub backends, concurrent-writer and torn-record cases |

## 5. Adjacent: related, and deliberately kept separate

| Area | Why separate |
|---|---|
| `v1/feature/logging.md` | A session *log* is an interaction record. Memory is validated state. They must not be merged (`logging.md` already distinguishes log from ledger) |
| `v1/feature/execution.md` | Scripts and one-shot mode. Memory must never store or replay commands (see the safety spec) |
| `v1/examples/README.md` | The pending example transcript. A recall-then-work transcript belongs here once real runs exist |
| `LICENSE`, `.gitignore` (other than the note above) | Unrelated |

## 6. Outside the repository, but part of the system

| Area | Relevance |
|---|---|
| Operator's shell and Termux environment (`$HOME`, XDG dirs, Python availability) | The tool runs there. Termux has Python via `pkg`, but StepWise's shell utilities were bash-only until now, so the dependency must be stated and optional |
| The transport the operator chooses (git, rsync, Syncthing, a cloud folder, or a copied file) | Synchronization must work over plain files with no server, so any of these suffice |
| Other assistants (Gemini and others) | The agent never runs the tool. The operator does, and pastes output. So the protocol must work through pasted text on any assistant, with no tool-calling |
| `~/.cache/stepwise/sessions/` (ledger sessions) | Ephemeral. A memory record may cite a `STEP n` but must not depend on the session directory still existing |

## 7. What the survey concludes

1. **The schema already exists** (prompt L85). The feature extends it rather than inventing a parallel one, and adds provenance, validity and scope so it can persist safely.
2. **One rule collides**: "never persistent" (L87). It needs a precise carve-out, not a silent exception.
3. **Three existing mechanisms must be reused, not reimplemented**: the fail-closed risk gate, the untrusted-text quoting rule, and the ledger's append-only discipline.
4. **The human-execution boundary shapes everything.** The agent cannot read or write the store, so recall and save are operator-run steps with pasted output. That makes memory writes visible to the person before they happen, which is a safety property to keep.
5. **The budgets are tight** (1,003 bytes of prompt headroom, 1,164 bytes of optional-context headroom), so the feature is split into a compact Tier 2 file and three Tier 3 specs.
