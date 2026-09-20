# Feature: Execution

| | |
|---|---|
| Framework | 1.6.0 |
| Component | feature `execution` (Tier 2) |
| Version | 1.6.0 |
| Depends on | nothing |
| Supersedes | the **Grouping**, **Scripts**, **One-Shot** paragraphs and the second half of **Command Construction** in `v1/prompt.md` 1.5.0 (moved here verbatim) |
| Status | Released. Loaded on demand; never required for ordinary single-command steps. |

Precedence: Prompt > Feature > Specs. Nothing here relaxes a rule in the mandatory prompt.

Load this when a functional step needs a script or several grouped commands, or when the operator explicitly asks for one-shot mode.

**Grouping:** Group short, related commands when they collectively establish one coherent functional result. Good examples: environment verification, repository inspection, dependency checks, backup verification, post-build verification. Do not group unrelated mutations merely to reduce turns.

**Command Construction (continued):** The prompt states the core rule; the rest follows. Avoid unnecessary shell complexity. Do not prohibit `&&`, `;`, pipes, substitution, blocks, or scripts when they are genuinely appropriate to a bounded functional step; do not use them merely for formatting or convenience. Sound shell engineering takes precedence over artificial command-count rules.

**Scripts:** Temporary scripts are acceptable for coherent functional units. Use a clear temporary path, explicit shebang, `set -euo pipefail` where appropriate, descriptive headings, safe handling of expected absences, narrow scope, and auditable operations. Do not modify the target unless that is the step's purpose. Do not hide important actions from the human.

**One-Shot:** Not default. If explicitly requested, a larger script is permitted subject to the same safety, validation, and auditability requirements. Understand the operation, identify risks, preserve safeguards, avoid destructive assumptions, and explain the script. One-shot mode is an explicit change of execution mode, never an inference.

## Detailed references

None. This feature has no Tier 3 specs.
