StepWise 1.6.0 — Implementation Plan
Part 1 of 3 — Context Architecture (Phases 0–2)

This is one of three synchronized parts of the restructured 1.6.0 implementation plan. Phase numbers are preserved as-is across all three files — nothing is renumbered — so a reference like "Phase 3.4" always means the same thing regardless of which document you're reading.

- Part 1 — Context Architecture (Phases 0–2): this document. Freezing the baseline, the three-tier Prompt/Feature/Specs system, and the session-state model everything else depends on.
- Part 2 — Clipboard, Ledger & Memory (Phases 3–4): `sw-1.6.0-upgrade-02-IMPLEMENTATION.md`. The clipboard subsystem redesign, the session ledger, and contextual-memory integration.
- Part 3 — Workflow, Verification & Release (Phases 5–7 + Appendix A): `sw-1.6.0-upgrade-03-VERIFICATION.md`. The integrated final architecture, acceptance tests, the v1.5.0→1.6.0 compatibility table, and a source-stage traceability map.

**Correction applied throughout this plan set:** the raw source material referred to this work as "v2.0" and called for a new `stepwise-v2-prompt.md` artifact under a top-level `stepwise/` tree. Per the established StepWise versioning policy (internal `1.x` only until the framework is fully tested — see `CHANGELOG.md`), this is a **1.5.0 → 1.6.0** upgrade. It continues to live at `v1/prompt.md` (version-bumped in place) with new `v1/feature/` and `v1/specs/` directories alongside the existing `v1/utils/clipcopy.sh`. Every "2.0" in the source drafts has been replaced with "1.6.0" below; see Phase 7.2 for the explicit release-gate statement.

