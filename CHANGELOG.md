# Changelog

All notable changes to the StepWise protocol are recorded here.

**Versioning policy:** StepWise is pre-release. All changes are tracked as `1.x` (minor/patch) revisions of the same generation, regardless of how large the change is. The project moves to `2.0.0` only once the framework has been fully tested end-to-end (see the pending example transcript in `README.md`). Do not interpret any `1.x` bump below as a stability signal beyond "this changed."

## Unreleased — 1.6.0 (in progress)

**Not a release.** `v1/prompt.md` is still `1.5.0`. Per the plan in `docs/1.6.0-plan/` (section 7.2), the version bumps to `1.6.0` only after the Phase 6 acceptance tests pass. Everything below exists in `v1/utils/`, `v1/specs/`, and `v1/feature/`, but the prompt does not load or use it yet.

- Fixed: `runcopy`'s clipboard bypass failed open. It matched only the exact strings `credential` and `privileged-data`, so the combined label `credential/privileged-data` (unified in 1.5.0), case variants, and any unrecognized label fell through to the copy path. It is now fail-closed: only known non-sensitive labels may copy; sensitive or unrecognized labels bypass with a notice. Repeated `--risk` flags accumulate (a later benign label cannot override an earlier sensitive one), an empty `--risk=` is unrecognized, and `--risk` with no value is an error. Omitting `--risk` keeps the 1.5.0 manual-copy behavior. Self-test extended to cover the combined label and unknown labels.
- Added: session ledger in `v1/utils/clipcopy.sh` (`sw_session_start`, `runledger`, `sw_ledger_list`, `sw_copy_clip`), extending the existing clipboard abstraction rather than adding a second one. Per-session and append-only, with length-prefixed records so output that mimics record delimiters cannot corrupt parsing. Index grammar: `N`, `A-B`, `N+`, or none for the final entry; invalid or out-of-range input fails safely and copies nothing.
- Added: output of a step labeled sensitive or unrecognized is never captured to the ledger, and the extractor re-checks the stored label and refuses. Command lines are not recorded.
- Added: `runledger --copy` for automatic clipboard duplication. Eligibility is decided from the risk label before the command runs, is fail-closed, and never affects terminal display or the exit status. The `AUTO_CLIPBOARD_ENABLED` session state is held by the agent and defined in the feature doc; there is no shell-side flag.
- Added: draft specs `v1/specs/clipboard/ledger-format.md` and `v1/specs/clipboard/extraction.md`, and draft feature `v1/feature/clipboard.md`.
- Added: `v1/utils/clipcopy-test.sh`, a hermetic suite (stub clipboard, temporary state directory) covering the bypass, ledger, extraction grammar, and `--copy`.
- Added: the three-part 1.6.0 implementation plan under `docs/1.6.0-plan/`.
- Changed: `README.md` documents the fail-closed bypass and the ledger as a preview, and its status line notes that 1.6.0 is in progress. Automatic copy is a deliberate change from 1.5.0's "never automatic"; it stays off by default and inactive until the prompt adopts it.
- Pending for 1.6.0: restructuring the prompt into the Prompt/Feature/Specs tiers with a feature index (Phase 1); prompt-level adoption of the session state and the `sw:auto-copy/enable` and `sw:auto-copy/disable` commands; `v1/feature/inspection.md`; the contextual-memory fields (Phase 4); the prompt-level acceptance and regression tests (Phase 6); and the example transcript.

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
