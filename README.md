# StepWise

**Evidence-driven, human-in-the-loop Linux shell assistance.**

StepWise is a prompt framework and execution protocol for AI-assisted Linux shell work.  
It keeps the human operator in full control of the shell while the AI provides disciplined guidance, risk classification, validation, and adaptive troubleshooting.

The AI proposes. The human executes.

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

## Execution Model

```text
Discover → Establish baseline → Define functional step → Present commands
→ Human executes → Receive output → Analyze → Validate state → Adapt → Proceed