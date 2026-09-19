StepWise 1.6.0 — Implementation Plan
Part 2 of 3 — Clipboard, Ledger & Memory (Phases 3–4)

This is one of three synchronized parts of the restructured 1.6.0 implementation plan. Phase numbers are preserved as-is across all three files.

- Part 1 — Context Architecture (Phases 0–2): `sw-1.6.0-upgrade-01-ARCHITECTURE.md`. Read this first — it defines the three-tier Prompt/Feature/Specs system and the session-state model this document builds on.
- Part 2 — Clipboard, Ledger & Memory (Phases 3–4): this document. The clipboard subsystem redesign, the session ledger, and contextual-memory integration.
- Part 3 — Workflow, Verification & Release (Phases 5–7 + Appendix A): `sw-1.6.0-upgrade-03-VERIFICATION.md`. The integrated final architecture, acceptance tests, the compatibility table, and the source-stage traceability map.

---

## Phase 3 — Clipboard & Ledger Subsystem

This is where the original proposal needed the most correction.

### 3.1 Clipboard Modes

The v1.5.0 contract currently says clipboard copying is:

> opt-in per invocation

through `runcopy` (`v1/utils/clipcopy.sh`), rather than automatic. The 1.6.0 proposal changes that to `AUTO_CLIPBOARD_ENABLED=true` with automatic clipboard piping. That is a legitimate 1.6.0 change, but it must be explicitly modeled as a new execution mode, not merely a replacement sentence.

Recommended modes:

- `AUTO_CLIPBOARD_ENABLED=false` → manual mode
- `AUTO_CLIPBOARD_ENABLED=true` → automatic-copy mode for eligible steps
- `credential/privileged-data` → mandatory clipboard bypass, in either mode

This makes the state machine explicit.

### 3.2 Risk Classification Before Command Construction

This is a critical correction. The framework must determine:

```
risk classification
        ↓
clipboard eligibility
        ↓
command construction
```

not:

```
construct command
        ↓
discover sensitive data
        ↓
try to remove clipboard
```

The latter is vulnerable to exactly the false-negative problem the two-stage model (3.3) is intended to address. Therefore:

> Clipboard eligibility must be decided before the command is emitted.

For a sensitive step: `Risk = credential/privileged-data` → `Clipboard = FORCED OFF`.
For a non-sensitive step with auto-copy enabled: `Risk = eligible` → `Clipboard = ON`.
For normal manual mode: `Risk = eligible` → `Clipboard = OFF unless runcopy explicitly requested`.

### 3.3 Two-Stage Inspection Model

This should become an independent feature specification (`v1/feature/inspection.md`).

Stage 1 should not be described merely as "the command executes normally." It should explicitly establish:

```
Stage 1:
execute
→ display terminal output
→ capture output
→ assign ledger index
→ persist ledger record
```

Then:

```
Stage 2:
human inspects
→ selects index/range
→ invokes extractor
→ selected content enters clipboard
```

The key architectural property:

> Execution and clipboard transfer are separate operations.

That is the important security improvement.

### 3.4 Session Ledger Format & Lifecycle

The proposed `~/.cache/stepwise/ledger.log` needs a stronger lifecycle definition. At minimum:

```
session start
    ↓
create/initialize ledger
    ↓
step executes
    ↓
append immutable entry
    ↓
assign index
    ↓
human inspects
    ↓
optional extraction
```

Each record should contain enough metadata to identify it, for example:

```
=== STEP 17 ===
timestamp: ...
session: ...
objective: ...
step: ...
exit_status: ...
risk: read-only
output:
...
=== END STEP 17 ===
```

Do not rely solely on `=== STEP 17 ===` — long-running or concurrent sessions could eventually create ambiguity.

### 3.5 Ledger Session Isolation

This is another requirement missing from the originally supplied implementation. A global `~/.cache/stepwise/ledger.log` creates collision and contamination risks. At minimum, 1.6.0 defines:

```
~/.cache/stepwise/sessions/<SESSION_ID>/ledger.log
```

with the active session determining the ledger:

```
~/.cache/stepwise/
└── sessions/
    └── <session-id>/
        ├── ledger.log
        └── metadata
```

`sw-copy-clip.sh` then operates against the active session ledger. This is substantially safer than one shared `ledger.log`.

### 3.6 Ledger Index Grammar

The extractor needs a formal grammar. Support:

