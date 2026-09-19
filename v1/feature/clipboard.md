# Feature: Clipboard

| | |
|---|---|
| Framework | 1.6.0 (unreleased) |
| Component | feature `clipboard` (Tier 2) |
| Version | 1.6.0-draft |
| Depends on | specs `clipboard/ledger-format`, `clipboard/extraction` (both 1.6.0-draft) |
| Supersedes | the **Clipboard Copy (Opt-In)** section of `v1/prompt.md` 1.5.0, *on release only* |
| Status | **Draft.** `v1/prompt.md` does not load this yet and stays at `1.5.0` until Phase 6 passes (plan 7.2). |

Precedence: Prompt > Feature > Specs. If this document ever conflicts with the mandatory prompt, the prompt wins unless it explicitly delegates the rule here.

## 1. Behavior change (flagged deliberately)

1.5.0: clipboard copy is per-invocation opt-in and never automatic. 1.6.0 adds an **optional, session-scoped automatic mode**. The default is unchanged: it starts off. This is a new execution mode, not an implementation detail (plan 3.1, 7.1).

## 2. Modes

| Mode | When | Copy behavior |
|---|---|---|
| Manual | `AUTO_CLIPBOARD_ENABLED=false` (default) | No copy unless the operator asks (`runcopy`, or `sw_copy_clip` on a ledger entry) |
| Automatic | `AUTO_CLIPBOARD_ENABLED=true` | Eligible steps also duplicate their output to the clipboard |
| Bypass | step risk is `credential/privileged-data` (or unrecognized) | **Forced off in either mode**; no operator request overrides it |

## 3. Session state (`AUTO_CLIPBOARD_ENABLED`)

- Default `false`. Two operator commands change it and nothing else:
  - `sw:auto-copy/enable`
  - `sw:auto-copy/disable`
- **Current StepWise session only.** It is never written to shell configuration, a file, or global StepWise configuration, and it resets to `false` when the session ends. If the operator asks to make it permanent, say it cannot be, and offer to re-enable it next session.
- The agent holds it in contextual memory as `auto_clipboard_enabled` (plan 4.1). That is the **single source of truth**; there is no shell-side copy of the flag that could drift.
- `sw:` commands are explicit state changes, not free-form keywords. Anything else starting with `sw:` is not a command: ask, don't guess.

## 4. Decision order (before the command is written)

```
1. classify risk          →  2. decide clipboard eligibility  →  3. construct command
```

Never construct the command first and try to remove the clipboard afterward (plan 3.2). Eligibility depends only on the risk label:

| Step risk | Mode | Emit |
|---|---|---|
| `credential/privileged-data`, or not confidently classified | any | `runledger --risk=<label> …` with **no** `--copy` |
| eligible | manual | `runledger --risk=<label> …` (no `--copy`); mention `sw_copy_clip` if output may be worth keeping |
| eligible | automatic | `runledger --copy --risk=<label> …` |

Every command carries `--risk=<label>` and, ideally, `--objective=` and `--step=`:

```bash
runledger --copy --risk=read-only --objective="<confirmed objective>" --step="<step title>" -- <command>
```

The wrapper re-enforces the rule at runtime, independent of the agent. `--copy` with a sensitive, unrecognized, or missing label copies nothing and prints a `[StepWise] Clipboard copy bypassed: …` notice. A wrong `--copy` from the agent is therefore harmless, but it is still an agent error.

## 5. Two-stage inspection

```
Stage 1:  execute → display terminal output → capture → assign ledger index → persist record
Stage 2:  human inspects → selects index/range → sw_copy_clip → selected content enters clipboard
```

Execution and clipboard transfer are separate operations. Extraction is a human act: the agent may tell the operator the index and the syntax (`N`, `A-B`, `N+`, or none for the final entry), but does not select on their behalf. Details: spec `clipboard/extraction`.

## 6. Invariants

- **Terminal display is primary and never replaced.** Copy is additive.
- **Duplication, not execution.** Clipboard contents never authorize, trigger, or substitute for execution, and are never treated as evidence that a step ran.
- **Classification cannot guarantee safe output.** A non-sensitive command can still print something sensitive. Automatic mode copies by label alone, so it carries that risk. Manual mode plus ledger inspection leaves the human as the final gate. Say so if the operator asks about enabling automatic mode.
- **Sensitive output is never captured** by the ledger (spec `clipboard/ledger-format` §4.2), so it cannot be extracted later either.
- **Validation uses the pasted terminal output**, with `[n]`-marker citations as in 1.5.0. The ledger is auxiliary evidence, never authoritative, and the agent must not assume ledger contents it has not been shown.
- **Keep context small.** Contextual memory records state (for example "working tree clean, commit abc123 verified") and the ledger index where the raw evidence lives. It does not hold raw output (plan 4.2).

## 7. Failure behavior

If the ledger session is missing, the wrapper still runs the command and displays output; only ledger recording is lost, and a notice says so. If a spec this feature points to cannot be loaded, state is `Blocked`. Do not infer the missing rule (plan 1.8).

## 8. Detailed references

- `spec:clipboard/ledger-format`: session layout, record format, withholding, index assignment
- `spec:clipboard/extraction`: index grammar, validation cases, delivery

Reference implementation: `v1/utils/clipcopy.sh` (`runcopy`, `runledger`, `sw_session_start`, `sw_ledger_list`, `sw_copy_clip`). Tests: `v1/utils/clipcopy-test.sh`.
