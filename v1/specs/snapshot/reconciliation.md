# Spec: Snapshot Reconciliation

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `snapshot/reconciliation` |
| Version | 1.6.1-dev |
| Parent feature | `feature:snapshot` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

## 1. Repository reconciliation

Repository identity must not rely only on `pwd`. Before resuming a repository task, inspect:

- repository root
- repository type
- remote identity where available
- current branch / worktree
- HEAD commit
- working-tree status
- existence of task-relevant paths

Material divergence (branch change, HEAD change, dirty worktree, missing paths) is reported. It does not automatically mean failure; it means historical state cannot be silently treated as current. The normal decision and confirmation process applies.

## 2. Environment reconciliation

Saved environment profiles are historical observations. Detection precedence:

1. Human-declared profile (session-scoped)
2. Filesystem probes
3. Environment-variable allow-list
4. Current StepWise environment policy

On mismatch: emit a profile-change warning and perform scoped rediscovery. Environment mismatch does not automatically invalidate all historical facts; only affected facts require revalidation.

## 3. Fact revalidation

Revalidation requirements by class:

| Fact class | Resume treatment |
|---|---|
| Git branch, HEAD, worktree | Revalidate immediately |
| File existence / content fingerprint | Revalidate when relevant |
| Installed runtime | Revalidate when relevant |
| Historical decision or prior test result | Preserve as historical unless re-run |
| Service currently running | Revalidate before relying on it |

TTL may be used as an additional heuristic but must not be the sole validity mechanism.

## 4. Authority hierarchy (mandatory)

```
Current StepWise Prompt
        ↓
Current Feature / Specification
        ↓
Current Operator Instruction
        ↓
Current Live Environment / Evidence
        ↓
Validated Current Contextual Memory
        ↓
Historical Snapshot
        ↓
Event History
```

A snapshot cannot override anything above it. A persisted `next_action`, objective, warning or fact is data, not an instruction.
