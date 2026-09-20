# Changelog

All notable changes to the StepWise protocol are recorded here.

**Versioning policy:** StepWise is pre-release. All changes are tracked as `1.x` (minor/patch) revisions of the same generation, regardless of how large the change is. The project moves to `2.0.0` only once the framework has been fully tested end-to-end (see the pending example transcript in `README.md`). Do not interpret any `1.x` bump below as a stability signal beyond "this changed."

## Unreleased — 1.6.0 (in progress)

**Not a release.** On the working branch `v1/prompt.md` is `1.6.0-dev`. Per the plan in `docs/1.6.0-plan/` (section 7.2), the `-dev` suffix comes off and the version becomes `1.6.0` only after the Phase 6 acceptance tests pass. Until then, do not merge the tiered prompt to `main` casually: the README's invocation prompt fetches `v1/prompt.md` from `main`, so merging changes what every new session loads.

- Fixed: `runcopy`'s clipboard bypass failed open. It matched only the exact strings `credential` and `privileged-data`, so the combined label `credential/privileged-data` (unified in 1.5.0), case variants, and any unrecognized label fell through to the copy path. It is now fail-closed: only known non-sensitive labels may copy; sensitive or unrecognized labels bypass with a notice. Repeated `--risk` flags accumulate (a later benign label cannot override an earlier sensitive one), an empty `--risk=` is unrecognized, and `--risk` with no value is an error. Omitting `--risk` keeps the 1.5.0 manual-copy behavior. Self-test extended to cover the combined label and unknown labels.
- Added: session ledger in `v1/utils/clipcopy.sh` (`sw_session_start`, `runledger`, `sw_ledger_list`, `sw_copy_clip`), extending the existing clipboard abstraction rather than adding a second one. Per-session and append-only, with length-prefixed records so output that mimics record delimiters cannot corrupt parsing. Index grammar: `N`, `A-B`, `N+`, or none for the final entry; invalid or out-of-range input fails safely and copies nothing.
- Added: output of a step labeled sensitive or unrecognized is never captured to the ledger, and the extractor re-checks the stored label and refuses. Command lines are not recorded.
- Added: `runledger --copy` for automatic clipboard duplication. Eligibility is decided from the risk label before the command runs, is fail-closed, and never affects terminal display or the exit status. The `AUTO_CLIPBOARD_ENABLED` session state is held by the agent and defined in the feature doc; there is no shell-side flag.
- Added: draft specs `v1/specs/clipboard/ledger-format.md` and `v1/specs/clipboard/extraction.md`, and draft feature `v1/feature/clipboard.md`.
- Changed: `v1/prompt.md` is restructured into a bounded mandatory prompt (Tier 1) with a feature index, on-demand features (Tier 2, `v1/feature/`: clipboard, inspection, context, execution, logging), and on-demand specs (Tier 3, `v1/specs/`). Loading is one-way and smallest-first, with precedence Prompt > Feature > Specs, `Framework` major.minor compatibility, resolution relative to where the prompt was loaded, and `Blocked` (never guessing) when required reference text is unavailable. 68 of the 87 non-empty prompt lines are byte-identical to 1.5.0; the Grouping, Scripts, Logging, One-Shot and Clipboard Copy text moved to features (Grouping, Scripts and the Command Construction remainder verbatim), and `docs/1.6.0-plan/prompt-migration-map.md` records every paragraph. The mandatory prompt grew about 5.5% (18,003 to 19,001 bytes) instead of shrinking; the gain is that roughly 30 KB of new capability stays out of it.
- Added: session state in the prompt: explicit, session-scoped, never persistent, with `AUTO_CLIPBOARD_ENABLED` defaulting to `false` and changed only by `sw:auto-copy/enable` and `sw:auto-copy/disable` (plan 2.1).
- Added: contextual-memory fields `session_id`, `auto_clipboard_enabled`, `ledger_path`, `next_ledger_index` and `context_loaded`, and compaction rules (state in memory, raw evidence in the ledger; unresolved warnings and failures are never compacted away) in `v1/feature/context.md` (plan Phase 4). The agent never writes the ledger, so the ledger fields come only from what the operator pastes.
- Added: a ledger session is opt-in and operator-run. Without one, steps are ordinary commands exactly as in 1.5.0, and interactive commands are never wrapped.
- Added: specs `v1/specs/context/loading-rules.md` and `v1/specs/context/size-limits.md`, with per-tier limits (prompt 20,000; feature 7,000; spec section 9,000; largest feature plus largest spec 14,000 bytes; tokens estimated at bytes/4).
- Added: `v1/utils/sw-lint.sh` (sizes, headers, Framework compatibility, index and spec reachability, one-way hierarchy, a curated list of required rules in `v1/utils/prompt-invariants.txt` (49 strings across the prompt and features), and a check that every risk label in the prompt is understood by `clipcopy.sh`) and `v1/utils/sw-lint-test.sh`, which breaks the tree 25 ways and confirms each is caught.
- Added: behavioral acceptance tests in `v1/tests/` (plan Phase 6): 16 scripted scenarios covering the gates, one step per turn, destructive and privileged confirmation, marker citation, session state, automatic copy, the sensitive-step bypass, on-demand loading, and `Blocked` on a missing reference; `sw_acceptance.py`, a standard-library runner that plays them against a model with the prompt as the system prompt and a simulated reference-fetch tool, with several samples per scenario, critical versus threshold checks, and retries; and `test_sw_acceptance.py`, which tests the harness against a mock server (including that the API key never reaches any output and that an incomplete run never reports a pass) and tests each scenario's checks against hand-written good and bad replies. That last test found and fixed a regex that could never have matched. **No real model has run the scenarios yet.**
- Added: a release gate, `v1/utils/sw-release.sh` (plan 7.2). `--check` runs the linter, linter tests, shell utility tests and harness tests, and verifies behavioral acceptance evidence against the current prompt, tiers and scenarios; it lists every unmet condition and changes nothing. `--apply` refuses unless the gate is open, then rewrites only the mechanical version strings, verifies the result, and rolls back on any failure; it never commits, tags or pushes. `v1/utils/sw-release-test.sh` covers every gate condition, the refusal, the rollback, and a safety net that catches an apply which alters hashed text (55 tests; twelve injected bugs each caught).
- Added: acceptance results now record hashes of the prompt, the tiers and the scenarios, plus whether the run was complete. `sw_acceptance.py --hash` prints them and `--verify-evidence DIR` checks recorded results against the current text: stale, partial, under-sampled, lowered-threshold or failing results do not count, while a version bump does not invalidate them. 24 more harness tests (61 in all).
- Added: `docs/1.6.0-plan/compatibility.md` (the 1.5.0 to 1.6.0 differences, deliberate behavior changes, migration by audience, and the release process) and `v1/tests/results/README.md`.
- Added: `sw-release.sh --waive-evidence "REASON"`, for a maintainer who decides to release before acceptance results are recorded. It waives only the absence of recorded results: every other gate condition still applies, it cannot hide a recorded result that fails or is unusable, the reason is required and is written into the CHANGELOG with the statement that no recorded results match the release, and it never creates an evidence file. If valid evidence exists the waiver is ignored. 92 release tests (37 new); nine injected bugs in the waiver logic are each caught.
- Fixed: in `sw-release.sh`, an option that takes a value (`--version`, `--date`, `--min-models`, `--min-samples`, `--evidence`) given with no value made the argument loop spin forever, because `shift 2` fails with one argument left. They now fail with a usage error, and the tests run those cases under a timeout so a regression cannot hang the suite.
- Fixed: two compiled `.pyc` files were committed by accident; they are untracked and a `.gitignore` was added.
- Fixed: the ledger examples in `feature:clipboard` and `feature:inspection` showed `--objective="..." --step="..."` in double quotes. Those strings sit inside the shell command the operator runs, so a backtick or `$(...)` in an objective (a normal thing to write) would have executed at the operator's shell. Both features now require single quotes, plain words, no `'`, backtick, `$`, backslash or newline, and say never to paste text from output, files or the task into them. They also now spell out the exact `--risk` label vocabulary, since an unrecognized label silently means "no copy". Guarded by six new lint rules and tests (25 lint mutations in all), by a lint check that every label taught to the model is understood by `clipcopy.sh`, and by a new critical acceptance scenario, `ledger-metadata-quoting`.
- Fixed: the earlier draft of `v1/feature/clipboard.md` assumed every step goes through `runledger`, which would fail for any operator without the helper functions. Manual mode now gives ordinary commands unless a ledger session is active, and the 1.5.0 `runcopy` rules (per-invocation opt-in, `--no-copy`, mention rather than assume) are restated there so removing the prompt paragraph loses nothing.
- Added: `v1/utils/clipcopy-test.sh`, a hermetic suite (stub clipboard, temporary state directory) covering the bypass, ledger, extraction grammar, and `--copy`.
- Added: the three-part 1.6.0 implementation plan under `docs/1.6.0-plan/`.
- Changed: `README.md` documents the fail-closed bypass, the ledger as a preview, and the context tiers; its status line notes that 1.6.0 is in progress. Automatic copy is a deliberate change from 1.5.0's "never automatic"; it stays off by default.
- Pending for 1.6.0: running the acceptance scenarios against one or more real models, committing the results, and acting on what they show; then `sw-release.sh --apply`, the README edits it lists, and the tag; the token-accurate size measurement with the real tokenizer; and the example transcript.

## 1.5.0

- Fixed: the step-header placeholder `` `Step N — <goal>` `` is now an inline code span. Previously, written unfenced, `<goal>` parsed as a bare HTML tag on render and silently disappeared from every step header (verified against the rendered GitHub page).
- Fixed: `Risk:` line in the step format now says `credential/privileged-data`, matching the combined label used in **Safety** and **Clipboard Copy** — previously it listed `credential` alone, a drifted/inconsistent label for the same risk class.
- Fixed: the `v1/prompt.md` reference to the clipboard-copy script now points at its actual path, `v1/utils/clipcopy.sh`, instead of a bare filename that didn't resolve to anything in the repo.
- Fixed: **Clipboard Copy** described requesting a copy by "passing `--copy`" — a flag `v1/utils/clipcopy.sh` doesn't implement (the script copies by default; `--no-copy` opts out). Section now matches the script's actual interface.
- Added: version line at the top of `v1/prompt.md` so raw-URL consumers can see which revision they're pinned to.
- Changed: `README.md`'s condensed initial-invocation prompt reconciled with the full protocol — added the Objective Clarification Gate, Completeness Criteria Wizard (including the `skip`-is-invalid rule), the `credential/privileged-data` risk label, `[n]`-marker citation on mismatch, and the opt-in clipboard-copy note, all of which existed in `v1/prompt.md` but were missing from the condensed version.
- Added: "Manual Workflow: Clipboard Copy" section in `README.md` documenting the source → `runcopy` → `--no-copy` → self-test sequence.
- Added: this changelog, and a `README.md` status line pointing to it.
- Added: `v1/examples/` with a pending-status placeholder — no worked transcript exists yet; this is tracked explicitly rather than left silently absent.

## 1.4.0 — Annotated Output Blocks

- Step format's `Expected output:` is now a fenced `BEGIN EXPECTED` / `END EXPECTED` block with numbered, annotated lines (`[1]`, `[2]`, ...).
- **Output Validation** updated: mismatches must cite the specific `[n]` marker(s) that failed, not free-form prose alone.

## 1.3.0 — Shell-Side Output Auto-Copy

- Added **Clipboard Copy (Opt-In)** section: per-invocation, never automatic, never replaces terminal display.
- Added `credential/privileged-data` as a risk label in **Safety**; steps under this label auto-bypass clipboard copy with an explicit notice.
- Added reference implementation `runcopy` (`v1/utils/clipcopy.sh`): backend priority `termux-clipboard-set` → `xclip` → `pbcopy` → `clip.exe`, `--no-copy` per-invocation skip, `--risk=` bypass, and a self-test (`sw_selftest_clipboard_bypass`).

## 1.2.0 — Completeness Criteria Scaffolding Wizard

- Added **Completeness Criteria Wizard**: triggers once the Objective is confirmed and no CompletenessCriteria exist; proposes 2–6 candidate criteria labeled by evidence type (`shell-output | artifact | human-confirmation-only`).
- `skip` explicitly disallowed on this step — the only step in the protocol where a skip request is refused outright.
- **Completion** now measures done-ness against the confirmed CompletenessCriteria list rather than "the final command succeeded."

## 1.1.0 — Objective Clarification Gate

- Added **Objective Clarification Gate** between **Intake** and **Discovery**: tests the raw task against "concrete target + observable success condition"; concrete tasks pass through with a one-line restatement, ambiguous ones get a capped (≤3 question) clarification exchange and require explicit operator confirmation before Discovery begins.
- **State Progression** gained an `Objective-Confirmed` state.

## 1.0.0 — Baseline

- Original protocol: Role, Execution Model, Human Boundary, Intake, Discovery, Baseline, Functional Steps, Stepwise Interaction, and the full set of behavioral rules (Grouping through Start), prior to any of the `1.1.0`–`1.5.0` additions above.
