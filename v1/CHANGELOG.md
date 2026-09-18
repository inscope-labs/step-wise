# Changelog

All notable changes to the StepWise protocol are recorded here.

**Versioning policy:** StepWise is pre-release. All changes are tracked as `1.x` (minor/patch) revisions of the same generation, regardless of how large the change is. The project moves to `2.0.0` only once the framework has been fully tested end-to-end (see the pending example transcript in `README.md`). Do not interpret any `1.x` bump below as a stability signal beyond "this changed."

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
