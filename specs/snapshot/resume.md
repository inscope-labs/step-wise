# Spec: Snapshot Resume

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `snapshot/resume` |
| Version | 1.6.1-dev |
| Parent feature | `feature:snapshot` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

## 1. Normative resume flow

1. Locate snapshot
2. Acquire state lock
3. Parse with strict schema
4. Reject malformed or unknown schema
5. Verify integrity if integrity metadata exists
6. Verify task identity
7. Verify framework/feature compatibility
8. Inspect current repository and environment
9. Compare saved state against live state
10. Identify material divergences
11. Revalidate required facts and evidence
12. Reconstruct bounded current Contextual Memory
13. Initialise current Session State from current defaults
14. Present RESUME BRIEF
15. Continue through the normal StepWise interaction loop

Resume must **never** execute a persisted `next_action`.

## 2. Resume Brief

The Brief is the sole automatic output of a successful resume. It reports:

- task identity and repository
- snapshot creation time and revision
- last checkpoint / historical status
- current reconciliation results (matched / changed / missing)
- unresolved warnings and criteria status
- the historical next action (as data only)
- explicit note that snapshot state is historical and has not authorised execution

## 3. Task switching

`stepwise switch <task-id>` performs: save source task → mark paused → validate and reconcile target → reconstruct context → set target active → present Resume Brief. No repository mutation occurs. Tasks remain independent; no inheritance of objective, scope, evidence, criteria, warnings, authorization or confirmation state is permitted.

## 4. Failure modes (minimum set)

```
SNAPSHOT_NOT_FOUND
SNAPSHOT_MALFORMED
SCHEMA_UNSUPPORTED
INTEGRITY_FAILURE
TASK_ID_MISMATCH
FEATURE_INCOMPATIBLE
ENVIRONMENT_CHANGED
REPOSITORY_MISSING
REPOSITORY_IDENTITY_CHANGED
BRANCH_CHANGED
HEAD_CHANGED
WORKTREE_CHANGED
EVIDENCE_UNAVAILABLE
LOCK_CONFLICT
MIGRATION_REQUIRED
```

A failure must not result in silent fallback to unvalidated state.
