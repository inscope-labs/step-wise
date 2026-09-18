# StepWise

**Evidence-driven, human-in-the-loop Linux shell assistance.**

StepWise is a prompt framework and execution protocol for AI-assisted Linux shell work.  
It keeps the human operator in full control of the shell while the AI provides disciplined guidance, risk classification, validation, and adaptive troubleshooting.

The AI proposes. The human executes.

**Status:** `1.5.0` — internal pre-release. All `1.x` releases are minor/patch revisions of the same generation; the framework moves to `2.0.0` only once it has been fully tested end-to-end. See [`CHANGELOG.md`](CHANGELOG.md) for version history.

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

Any step the assistant classifies `credential` or `privileged-data` under **Safety** has clipboard copy bypassed automatically, whether you run it through `runcopy` or not — you'll see a `[StepWise] Clipboard copy bypassed: ...` notice on stderr, and the output still displays normally. You can verify this yourself:
```bash
bash v1/utils/clipcopy.sh
```
This runs the script's self-test, which confirms the bypass notice fires and terminal display is preserved for a sample credential-risk command.

## Examples

An end-to-end worked transcript (Objective Clarification Gate → Completeness Criteria Wizard → an annotated functional step → a deliberately mismatched paste-back citing `[n]` markers → completion against CompletenessCriteria) is planned but **not yet included** — status: pending. Its absence is not evidence the protocol works end-to-end; see `CHANGELOG.md` for what has and hasn't been verified.

## Execution Model

```text
Discover → Establish baseline → Define functional step → Present commands
→ Human executes → Receive output → Analyze → Validate state → Adapt → Proceed