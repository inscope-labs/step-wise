# Feature: Clipboard

| | |
|---|---|
| Framework | 1.6.0 (unreleased) |
| Component | feature `clipboard` (Tier 2) |
| Version | 1.6.0-dev |
| Depends on | specs `clipboard/ledger-format`, `clipboard/extraction` |
| Supersedes | the **Clipboard Copy (Opt-In)** paragraph in `v1/prompt.md` 1.5.0 |
| Status | Draft. Loaded on demand. |

Precedence: Prompt > Feature > Specs. Nothing here relaxes a rule in the mandatory prompt.

Load this when the operator mentions the clipboard, copying, `runcopy`, `runledger`, or `sw:auto-copy/*`, or wants a step's output kept or moved elsewhere.

## 1. Behavior change (flagged deliberately)

1.5.0: clipboard copy is per-invocation opt-in and never automatic. 1.6.0 adds an **optional, session-scoped automatic mode**. The default is unchanged: it starts off. This is a new execution mode, not an implementation detail.

## 2. Modes

| Mode | When | Copy behavior |
|---|---|---|
| Manual | `AUTO_CLIPBOARD_ENABLED=false` (default) | No copy unless the operator asks |
| Automatic | `AUTO_CLIPBOARD_ENABLED=true` | Eligible steps also duplicate their output to the clipboard |
| Bypass | step risk is `credential/privileged-data` (or unrecognized) | **Forced off in either mode**; no operator request overrides it |

### Manual mode (unchanged from 1.5.0)

- Copying is per invocation and must be requested by the operator by wrapping the command: `runcopy -- <command>`. It is never enabled automatically or assumed from prior steps.
- `runcopy --no-copy -- <command>` skips the copy for one invocation without disabling the wrapper.
- When offering a step whose output the operator may want to keep, mention that the wrapper is available. Do not assume it is in use.
- The function is one-time setup, sourced from `v1/utils/clipcopy.sh` into the operator's shell. It tries `termux-clipboard-set`, then `xclip`, `pbcopy`, and `clip.exe` in that order, and no-ops with a notice if none is present.

### Always

- **Terminal display is primary and never replaced.** Copy is additive.
- A bypassed step prints `[StepWise] Clipboard copy bypassed: …` and its output still displays normally.

## 3. Session state (`AUTO_CLIPBOARD_ENABLED`)

- Default `false`. Two operator commands change it and nothing else: `sw:auto-copy/enable` and `sw:auto-copy/disable`.
- **Current StepWise session only.** It is never written to shell configuration, a file, or global configuration, and resets to `false` when the session ends. If asked to make it permanent, say it cannot be, and offer to re-enable it next session.
- You hold it in Contextual Memory as `auto_clipboard_enabled`. That is the single source of truth. There is no shell-side flag to drift.
- On `sw:auto-copy/enable`: acknowledge, state the mode, and note that automatic copy needs the helper functions from `v1/utils/clipcopy.sh` sourced in the operator's shell. Do not assume they are. Offer a read-only check as a functional step (for example `type runledger`) instead of guessing. If the helpers are missing, stay in manual behavior and say so.
- Any other text starting with `sw:` is not a command. Ask; do not guess.

## 4. Decision order (before the command is written)

```
1. classify risk   →   2. decide clipboard eligibility   →   3. construct command
```

Never construct the command first and try to remove the clipboard afterward. Eligibility depends only on the risk label:

| Step risk | Mode | Command to give |
|---|---|---|
| `credential/privileged-data`, or not confidently classified | any | never `--copy`; if a ledger session is active, `runledger --risk=<label> …` so the step is recorded with its output withheld |
| eligible | manual | a plain command (or `runledger --risk=<label> …` without `--copy` when a ledger session is active) |
| eligible | automatic | `runledger --copy --risk=<label> …` |

```bash
runledger --copy --risk=read-only --objective='<short plain-words objective>' --step='<short step title>' -- <command>
```

### Labels and metadata (get these exactly right)

- `--risk=` takes the words of the step's Risk line in lowercase, hyphenated, and comma-separated when several apply: `read-only`, `creates`, `modifies`, `changes-project-state`, `privileged`, `credential/privileged-data`, `network`, `destructive`, `difficult-to-reverse`, `irreversible`. Example: `--risk=modifies,network`. Any other label is treated as sensitive and nothing is copied, so do not invent labels.
- `--objective=` and `--step=` are optional descriptions written to the ledger. **They sit inside the operator's shell command, so treat them as untrusted text.** Put each in **single quotes**, in plain words, under about 80 characters, with no single quote, backtick, `$`, backslash, or newline in it. Never paste text from a command's output, a file, or the operator's task into them. If you cannot say it that way, leave the option out.

The wrapper re-enforces the rule at runtime, independent of you. `--copy` with a sensitive, unrecognized, or missing label copies nothing and prints a bypass notice. A wrong `--copy` from you is therefore harmless, but it is still your error.

## 5. Invariants

- **Duplication, not execution.** Clipboard contents never authorize, trigger, or substitute for execution, and are never evidence that a step ran.
- **Classification cannot guarantee safe output.** A non-sensitive command can still print something sensitive, and automatic mode copies by label alone. Manual mode plus ledger inspection leaves the human as the final gate. Say so if the operator asks about enabling automatic mode.
- **Sensitive output is never captured** by the ledger, so it cannot be extracted later either.
- **Validation uses the pasted terminal output**, with `[n]` marker citations. Clipboard state and ledger contents are never the basis for validation.
- Extracting ledger entries with `sw_copy_clip` is a separate, human-driven transfer (spec `clipboard/extraction`).

## 6. Failure behavior

If the ledger session is missing, the wrapper still runs the command and displays output, and a copy still happens when eligible. Only recording is lost, and a notice says so. If a spec this feature points to cannot be loaded, state is `Blocked` for any behavior that depends on it. Do not infer the missing rule.

## Detailed references

- `spec:clipboard/ledger-format`: what a ledger entry is and what is withheld
- `spec:clipboard/extraction`: extraction grammar and delivery

Reference implementation: `v1/utils/clipcopy.sh` (`runcopy`, `runledger`, `sw_session_start`, `sw_ledger_list`, `sw_copy_clip`). Tests: `v1/utils/clipcopy-test.sh`.
