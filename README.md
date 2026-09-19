# StepWise

**Evidence-driven, human-in-the-loop Linux shell assistance.**

StepWise is a prompt framework and execution protocol for AI-assisted Linux shell work.  
It keeps the human operator in full control of the shell while the AI provides disciplined guidance, risk classification, validation, and adaptive troubleshooting.

The AI proposes. The human executes.

**Status:** `1.5.0` — internal pre-release. All `1.x` releases are minor/patch revisions of the same generation; the framework moves to `2.0.0` only once it has been fully tested end-to-end. See [`CHANGELOG.md`](CHANGELOG.md) for version history.

**In progress:** `1.6.0` (see the *Unreleased* section of the changelog). `v1/prompt.md` is still `1.5.0`. The session-ledger utilities described under [Session Ledger (1.6.0 preview)](#session-ledger-160-preview) exist and are tested, but the prompt does not use them yet, so the assistant will not emit those commands.

---

## Core Idea

Traditional AI coding assistants often assume they can run commands or treat success as automatic.  
StepWise inverts that model:

- Every action is a **functional step** with a clear objective.
- Risk is classified before execution.
- Shell output is the primary evidence of state.
- Progression is blocked until evidence is validated (or an allowed skip occurs).
- Destructive, privileged, or irreversible operations always require explicit human confirmation.
- The agent never pretends to have executed a command.

---

## Getting Started

1. Copy the full protocol from [`v1/prompt.md`](v1/prompt.md) into your AI system prompt (or the equivalent configuration for your tool).

2. **(Optional)** If your tool has a separate short system-prompt / custom-instruction field, you can use the following initial-invocation prompt:

   ```text
   # StepWise — Interactive Execution Assistant

   You are operating under StepWise, a prompt framework for AI-assisted Linux shell work.

   **Intent:** Keep the human in control of the shell while you provide disciplined, evidence-driven guidance. You propose; the human executes.

   **Core rules:**
   - Before any discovery or baseline work: run the Objective Clarification Gate (confirm a concrete, testable Objective) and the Completeness Criteria Wizard (propose and get explicit accept/edit/reject on a CompletenessCriteria list — `skip` is never valid on this step).
   - Guide the operator one functional step at a time, with expected output shown as a numbered `BEGIN EXPECTED`/`END EXPECTED` block.
   - Classify risk for every step: read-only, creates files, modifies files, privileged, credential/privileged-data, network, destructive, difficult to reverse, irreversible.
   - Verify state from shell output. Human confirmation is only evidence of the operator’s assertion, not system-verified fact. When pasted output doesn't match, cite the specific `[n]` marker(s) that failed.
   - Never advance past unresolved failure or missing required evidence.
   - `skip` may bypass optional steps only — never mandatory safety checks, required validation, destructive confirmations, or Completeness Criteria.
   - Request explicit confirmation before consequential or destructive operations.
   - Preserve existing work; never silently overwrite, reset, or delete.
   - Stay strictly within the stated task.
   - Clipboard copy of a step's output is opt-in only (see `v1/utils/clipcopy.sh`), and is always auto-bypassed with a notice on any step classified credential/privileged-data.

   **Execution model:**
   Require task → Objective Clarification Gate → Completeness Criteria Wizard → Discover → baseline → define functional step → present → human executes → receive output → analyze (citing `[n]` markers) → validate → adapt → proceed.

   **Core principles:** Evidence over assumption. Human execution over implied autonomy. Safety over speed. Clarity over complexity.

   Full protocol: https://raw.githubusercontent.com/inscope-labs/step-wise/main/v1/prompt.md

   Acknowledge that you are operating under StepWise.  
   State that a concrete task is required, then wait for the operator’s task.


3. Start a new conversation and state a concrete task.  
   Example: “Set up a Python virtual environment and install the dependencies listed in requirements.txt.”

4. The assistant will confirm the task, then begin with safe discovery or baseline steps.  
   Execute the proposed commands in your own terminal and paste the complete output back.

5. Continue step by step until the objective is verified against agreed completeness criteria.

The assistant never runs commands itself. You remain in full control of the shell at every moment.

## Manual Workflow: Clipboard Copy (Optional)

Clipboard copy is never automatic — it's a manual, opt-in convenience you enable yourself, per command. Setup:

1. Source the wrapper once per shell session:
   ```bash
   source v1/utils/clipcopy.sh
   ```
2. Run any command through it to display output normally **and** copy it:
   ```bash
   runcopy -- <command>
   ```
3. Skip the copy for a single invocation without disabling the wrapper:
   ```bash
   runcopy --no-copy -- <command>
   ```
4. Nothing else to configure — the wrapper auto-detects `termux-clipboard-set`, `xclip`, `pbcopy`, or `clip.exe`, in that order, and prints a notice if none are found.

Any step the assistant classifies `credential/privileged-data` under **Safety** has clipboard copy bypassed automatically, whether you run it through `runcopy` or not — you'll see a `[StepWise] Clipboard copy bypassed: ...` notice on stderr, and the output still displays normally. The script also accepts `credential` and `privileged-data` on their own.

The bypass is **fail-closed**: `runcopy --risk=<label>` copies only for known non-sensitive labels (`read-only`, `creates`, `modifies`, `network`, `destructive`, and so on). Sensitive labels (in any letter case) and any unrecognized label are bypassed. A later `--risk` flag cannot override an earlier sensitive one. Leaving `--risk` off means you wrapped the command by hand and asked for a copy, exactly as in 1.5.0. You can verify the bypass yourself:
```bash
bash v1/utils/clipcopy.sh
```
This runs the script's self-test, which confirms the bypass notice fires and terminal display is preserved for the combined label, a case variant, and unrecognized labels. The full suite, which uses a stub clipboard and touches neither your real clipboard nor `~/.cache/stepwise`, is:
```bash
bash v1/utils/clipcopy-test.sh
```

## Session Ledger (1.6.0 preview)

> **Preview.** Implemented and tested in `v1/utils/clipcopy.sh`, but not yet part of the protocol in `v1/prompt.md`. Design: [`docs/1.6.0-plan/`](docs/1.6.0-plan/), [`v1/specs/clipboard/`](v1/specs/clipboard/), [`v1/feature/clipboard.md`](v1/feature/clipboard.md).

The ledger keeps each step's raw output outside the chat, so you can inspect it and copy exactly what you choose. Running a command and copying its output are separate operations.

```bash
source v1/utils/clipcopy.sh
sw_session_start                                          # once per shell
runledger --risk=read-only --step="git status" -- git status
sw_ledger_list                                            # what has been recorded
sw_copy_clip                                              # copy the final entry
```

`sw_copy_clip [--stdout] [spec]` selects entries by index. `--stdout` prints instead of copying.

| Spec | Meaning |
|---|---|
| *(none)* | the final entry |
| `5` | entry 5 |
| `12-15` | entries 12 through 15 |
| `18+` | entry 18 through the final entry |

Anything else (`0`, negatives, `12-`, reversed ranges, out-of-range entries, non-numeric input) fails with a message and copies nothing. Extraction is all-or-nothing.

For automatic clipboard duplication, add `--copy`: `runledger --copy --risk=<label> -- <command>`. The decision is made from the label before the command runs. A sensitive, unrecognized, or missing label copies nothing. Terminal display and the command's exit status are never affected. It is off unless you pass `--copy`.

Properties worth knowing:

- Output of a step labeled sensitive or unrecognized is **never written to the ledger**, and the extractor refuses such entries even if a record is hand-edited.
- The command line is not recorded, since commands can embed secrets. Only the `--step` description is.
- Each shell has its own session (`SW_SESSION_ID`), stored under `~/.cache/stepwise/sessions/<id>/` with `0700`/`0600` permissions. There is no global ledger.
- A ledger failure never blocks the command, and never changes what you see or its exit status.
- Limits: output is captured as combined stdout and stderr through a pipe, like `runcopy`, so interactive programs, pagers, and terminal colors are not supported. A label describes the *command*, so it cannot tell you a non-sensitive command printed something sensitive — inspect an entry before extracting it.

## Examples

An end-to-end worked transcript (Objective Clarification Gate → Completeness Criteria Wizard → an annotated functional step → a deliberately mismatched paste-back citing `[n]` markers → completion against CompletenessCriteria) is planned but **not yet included** — status: pending. Its absence is not evidence the protocol works end-to-end; see `CHANGELOG.md` for what has and hasn't been verified.

## Execution Model

```text
Discover → Establish baseline → Define functional step → Present commands
→ Human executes → Receive output → Analyze → Validate state → Adapt → Proceed