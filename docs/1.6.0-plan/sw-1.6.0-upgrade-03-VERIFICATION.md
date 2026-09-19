StepWise 1.6.0 — Implementation Plan
Part 3 of 3 — Workflow, Verification & Release (Phases 5–7 + Appendix A)

This is one of three synchronized parts of the restructured 1.6.0 implementation plan. Phase numbers are preserved as-is across all three files.

- Part 1 — Context Architecture (Phases 0–2): `sw-1.6.0-upgrade-01-ARCHITECTURE.md`. The three-tier Prompt/Feature/Specs system and the session-state model.
- Part 2 — Clipboard, Ledger & Memory (Phases 3–4): `sw-1.6.0-upgrade-02-IMPLEMENTATION.md`. The clipboard subsystem, session ledger, and contextual-memory integration.
- Part 3 — Workflow, Verification & Release (Phases 5–7 + Appendix A): this document. How everything from Parts 1–2 fits into one operational flow, how it gets tested, and how the release is gated.

---

## Phase 5 — Workflow Integration & Final Architecture

### 5.1 Integrated Operational Flow

The final 1.6.0 operational model:

```
TASK
  ↓
OBJECTIVE GATE
  ↓
COMPLETENESS CRITERIA
  ↓
PROMPT-ONLY EXECUTION
  ↓
Need feature information?
  ├── No ────────────────┐
  └── Yes → LOAD FEATURE │
                         ↓
                 Need detailed spec?
                   ├── No
                   └── Yes → LOAD SPEC
                         ↓
                 EXECUTION MODE
                         ↓
              Risk / Clipboard Decision
                         ↓
                  Execute Step
                         ↓
                Terminal Output
                   ↙          ↘
             Validation       Ledger
                                  ↓
                          Human Inspection
                                  ↓
                       Optional Copy Selection
                                  ↓
                         State Update
                                  ↓
                         Next Functional Step
```

The important ordering: **context → execution rules → risk classification → execution → evidence → optional clipboard extraction → state update.**

### 5.2 Final Five-Layer Architecture

The resulting StepWise 1.6.0 architecture is five cooperating layers:

```
┌──────────────────────────────────────────────┐
│ 1. PROMPT                                     │
│    Mandatory / bounded contract               │
└──────────────────────┬───────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────┐
│ 2. FEATURES                                   │
│    On-demand behavioral information           │
└──────────────────────┬───────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────┐
│ 3. SPECS                                      │
│    On-demand detailed references              │
└──────────────────────┬───────────────────────┘
                        │
         ┌──────────────┴──────────────┐
         ▼                              ▼
┌─────────────────────┐      ┌─────────────────────┐
│ 4. CONTEXT MEMORY    │      │ 5. SESSION LEDGER    │
│    Compact current   │      │    Raw historical    │
│    operational state │      │    execution evidence│
└─────────────────────┘      └──────────┬──────────┘
                                          │
                                          ▼
                              Human-selected extraction
                                          │
                                          ▼
                               System clipboard
```

This produces a clean separation:

- **Prompt** = rules
- **Feature** = capability knowledge
- **Specs** = detailed reference
- **Context Memory** = current state
- **Ledger** = historical evidence
- **Clipboard** = explicitly selected transport

*(This is the authoritative architecture diagram for the release — it supersedes the initial three-tier sketch in Part 1 §1.1 by formally adding Context Memory and Session Ledger as first-class layers 4–5. §1.1 describes the context-loading tiers in isolation; this is the complete system including state and evidence.)*

---

## Phase 6 — Verification & Acceptance Tests

The final implementation phase tests the framework itself. None of Phases 1–5 are considered done until their corresponding tests below pass.

### 6.1 Context Tests

- Prompt works independently.
- Prompt can identify when Feature information is required.
- Feature can identify when Specs are required.
- Specs are not loaded unnecessarily.
- Missing Specs produce `Blocked`, not guessing.
- Context remains within defined limits.

### 6.2 Clipboard Tests

- default session = disabled
- enable persists for current session
- disable restores manual behavior
- sensitive step bypasses automatic copy
- sensitive step also bypasses explicit copy
- terminal output remains intact
- manual ledger extraction works
- single index works
- closed range works
- open range works
- default selects final entry
- invalid indexes fail safely
- missing ledger fails safely

### 6.3 Ledger Tests

- index increments correctly
- entries cannot accidentally overwrite previous entries
- session isolation works
- malformed records are handled
- empty output is represented correctly
- non-zero command status is retained
- multiline output is preserved

### 6.4 Regression Tests — v1.5.0 Guarantees

