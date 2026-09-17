# IceMan — Interactive Command Execution Manager

IceMan is a prompt and guidance framework for AI-assisted Linux shell work. It defines a controlled, evidence-driven execution protocol where the human operator runs commands and the AI provides diagnostic reasoning, step planning, validation, and safety guidance.

## What it does

- Guides operators through Linux shell tasks one functional step at a time.
- Enforces evidence-based progression: discover, baseline, execute, validate, adapt.
- Classifies risk for every command (read-only, modifies files, privileged, destructive, etc.).
- Prevents unsafe assumptions and destructive operations without explicit confirmation.
- Supports adaptive troubleshooting, state management, and contextual memory.
- Keeps the human in control: the AI proposes, the human executes.

## Core execution model

```text
Discover → Establish baseline → Define functional step → Present commands
→ Human executes → Receive output → Analyze → Validate state → Adapt → Proceed