**Deduplication applied:** the two source files contained several stages repeated near-verbatim (the source material's own stages 19–25 reappear, sometimes in a more refined form, as stages 28–35). Those have been merged into single sections below rather than reproduced twice — see Appendix A in Part 3 for the full stage-to-section mapping.

---

## Phase 0 — Baseline

### 0.1 Freeze the v1.5.0 Contract

**Purpose:** establish exactly what 1.6.0 is upgrading.

The current `v1/prompt.md` (`1.5.0`) already defines:

- human execution boundary
- Objective Clarification Gate
- Completeness Criteria
- Discovery and Baseline
- functional-step interaction
- numbered expected-output markers
- output validation
- state progression
- adaptive planning
- safety classifications
- privileged/destructive/network controls
- contextual memory
- optional logging
- opt-in clipboard behavior
- one-shot mode
- completion and final-summary requirements

**Upgrade rule:** 1.6.0 must preserve these behavioral guarantees unless a later phase explicitly supersedes one.

**Required artifact:** the existing `v1/prompt.md`, with its `Version:` header bumped to `1.6.0` once Phases 1–6 are implemented and the Phase 6 tests pass. *(Source drafts called for a new `stepwise-v2-prompt.md`; corrected per the versioning note above — there is no new prompt file, only a version bump to the one that already exists.)*

The current `v1/prompt.md` (`1.5.0`) is the baseline contract against which 1.6.0 behavior is checked.

---

## Phase 1 — Context Tier Architecture

This phase is more fundamental than the clipboard work in Phase 3, and everything downstream depends on it.

### 1.1 Three-Tier Model

StepWise becomes a three-tier context system:

```
STEPWISE AGENT
                          │
                          ▼
                 ┌─────────────────┐
                 │  1. PROMPT      │
                 │  Mandatory      │
                 │  Normal-size cap│
                 └────────┬────────┘
                          │
                  needs more information?
                          │
                          ▼
                 ┌─────────────────┐
                 │  2. FEATURE     │
                 │  On demand      │
                 │  Normal-size cap│
                 └────────┬────────┘
                          │
                  needs implementation
                  / protocol detail?
                          │
                          ▼
                 ┌─────────────────┐
                 │  3. SPECS       │
                 │  On demand      │
                 │  Higher cap     │
                 │  Sectional      │
                 └─────────────────┘
```

**Tier 1 — Prompt.** Mandatory on every StepWise session. Contains only the stable operational contract required for the agent to behave correctly: role; human execution boundary; core principles; mandatory gates; functional-step model; safety rules; validation rules; context escalation rules; session-state semantics; completion requirements. It should not contain extensive implementation detail.

**Tier 2 — Feature.** Loaded only when the agent needs information about a particular StepWise feature. Lives at `v1/feature/`:

```
v1/feature/
    clipboard.md
    context.md
    inspection.md
    session-state.md
    logging.md
    execution.md
    safety.md
```

The prompt says, conceptually: *"For additional information about a feature, load the corresponding Feature specification."*

**Tier 3 — Specs.** Detailed sectional reference material. Lives at `v1/specs/`:

```
v1/specs/
    clipboard/
        ledger-format.md
        extraction.md
        platform-support.md

    context/
        loading-rules.md
        size-limits.md
        escalation.md

    execution/
        step-format.md
        validation.md
        state-machine.md
```

This tier contains implementation-level detail, edge cases, schemas, examples, compatibility rules, and detailed algorithms.

**Critical rule — strictly hierarchical dependency:**

```
Prompt
  └── Feature
       └── Specs
```

Not:

```
Prompt ─────► Specs
Feature ────► unrelated Feature
Specs ──────► Prompt
```

This prevents context leakage and circular dependencies.

### 1.2 Context Loading and Escalation Rules

The three tiers alone aren't enough — 1.6.0 needs an explicit context-loading contract.

**Mandatory behavior.** The agent always receives `PROMPT`. It may request `PROMPT → FEATURE` when the prompt does not contain enough information. A feature may request `FEATURE → SPECS` when implementation/reference detail is required.

**Prohibited behavior.** The agent must not automatically load the entire feature or specs corpus. The intended behavior is:

```
Need → identify missing information → load smallest relevant context → continue
```

rather than:

```
Need anything → load everything
```

**Important refinement.** Context should be section-addressable, not merely file-addressable:

```
feature:clipboard
spec:clipboard/ledger-format
spec:clipboard/extraction
```

is preferable to requiring the agent to load an entire large document merely because it needs one rule.

### 1.3 Context Budgets

The context budget must apply **independently to each tier**:

- Prompt: fixed maximum
- Feature: fixed maximum per loaded feature
- Specs: larger maximum per requested section

Do not define the budget merely as a static file-size limit — there are three different measurements:

1. source file size
2. serialized context size
3. actual model-token consumption

The third is the operationally important measurement. Therefore 1.6.0 establishes:

```
Source size ≠ context size ≠ token cost
```

The implementation should measure or estimate the serialized context actually supplied to the model.

**Recommended invariant:** the session should normally operate with **Prompt only**, and escalate only when required. This directly supports keeping StepWise's footprint bounded.

### 1.4 Context Precedence

Once information is split across three levels, contradictions become possible, so 1.6.0 needs a precedence rule:

```
Prompt = normative behavioral contract
Feature = feature-specific behavioral definition
Specs = detailed implementation/reference material
```

If they conflict:

```
Prompt > Feature > Specs
```

unless the Prompt explicitly delegates a rule to the lower layer. This matters because otherwise an agent could load a detailed specification that accidentally overrides a safety rule in the mandatory prompt.

### 1.5 Context Retrieval Decision Procedure

The retrieval hierarchy:

```
1. Mandatory Prompt
       │
       ▼
2. Can the current task be completed?
       │
       ├── yes → proceed
       │
       └── no
            ↓
       load relevant Feature
            │
            ▼
       can task now be completed?
            │
            ├── yes → proceed
            │
            └── no
                 ↓
             load relevant Spec section
```

This is an explicit 1.6.0 rule. The agent must not load Tier 3 simply because Tier 3 exists — the smallest sufficient context should be loaded.

### 1.6 Feature/Spec Discovery Layout

There needs to be a deterministic way for the agent to know what exists:

```
v1/
├── prompt.md              (Tier 1 — mandatory; version-bumped in place)
├── feature/                (Tier 2)
│   ├── clipboard.md
│   ├── context.md
│   └── inspection.md
└── specs/                  (Tier 3)
    ├── clipboard/
    ├── context/
    └── inspection/
```

*(Source drafts sketched this as a top-level `stepwise/` tree with `prompt/stepwise-v2.md`; corrected here to the repo's actual `v1/` layout, per the versioning note above.)*

The mandatory prompt contains the feature index. The feature contains its available detailed specs. That allows progressive disclosure without requiring the model to know the entire filesystem.

A feature should therefore have a compact specification map, e.g.:

```
Feature: Clipboard
Detailed references:
- ledger-format
- extraction
- platform-support
- safety
```

The agent can then request only the section it needs.

### 1.7 Per-Tier Versioning

Every tier should have explicit version compatibility:

```
StepWise Framework: 1.6.0
Prompt:             1.6.0
Feature Clipboard:  1.6.0
Spec Clipboard:     1.6.0
```

A feature/spec incompatible with the mandatory prompt must not silently load. This becomes particularly important as the framework evolves independently. At minimum, each reference component should identify: framework version; component version; dependency/compatibility information; supersession status, if applicable.

### 1.8 Missing-Context Failure Behavior

If a required feature/spec cannot be loaded:

```
State = Blocked
```

not:

```
Agent guesses
```

This follows the existing v1.5.0 principle that unresolved failures must not be silently bypassed. The agent should effectively report:

> Required reference information is unavailable. I will not infer the missing protocol rule.

and stop or request the missing context. Likewise, if a loaded Feature explicitly states that a deeper Spec is required, the agent must not invent the missing detail from general knowledge.

### 1.9 Context Footprint Contract

*(Merge note: the source drafts contained three overlapping versions of this contract. The version below combines the most evolved invariant table — the one that already accounts for the Session Ledger introduced in Phase 3 — with the measurable-limits requirement that only appeared in one of the three drafts. See Appendix A, Part 3, for the exact source mapping.)*

This is an explicit architectural objective:

> StepWise minimizes persistent model context by keeping the mandatory prompt bounded and loading feature/specification information progressively only when required.

The invariant:

```
Prompt:            always loaded, bounded
Feature:           loaded only when needed, bounded
Specs:             loaded only when needed, sectional, higher cap
Contextual Memory: compact current state
Session Ledger:    external historical evidence
```

This is considerably stronger than simply saying "average KB per session."

The framework should define measurable limits for:

- mandatory prompt size
- individual feature size
- individual specification-section size
- maximum simultaneously loaded optional context
- contextual-memory size
- total session context target

The target should be expressed in tokens or an explicitly defined serialized-context measurement, with KB retained as a secondary engineering metric.

---

## Phase 2 — Session State Model

### 2.1 Session-Scoped State

The proposed `sw:auto-copy/enable` / `sw:auto-copy/disable` commands should not be treated as arbitrary prompt keywords. Make this an explicit session state:

```
AUTO_CLIPBOARD_ENABLED=false   (default)
```

Commands:

```
sw:auto-copy/enable
sw:auto-copy/disable
```

change only that session state.

**Critical distinction:** this state must **not** become persistent configuration. It means *current StepWise session only* — not future sessions, not shell configuration, not global StepWise configuration. The state resets when the StepWise session ends.

---

End of Part 1 (Phases 0–2). Continue with Part 2 — Clipboard, Ledger & Memory (`sw-1.6.0-upgrade-02-IMPLEMENTATION.md`), Phase 3 — Clipboard & Ledger Subsystem.