All existing v1.5.0 guarantees must remain intact:

- objective gate
- completeness criteria
- human execution boundary
- one functional step per turn
- validation
- adaptive planning
- safety
- destructive-operation confirmation
- privileged-operation confirmation
- final completeness verification

---

## Phase 7 — Compatibility, Migration & Release Gate

### 7.1 v1.5.0 → 1.6.0 Differences

*(Merge note: the source drafts contained near-duplicate versions of this table with slightly different wording. The version below uses the more refined phrasing from the later draft — "manual mode" and "retained and strengthened" — as canonical; see Appendix A.)*

| Area | v1.5.0 | 1.6.0 |
|---|---|---|
| Prompt | monolithic | mandatory bounded prompt |
| Feature information | embedded | on-demand |
| Detailed specs | embedded/implicit | sectional on-demand |
| Clipboard | per-invocation `runcopy` | session auto-copy + manual mode |
| Sensitive steps | clipboard bypass | retained and strengthened |
| Output history | optional logging | session ledger |
| Copy selection | direct invocation | indexed ledger extraction |
| Context memory | operational state | operational state + context-tier state |
| Raw output | chat/session | terminal + ledger |
| Context loading | static | progressive |
| Session state | implicit | explicit |

The v1.5.0 clipboard mechanism is specifically documented as per-invocation opt-in, so this migration must be treated as a deliberate, explicitly-flagged behavioral change — not an implementation detail.

### 7.2 Release / Versioning Policy

Per the established StepWise versioning policy: **1.6.0 stays within the internal `1.x` series.** It does not become `2.0` merely because this is architecturally a large change — `2.0` is reserved for after the framework has been fully tested end-to-end (see the pending example-transcript requirement already tracked in `v1/examples/README.md`).

Concretely, for this release:

- Bump the `Version:` line in `v1/prompt.md` to `1.6.0` once Phases 1–6 above are implemented and the Phase 6 tests pass.
- Add a `1.6.0` entry to `CHANGELOG.md` describing the changes in Phases 1–5, mirroring the existing `1.1.0`–`1.5.0` entries.
- Do not create a `stepwise-v2-prompt.md` or any `v2/` directory as part of this work.
- The compatibility table in §7.1 above is the "document the differences from v1" deliverable the source material called for — here that means v1.5.0, the immediately preceding version, not some unversioned "v1."

---

## Appendix A — Source Stage Mapping

For traceability back to the two raw source files (`sw-1_6_0-upgrade-part-1.txt`, `sw-1_6_0-upgrade-part-2.txt`).

| Source stage(s) | New section | Note |
|---|---|---|
| P1 Stage 1 | 0.1 | |
| P1 Stage 2 | 1.1 | |
| P1 Stage 3 | 1.2 | |
| P1 Stage 4 | 1.3 | |
| P1 Stage 5 | 1.4 | |
| P1 Stage 6 | 2.1 | |
| P1 Stage 7 | 3.1 | |
| P1 Stage 8 | 3.2 | |
| P1 Stage 9 | 3.3 | |
| P1 Stage 10 | 3.4 | |
| P1 Stage 11 | 3.5 | |
| P1 Stage 12 | 3.6 | |
| P1 Stage 13 | 3.7 | |
| P1 Stage 14 | 3.8 | |
| P1 Stage 15 | 3.9 | |
| P1 Stage 16 | 3.10 | |
| P1 Stage 17 | 4.1 | |
| P1 Stage 18 | 4.2 | |
| P1 Stage 19 / P2 Stage 29 | 1.5 | Duplicate — merged |
| P1 Stage 20 / P2 Stage 30 | 1.6 | Duplicate — merged |
| P1 Stage 21 / P2 Stage 31 | 1.7 | Duplicate — merged |
| P1 Stage 22 / P2 Stage 32 | 1.8 | Duplicate — merged |
| P1 Stage 23 / P2 Stage 33 | 5.1 | Duplicate — merged |
| P1 Stage 24 / P2 Stage 28 / P2 Stage 34 | 1.9 | Three overlapping drafts — merged; canonical invariant table taken from Stage 34 (the ledger-inclusive version), measurable-limits list taken from Stage 28 |
| P1 Stage 25 / P2 Stage 27 / P2 Stage 35 | 7.1 | Three overlapping drafts — merged; wording taken from Stage 35 (most refined) |
| P2 Stage 26 | Phase 6 (6.1–6.4) | New — not present in Part 1 |
| P2 Stage 36 | 5.2 | New — not present in Part 1 |
| — | 7.2 | New — versioning-policy correction, not in either source file |