```
5
12-15
18+
```

and no argument, for the final entry. Define precisely what these mean:

- `18+` → entry 18 through the final ledger entry
- `12-15` → entries 12, 13, 14, 15

Also define these as explicit validation cases:

- `0`
- negative integers
- `12-` (open start, no defined end — must be specified, not left implicit)
- `1-999999999`
- non-numeric input
- missing entries
- reversed ranges

### 3.7 Utility Implementation — Extend, Don't Fork

Only after the ledger format and session semantics (3.4–3.6) are frozen should the actual utility, `sw-copy-clip.sh`, be implemented.

The supplied pseudo-implementation has an important deficiency:

```
awk '/^=== STEP / {block=""} {block=block $0 "\n"} END {printf "%s", block}'
```

does not actually implement indexed extraction — it merely returns the final block.

Likewise, the stated fallback `xclip → pbcopy` doesn't match the existing v1 clipboard abstraction, which already specifies:

```
termux-clipboard-set → xclip → pbcopy → clip.exe
```

with a no-op notice when none are available (`v1/utils/clipcopy.sh`).

Therefore 1.6.0 should either:

1. extend `v1/utils/clipcopy.sh` with ledger-aware indexed extraction; or
2. deliberately replace it with a documented 1.6.0 abstraction, if the ledger model turns out incompatible with the existing `runcopy` interface.

**Do not create two competing clipboard implementations.** Given `v1/utils/clipcopy.sh` already exists and passes its self-test, option 1 (extend) is the default path unless implementation reveals a concrete incompatibility.

### 3.8 Automatic Clipboard Injection

When `AUTO_CLIPBOARD_ENABLED=true` and the step is eligible, StepWise constructs the command so that terminal output and clipboard copy occur together — but terminal display must remain primary. This preserves the v1.5.0 invariant:

> clipboard is never a replacement for normal terminal output.

**Important:** automatic copy should be described as *automatic clipboard duplication*, never *automatic clipboard execution*. The framework must never imply that clipboard state authorizes execution.

### 3.9 Sensitive-Output Handling

The proposed safety override is directionally correct but needs stronger semantics. There are two separate questions:

- A. Is the COMMAND classified as sensitive?
- B. Could the OUTPUT contain sensitive information?

The framework cannot reliably guarantee B merely by classifying the command. Therefore 1.6.0 should state:

> `credential/privileged-data` classification forces clipboard bypass. However, command classification cannot guarantee that non-sensitive commands produce non-sensitive output.

That limitation is important. The two-stage ledger model (3.3) addresses this by making human inspection the final authorization for copying ledger content — the human, not the classifier, is the last line of defense against exactly this gap.

### 3.10 Ledger vs. Output Validation

The ledger must not interfere with StepWise's existing evidence model. v1.5.0 requires shell output to remain primary evidence and validates results against numbered expected-output markers. Therefore:

```
terminal output
      │
      ├──► StepWise validation
      │
      └──► session ledger
```

not:

```
ledger
   ↓
validation
```

The ledger is an auxiliary artifact, not authoritative state.

---

## Phase 4 — Contextual Memory Integration

### 4.1 New State Fields

The existing contextual memory already tracks: Objective; Completeness Criteria; completed/skipped steps; verified state; human confirmations; constraints; failures; corrections; affected paths; warnings; remaining objectives.

1.6.0 adds only the minimum new state:

```
session_id
auto_clipboard_enabled
ledger_path
next_ledger_index
context tiers loaded
```

Do not put entire ledger contents into contextual memory — that would defeat the context-footprint objective (Phase 1.9).

### 4.2 Context Compaction Rules

This is essential to the three-tier architecture. The agent should not carry full historical outputs indefinitely. Instead:

```
Raw shell output
      ↓
validation
      ↓
relevant state extracted
      ↓
compact contextual memory
      ↓
raw output remains in ledger
```

Thus: `Context = state`, `Ledger = historical evidence`. This is a very important separation.

For example, the model does not need to retain 30 KB of a git diff after establishing `working tree clean`, `commit abc123 verified` — the raw evidence remains externally available in the ledger.

---

End of Part 2 (Phases 3–4). Continue with Part 3 — Workflow, Verification & Release (`sw-1.6.0-upgrade-03-VERIFICATION.md`), Phase 5 — Workflow Integration & Final Architecture.
