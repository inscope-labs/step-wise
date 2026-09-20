# StepWise 1.5.0 to 1.6.0: compatibility, migration and release

Plan Phase 7. This is the "document the differences" deliverable of 7.1, written against what is actually in the repository, plus the release process for 7.2.

**Status.** `v1/prompt.md` is `1.6.0-dev`. It is not released, and no real model has run the acceptance scenarios yet.

## 1. What changed

| Area | 1.5.0 | 1.6.0-dev |
|---|---|---|
| Prompt | monolithic, 18,003 bytes | bounded mandatory prompt, 19,001 bytes (5.5% larger) |
| Feature information | embedded in the prompt | on demand: `feature:clipboard`, `inspection`, `context`, `execution`, `logging` |
| Detailed specs | embedded or implicit | on demand, one section at a time: `spec:clipboard/*`, `spec:context/*` |
| Clipboard | per-invocation `runcopy` only | manual mode (unchanged) plus an optional, session-scoped automatic mode |
| Sensitive steps | clipboard bypass | retained and strengthened: fail-closed labels, both modes, output never captured in the ledger |
| Output history | optional logging | logging retained, plus an opt-in session ledger |
| Copy selection | direct invocation | indexed ledger extraction with `sw_copy_clip` |
| Context memory | operational state | operational state plus `session_id`, `auto_clipboard_enabled`, `ledger_path`, `next_ledger_index`, `context_loaded`, and compaction rules |
| Raw output | chat and terminal | terminal, plus the ledger when a session is active |
| Context loading | static | progressive, smallest sufficient first |
| Session state | implicit | explicit, session-scoped, never persistent |

The mandatory prompt did **not** shrink. The gain is that roughly 30 KB of new capability stays out of it. Paragraph-by-paragraph accounting is in [`prompt-migration-map.md`](prompt-migration-map.md).

## 2. Behavior changes to be aware of

These are deliberate. Each is also in the CHANGELOG.

1. **Automatic clipboard mode exists.** 1.5.0 said clipboard copy is never automatic. It is still **off by default** and starts off every session; `sw:auto-copy/enable` turns it on for the current session only.
2. **The bypass is fail-closed.** In 1.5.0's `clipcopy.sh`, only the exact strings `credential` and `privileged-data` bypassed the copy; the protocol's own label `credential/privileged-data`, case variants, and any unknown label were copied. Now only known non-sensitive labels may copy. This affects anyone who called `runcopy --risk=<something unusual>` and relied on it copying.
3. **Features and specs load on demand.** An assistant that can neither fetch a file nor be given it by paste reports `Blocked` for whatever needs it, and does not guess. The core protocol (gates, one step per turn, validation, safety) works from the prompt alone.
4. **A ledger session is opt-in.** Without one, steps are ordinary commands exactly as in 1.5.0. Interactive programs are never wrapped.

## 3. What does not change

The objective and completeness gates, one functional step per turn, numbered expected-output markers and `[n]` citations, output validation, state progression, adaptive planning, destructive and privileged confirmation, and the rule that shell output is primary evidence. 68 of the prompt's 87 non-empty lines are byte-identical to 1.5.0, and a linter checks that 43 required rule strings are still present in the prompt (and 6 more in the features). That proves the text is there, not that a model follows it. The acceptance scenarios exist to measure that.

## 4. Migration by audience

- **You load the prompt from the `main` URL.** Nothing to do, but you now get the tiered prompt. To keep the old behavior, pin `1.5.0`: features and specs resolve relative to where the prompt was loaded from, so a pinned copy loads pinned references. Tag the last `1.5.0` commit (`4d90c06`) if you want a stable name for it.
- **You integrate StepWise into another assistant** (a custom system prompt, an agent framework). Serve `feature/` and `specs/` next to `prompt.md`, and give the assistant a way to fetch them, or accept that it will ask the operator to paste them. Pasting the prompt alone works, with the limits in section 2.
- **You use `runcopy` today.** No change, except the fail-closed labels in section 2. The wrapper is otherwise the same.
- **You want the ledger.** `source v1/utils/clipcopy.sh`, then `sw_session_start`, and paste the two notices it prints into the conversation. Steps then use `runledger`. See the README's Session Ledger section.
- **You want automatic copy.** Enable it with `sw:auto-copy/enable`. It copies by risk label alone, so a non-sensitive command that prints something sensitive will be copied. Manual mode plus ledger inspection keeps a person as the last gate.

## 5. Version compatibility rule

A feature or spec loads only if its `Framework` major.minor equals the prompt's `Version` major.minor. `1.6.0-dev` and `1.6.0` are compatible; `1.5.x` and `1.7.x` are not. Details: [`v1/specs/context/loading-rules.md`](../../v1/specs/context/loading-rules.md).

## 6. Releasing 1.6.0 (plan 7.2)

The release stays in the 1.x series. Do not create `stepwise-v2-prompt.md` or a `v2/` directory; the gate refuses if either exists.

1. Run the scenarios against at least one real model (two is better; raise `--min-models`) and commit the results under `v1/tests/results/`. See that directory's README.
2. `bash v1/utils/sw-release.sh --check` runs the linter, the linter tests, the shell utility tests and the harness tests, and verifies the evidence against the current text. It changes nothing and lists every unmet condition.
3. `bash v1/utils/sw-release.sh --apply --version 1.6.0` re-runs that gate. If it is open, it rewrites only the mechanical version strings (the prompt's `Version` line, the `Framework`, `Version` and `Status` rows of each feature and spec, and the CHANGELOG heading), verifies the result, and rolls back on any failure. It never commits, tags, or pushes.
4. By hand: update the README's status line and "In progress" paragraph, and rename the "(1.6.0-dev)" and "(1.6.0 preview)" headings and their anchors. Review the diff, commit, tag `v1.6.0`, and push.

Editing the prompt, a feature, a spec or a scenario after recording evidence makes that evidence stale. Re-run before releasing.

**Releasing without recorded evidence.** If a maintainer decides to release before results are recorded, `--check` and `--apply` accept `--waive-evidence "REASON"`. It waives only the *absence* of recorded results. Every other condition still applies, and it cannot hide a recorded result that fails, is partial, or is unreadable (re-run or remove those). The reason is required, is printed, and is written into the CHANGELOG together with the statement that no recorded results match the release, "a known gap, not a passing result". It never creates an evidence file. If valid evidence exists the waiver is ignored and nothing is recorded. Use of the waiver is the maintainer's decision and is visible in the release notes; the gate itself stays in place for the next release.

**After a release.** Start the next cycle by setting the prompt's Version line to the next `X.Y.Z-dev` and adding an Unreleased section to the CHANGELOG; the gate expects both.

## 7. Known limitations

- Nothing here has been run against a real model. Every behavioral claim is unmeasured until step 1 above happens.
- The ledger helpers were tested on bash 5.2 on Linux only, not on Termux or macOS bash 3.2.
- Token figures are an estimate (bytes divided by 4), not a tokenizer measurement.
- The evidence check guards against accident, not against someone editing a results file by hand.
- The acceptance runner speaks the Anthropic Messages API only.
