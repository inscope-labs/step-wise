# Spec: Snapshot Lifecycle

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `snapshot/lifecycle` |
| Version | 1.6.1-dev |
| Parent feature | `feature:snapshot` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

## 1. Task and session states

**Task states:** `active`, `paused`, `completed`, `blocked`, `aborted`  
**Session states:** `open`, `suspended`, `closed`

Legal combinations are explicitly validated. A closed session with an active task is invalid. A task may remain paused across many sessions.

## 2. Save

`stepwise save` (or the equivalent `sw:snapshot/save`) writes the current mutable resumable state as a new immutable snapshot revision. The write is atomic:

1. write temporary state file
2. flush/sync
3. atomically replace previous state
4. append corresponding event
5. flush/sync event log

Crash recovery must present discrepancies rather than silently choosing a side.

## 3. Event log

Separate append-only log (preferred JSONL):

```
.stepwise/events.jsonl
```

Each event carries: monotonic sequence, event_id, timestamp, event type, task_id, session_id, resulting state revision where applicable. The log is for lifecycle history, debugging, audit and recovery; it is not Contextual Memory and is not loaded by default.

## 4. Locking

A state lock prevents simultaneous writers. Lock metadata records session_id, process_id, host and acquired_at. A lock is not considered stale solely by age. Breaking a lock requires human confirmation and records an event. OS-level advisory locking is preferred where available.

## 5. Retention

Snapshots are immutable. Retention policy defines maximum number, optional maximum age, maximum storage size and pruning behaviour. Automatic pruning must never delete the current active snapshot or the only recoverable snapshot. Event history has an independent retention policy.

## 6. Commands (normative surface)

- `stepwise save [--task <id>] [--message <note>]`
- `stepwise pause [--task <id>] [--reason <reason>]`
- `stepwise task list`
- `stepwise task add / remove` (subject to Objective Clarification Gate and confirmation)
- `stepwise state validate / diff / export / reset` (destructive forms require confirmation)
- `stepwise profile --show / --set` (session-scoped only)

The exact operator-facing names may follow the `sw:snapshot/` pattern for consistency with existing features; the behaviour above is normative.
